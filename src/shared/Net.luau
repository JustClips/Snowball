--!strict
-- All remotes in one place. The server creates them in ReplicatedStorage.Remotes;
-- clients wait for them. Every client -> server call is rate limited here.
-- (Ported from Sweep the World: same API, new remote list.)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- name = max calls per second from one client (0 = server -> client only)
local EVENTS: { [string]: number } = {
	PlayerState = 0, -- server -> owner: full PlayerSnapshot
	Notify = 0, -- server -> one: short toast (text, kind?)
	Announce = 0, -- server -> all: server-wide message
	-- Training (TrainService / PopService)
	PowerGained = 0, -- server -> owner: (amount BigNum, taps) for the "+N" floaters
	PopShown = 0, -- server -> owner: (id, tierId, x 0-1, y 0-1, seconds, priceText?) a Snow Pop
	PopGone = 0, -- server -> owner: (id, claimed: bool, reward?) the pop ended
	ClaimPop = 6, -- client: (id) tapped the live pop
	-- Rolling (RollService)
	PackStart = 0, -- server -> owner: (serverClock, period, greenWidth) the pack meter started
	PackTap = 3, -- client: (clientClockAtTap) stop the pack meter
	Steer = 11, -- client: (value -1..1) at most 10/s are used
	RunStarted = 0, -- server -> all: (userId, runInfo) a ball left the deck
	RunSnapshot = 0, -- server -> all: buffer of every rolling ball (10 Hz)
	RunEvent = 0, -- server -> all: (userId, kind, data) Pickup / Smash / Bonk / Zone / Full
	RunEnded = 0, -- server -> all: (userId, result) the ball cracked
	RunStopped = 0, -- server -> owner: { Distance, Seconds, Product, Price, Push, NextZone?, ToNext, Extra, Best } keep rolling?
	RunContinued = 0, -- server -> all: (userId, { S, D, V, Limit, Seed, IdBase }) a Keep Rolling push
	DeclineContinue = 2, -- client: no thanks, crack the ball now
	ShowOffer = 0, -- server -> owner: { Key, Product?, Title, Text, Price?, Open? } offer popup
	OpenShop = 0, -- server -> owner: open the Shop at a section (3rd "not enough cash")
	Purchased = 0, -- server -> one: (product or pass key, { From?, To? }) celebration
	HatchCompleted = 0, -- server -> owner: { Uid, PetId, Rarity, EggRarity, X, Z, Weight, Income, IsNew, Placed, ... } the hatch show
	HatchShown = 0, -- server -> everyone: { UserId, Uid, PetId, Rarity, X, Z, ... } a short show at their base
	WelcomeBack = 0, -- server -> owner: offline income payload
	-- Egg rescue (EggRescueService)
	RescueEvent = 0, -- server -> owner: (kind, data) Start / Grab / Saved / Knocked / Wake / Ended
	-- Leaderboards (LeaderboardService)
	RankEvent = 0, -- server -> owner: { Kind = "Passed", Board, Scope = World|Week|Server, UserId, Name, Rank? }
	ServerRecord = 0, -- server -> all: { Board, UserId, Name, Score } new best roll / luckiest roll in this server
	Analytics = 6, -- client: ("Loaded") loading screen gone, ("Open", screenName) a window opened
}

local FUNCTIONS: { [string]: number } = {
	GetState = 2,
	BuyRoller = 4, -- () -> ok, message: buy the next cash Snow Roller
	StopTraining = 2, -- () -> ok: the STOP button, steps you off your roller
	Rewards = 4, -- (action, arg?) -> ok, message, extra: see RewardService
	RedeemCode = 2, -- (code) -> ok, message
	Rebirth = 2, -- () -> ok, message: see RebirthService
	BuyUpgrade = 6, -- (upgradeId) -> ok, message: Core / EggSlots / PetSlots / PackZone
	StartPack = 2, -- () -> ok, message: step onto the launch deck and start packing
	CancelPack = 2,
	Teleport = 3, -- ("Base" | "Deck" | "Roller") -> ok
	PromptPurchase = 4, -- (productKey, giftToUserId?) -> ok, message
	Pets = 10, -- (action, arg?) -> ok, message: see PetService / HatchService ACTIONS
	Admin = 8, -- (action, payload) -> ok, message: admins only, see AdminService
	Rescue = 3, -- ("Leave" | "Sled" | "Repel" | "Drop" i | "Pick" i) -> ok, message: see EggRescueService
	Leaderboards = 2, -- () -> { All = { key = score }, Week = {...} } your own scores (window "you" row)
}

local FOLDER_NAME = "Remotes"

local Net = {}
Net.Events = EVENTS
Net.Functions = FUNCTIONS

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			existing:Destroy()
		end
		local f = Instance.new("Folder")
		f.Name = FOLDER_NAME
		f.Parent = ReplicatedStorage
		folder = f
	else
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	end
	return folder :: Folder
end

-- Server: creates every remote. Call once before anything else uses Net.
function Net.setup()
	assert(RunService:IsServer(), "Net.setup is server only")
	local f = getFolder()
	for name in EVENTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = f
	end
	for name in FUNCTIONS do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = f
	end
end

function Net.event(name: string): RemoteEvent
	assert(EVENTS[name] ~= nil, "Unknown remote event " .. name)
	local f = getFolder()
	if RunService:IsServer() then
		return f:FindFirstChild(name) :: RemoteEvent
	end
	return f:WaitForChild(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	assert(FUNCTIONS[name] ~= nil, "Unknown remote function " .. name)
	local f = getFolder()
	if RunService:IsServer() then
		return f:FindFirstChild(name) :: RemoteFunction
	end
	return f:WaitForChild(name) :: RemoteFunction
end

-- Rate limiting (server side), one token bucket per player per remote.
local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}
local warned: { [string]: boolean } = {}

local function allow(player: Player, name: string, perSecond: number): boolean
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local now = os.clock()
	local bucket = playerBuckets[name]
	if not bucket then
		bucket = { tokens = perSecond, last = now }
		playerBuckets[name] = bucket
	end
	bucket.tokens = math.min(perSecond, bucket.tokens + (now - bucket.last) * perSecond)
	bucket.last = now
	if bucket.tokens < 1 then
		local key = player.UserId .. ":" .. name
		if not warned[key] then
			warned[key] = true
			warn(`[Net] {player.Name} is calling {name} too fast; extra calls are ignored`)
		end
		return false
	end
	bucket.tokens -= 1
	return true
end

if RunService:IsServer() then
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

function Net.onEvent(name: string, handler: (Player, ...any) -> ())
	local limit = EVENTS[name]
	assert(limit and limit > 0, name .. " is not a client -> server event")
	Net.event(name).OnServerEvent:Connect(function(player, ...)
		if allow(player, name, limit) then
			handler(player, ...)
		end
	end)
end

function Net.onInvoke(name: string, handler: (Player, ...any) -> ...any)
	local limit = FUNCTIONS[name]
	Net.func(name).OnServerInvoke = function(player, ...)
		if not allow(player, name, limit) then
			return false, "Slow down"
		end
		return handler(player, ...)
	end
end

function Net.fire(name: string, player: Player, ...: any)
	Net.event(name):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	Net.event(name):FireAllClients(...)
end

return Net
