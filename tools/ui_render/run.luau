--!nocheck
-- Runs the game's client UI code (src/client + src/shared) in Lune with a fake Roblox
-- (roblox.luau), opens one screen and dumps the PlayerGui to JSON for render.mjs.
--   lune run tools/ui_render/run.luau <scenario> <Phone|PC> <out.json>
-- Scenarios are at the bottom (hud, keeprolling, results, starter, shop, ...).
-- Run tools/ui_render/shots.sh to render every scenario on phone and PC.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local R = require("./roblox")
local Dump = require("./dump")

local scenario = process.args[1] or "hud"
local deviceName = process.args[2] or "PC"
local outPath = process.args[3] or "/tmp/ui_dump.json"
local ROOT = process.cwd:gsub("/$", "")
local VIEW = if deviceName == "Phone" then R.Vector2.new(844, 390) else R.Vector2.new(1280, 720)
-- ScreenGuis report the safe area (CoreUISafeInsets) as their AbsoluteSize, like Roblox.
R.DEFAULTS.ScreenGui.AbsoluteSize = if deviceName == "Phone" then R.Vector2.new(750, 329) else R.Vector2.new(1280, 662)

local Instance, Enum = R.Instance, R.Enum

-------------------------------------------------------------------------- world

local game = Instance.new("DataModel")
game.Name = "Game"
local services = {}
local function service(name, cls)
	local s = Instance.new(cls or name)
	s.Name = name
	s.Parent = game
	services[name] = s
	return s
end
for _, n in {
	"ReplicatedStorage", "Players", "Workspace", "TweenService", "RunService", "UserInputService", "GuiService",
	"SoundService", "ProximityPromptService", "MarketplaceService", "ContentProvider", "HttpService", "Lighting",
	"Debris", "CollectionService", "TextService", "StarterGui", "SocialService", "BadgeService", "StarterPlayer",
	"ContextActionService", "PhysicsService", "VRService", "PolicyService", "LocalizationService", "Teams",
	"AvatarEditorService", "AssetService", "TeleportService", "GroupService", "AnalyticsService", "Chat",
	"TextChatService", "HapticService", "ExperienceNotificationService",
} do
	service(n)
end
-- Waiting for something the server would make (EggModels, Bases...): an empty Folder.
for _, svc in services do
	R.state[svc].autoChild = function(name)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = svc
		return f
	end
end
local workspace = services.Workspace
local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.ViewportSize = VIEW
camera.Parent = workspace
workspace.CurrentCamera = camera
workspace.Gravity = 196.2
local terrain = Instance.new("Terrain")
terrain.Name = "Terrain"
terrain.Parent = workspace
services.UserInputService.TouchEnabled = deviceName == "Phone"
services.UserInputService.KeyboardEnabled = deviceName ~= "Phone"
services.UserInputService.MouseEnabled = deviceName ~= "Phone"
services.UserInputService.GamepadEnabled = false
services.GuiService.ReducedMotionEnabled = false
services.GuiService.TopbarInset = R.Rect.new(0, 0, 0, 0)
services.Lighting.ClockTime = 13

function game.GetService(_, name)
	return services[name] or service(name)
end
game.FindService = game.GetService
game.PlaceId = 0
game.JobId = "render"
game.GameId = 0
game.CreatorId = 0

local player = Instance.new("Player")
player.Name = "Dev"
player.DisplayName = "Dev"
player.UserId = 1
player.AccountAge = 30
player.MembershipType = Enum.MembershipType.None
player.Parent = services.Players
local playerGui = Instance.new("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = player
local backpack = Instance.new("Backpack")
backpack.Name = "Backpack"
backpack.Parent = player
services.Players.LocalPlayer = player
R.LocalPlayer = player

-- Rojo tree
local shared = R.mountFolder(ROOT .. "/src/shared", "Shared", services.ReplicatedStorage)
local sp = Instance.new("StarterPlayerScripts")
sp.Name = "StarterPlayerScripts"
sp.Parent = services.StarterPlayer
local client = R.mountFolder(ROOT .. "/src/client", "Client", sp)

-- Remotes (names from Net.luau)
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local netSrc = fs.readFile(ROOT .. "/src/shared/Net.luau")
local evBlock = netSrc:match("local EVENTS[^\n]*\n(.-)\n}")
local fnBlock = netSrc:match("local FUNCTIONS[^\n]*\n(.-)\n}")
for name in evBlock:gmatch("\n?%s*([%w_]+) = %d+,") do
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = remotes
end
for name in fnBlock:gmatch("\n?%s*([%w_]+) = %d+,") do
	local e = Instance.new("RemoteFunction")
	e.Name = name
	e.Parent = remotes
end
remotes.Parent = services.ReplicatedStorage
local serverState = Instance.new("Folder")
serverState.Name = "ServerState"
serverState.Parent = services.ReplicatedStorage
serverState:SetAttribute("AvalancheMeter", 0.4)

-------------------------------------------------------------------------- globals

local env = {
	game = game,
	workspace = workspace,
	Workspace = workspace,
	script = nil,
	Instance = Instance,
	Enum = Enum,
	UDim = R.UDim,
	UDim2 = R.UDim2,
	Vector2 = R.Vector2,
	Vector3 = R.Vector3,
	Color3 = R.Color3,
	ColorSequence = R.ColorSequence,
	ColorSequenceKeypoint = R.ColorSequenceKeypoint,
	NumberSequence = R.NumberSequence,
	NumberSequenceKeypoint = R.NumberSequenceKeypoint,
	NumberRange = R.NumberRange,
	Rect = R.Rect,
	Font = R.Font,
	TweenInfo = R.TweenInfo,
	CFrame = R.CFrame,
	BrickColor = R.BrickColor,
	RaycastParams = R.RaycastParams,
	OverlapParams = R.OverlapParams,
	PhysicalProperties = R.PhysicalProperties,
	task = R.task,
	typeof = R.typeof,
	wait = R.task.wait,
	delay = R.task.delay,
	spawn = R.task.spawn,
	tick = function()
		return 1.7e9 + R.now()
	end,
	time = function()
		return R.now()
	end,
	warn = function(...)
		print("[warn]", ...)
	end,
	DateTime = {
		now = function()
			return { UnixTimestamp = 1795000000 + math.floor(R.now()), UnixTimestampMillis = (1795000000 + R.now()) * 1000 }
		end,
	},
	os = setmetatable({
		clock = function()
			return R.now()
		end,
		time = function(t)
			if t then
				return os.time(t)
			end
			return 1795000000 + math.floor(R.now())
		end,
	}, { __index = os }),
	utf8 = utf8,
	Random = {
		new = function(seed)
			local state = (seed or 1) % 2147483647
			if state <= 0 then
				state += 2147483646
			end
			local function nxt()
				state = (state * 16807) % 2147483647
				return state / 2147483647
			end
			return {
				NextNumber = function(_, a, b)
					a = a or 0
					b = b or 1
					return a + (b - a) * nxt()
				end,
				NextInteger = function(_, a, b)
					return math.floor(a + (b - a + 1) * nxt())
				end,
				NextUnitVector = function()
					return R.Vector3.new(0, 1, 0)
				end,
				Shuffle = function() end,
			}
		end,
	},
	shared = {},
	settings = function()
		return { Rendering = { QualityLevel = 10 } }
	end,
	UserSettings = function()
		return { GameSettings = { SavedQualityLevel = Enum.SavedQualitySetting.Automatic } }
	end,
}
setmetatable(env, { __index = getfenv(0) })
env.require = R.makeRequire(env)

-------------------------------------------------------------------------- player data

local NOW = 1795000000
local function big(n)
	return { m = n, e = 0 }
end
local data = {
	Cash = big(12400),
	Power = big(245),
	PowerPerTap = big(5),
	TrainMult = 1,
	PopMult = 1,
	Distance = 150,
	Roller = 2,
	RobuxRollers = {},
	Core = 1,
	EggSlots = 2,
	PetSlots = 4,
	PackZone = 0,
	Rebirths = 0,
	RebirthCost = big(50000),
	BestDistance = 320,
	BestZone = 2,
	ReachedVillage = false,
	BiggestRadius = 4,
	InvVersion = 1,
	Pets = { p1 = { Id = "Chipmunk", Weight = 1.4 }, p2 = { Id = "Sheep", Weight = 2.2 } },
	Eggs = { { Rarity = "Rare" }, { Rarity = "Uncommon" }, { Rarity = "Uncommon" }, { Rarity = "Common" } },
	Hatching = {},
	Index = {},
	Boosts = { Cash2x = NOW + 299, Train2x = NOW + 552 },
	Charges = { LuckyRoll = 0, SuperLucky = 0, GoldenRuns = 0, LuckPop = 0 },
	Gamepasses = {},
	Flags = {
		TutorialDone = true,
		StarterPackBought = false,
		StarterPackEnds = NOW + 6000,
		FirstPopDone = true,
		Funnel = {},
		OffersShown = {},
	},
	Stats = { Taps = 10, PopsClaimed = 1, Runs = 3, TotalDistance = 500, Smashes = 4, EggsFound = 2, Hatches = 1, Playtime = 600 },
	Settings = { Music = 0.6, Sfx = 0.8, Steer = 1, FreePops = true },
	IncomePerSec = 84,
	Luck = 1,
	Rewards = { DailyIndex = 3, DailyReady = true, DailyNextAt = 0, PlaytimeClaimed = { true }, Playtime = 400, Spins = 0, FreeSpin = true, CashOf = {} },
	Spins = 1,
	CashMult = 1,
	CashPacks = nil,
	PowerPacks = nil,
	TutorialStep = "Done",
	BaseIndex = 1,
	ServerTime = NOW,
}
player:SetAttribute("IncomePerSec", 84)

R.onInvoke = function(name, ...)
	if name == "GetState" then
		return data
	end
	return true
end

-------------------------------------------------------------------------- boot

local MAIN_SRC = fs.readFile(ROOT .. "/src/client/Main.client.luau")
local LOADING_SRC = fs.readFile(ROOT .. "/src/first/Loading.client.luau")
local controllers
local function boot()
	local req = env.require
	local Client = client
	local State = req(Client:WaitForChild("State"))
	local mainSrc = MAIN_SRC
	local order = {}
	for name in (mainSrc:match("local ORDER = {(.-)}") or ""):gmatch('"([%w_]+)"') do
		table.insert(order, name)
	end
	controllers = {}
	for _, name in order do
		local ok, mod = pcall(req, Client.Controllers:FindFirstChild(name))
		if ok then
			controllers[name] = mod
		else
			print("[load] " .. name .. ": " .. tostring(mod))
			controllers[name] = {}
		end
	end
	State.init()
	for _, name in order do
		local c = controllers[name]
		if c.Init then
			local ok, err = pcall(c.Init, c, controllers)
			if not ok then
				print("[init] " .. name .. ": " .. tostring(err))
			end
		end
	end
	for _, name in order do
		local c = controllers[name]
		if c.Start then
			R.task.spawn(function()
				local ok, err = pcall(c.Start, c)
				if not ok then
					print("[start] " .. name .. ": " .. tostring(err))
				end
			end)
		end
	end
end

R.frame = function(dt)
	services.RunService.Heartbeat:Fire(dt)
	services.RunService.RenderStepped:Fire(dt)
	services.RunService.Stepped:Fire(R.now(), dt)
end

local function fire(name, ...)
	remotes:FindFirstChild(name).OnClientEvent:Fire(...)
end

-------------------------------------------------------------------------- scenarios

local SCENARIOS = {}
SCENARIOS.hud = function() end
SCENARIOS.training = function()
	player:SetAttribute("Training", true)
	fire("PopShown", 1, "Snowflake", 0.3, 0.35, 4)
	fire("PopShown", 2, "Golden", 0.7, 0.4, 4)
	fire("PopShown", 3, "Coin", 0.55, 0.25, 4)
end
SCENARIOS.rolling = function()
	player:SetAttribute("RollPhase", "Rolling")
	controllers.HudController:ShowZoneBar(true, { Luck = 1 })
	controllers.HudController:SetZoneProgress(180)
end
SCENARIOS.keeprolling = function()
	player:SetAttribute("RollPhase", "Stopped")
	controllers.HudController:ShowZoneBar(true, { Luck = 1 })
	controllers.HudController:SetZoneProgress(180)
	local Zones = env.require(shared.Config.Zones)
	local z1, z2 = Zones.List[1], Zones.List[2]
	fire("RunStopped", {
		Zone = 1,
		NextZone = 2,
		ZoneStart = z1.Start,
		Distance = z1.Start + (z2.Start - z1.Start) * 0.82,
		Reach = z1.Start + (z2.Start - z1.Start) * 1.1,
		Price = 19,
		Product = "KeepRolling",
		Seconds = 8,
		Best = 320,
	})
end
SCENARIOS.results = function()
	controllers.ResultsController:Show({ Zone = 2, Cash = big(2400), Eggs = { "Common", "Rare", "Epic", "Legendary" }, Record = true })
end
SCENARIOS.starter = function()
	controllers.StarterPackController:Open()
end
SCENARIOS.toast = function()
	controllers.HudController:Mode()
	env.require(client.Ui).toast("Stone Roller! +5 Power", "Good")
	env.require(client.Ui).word("PERFECT!", R.Color3.fromRGB(110, 235, 90), 5)
end
local function opener(ctrl, method, ...)
	local args = table.pack(...)
	return function()
		local c = controllers[ctrl]
		c[method](c, table.unpack(args, 1, args.n))
	end
end
SCENARIOS.loading = function()
	local scriptEnv = {}
	for k, v in env do
		scriptEnv[k] = v
	end
	scriptEnv.script = Instance.new("LocalScript")
	local fn = require("@lune/luau").load(LOADING_SRC, { debugName = "Loading", environment = scriptEnv })
	R.task.spawn(fn)
end
SCENARIOS.pack = function()
	player:SetAttribute("RollPhase", "Packing")
	fire("PackStart", workspace:GetServerTimeNow() - 0.45, 1.1, 0.14, 0.13)
end
SCENARIOS.offer = function()
	fire("ShowOffer", {
		Key = "HatchLuck",
		Product = "LuckyRoll10",
		Title = "EPIC PET! YOU'RE LUCKY!",
		Text = "Keep the luck going: 10 Lucky Rolls.",
		Price = 69,
		Pic = "Shop_Lucky10",
	})
end
SCENARIOS.bought = function()
	fire("Purchased", "Cash3", { Got = "+$424M CASH" })
end
SCENARIOS.shop = opener("ShopController", "Open")
SCENARIOS.shop2 = opener("ShopController", "Open", "Boosts")
SCENARIOS.shop3 = opener("ShopController", "Open", "Money")
SCENARIOS.upgrades = opener("UpgradesController", "Toggle")
SCENARIOS.rebirth = opener("RebirthController", "Toggle")
SCENARIOS.bag = opener("InventoryController", "Toggle")
SCENARIOS.daily = opener("RewardsController", "Open", "Daily")
SCENARIOS.gifts = opener("RewardsController", "Open", "Gifts")
SCENARIOS.wheel = opener("RewardsController", "Open", "Wheel")
SCENARIOS.codes = opener("RewardsController", "Open", "Codes")

-- Leaderboards (LeaderboardController / NametagController): fake top lists, then the
-- window, a plaza stand (its SurfaceGui canvas moved into a ScreenGui), the passed card
-- and name tags (billboards moved into a ScreenGui, 40 px per stud).
local function fakeBoards()
	local HttpService = services.HttpService or game:GetService("HttpService")
	local f = services.ReplicatedStorage:FindFirstChild("Leaderboards") or Instance.new("Folder")
	f.Name = "Leaderboards"
	f:SetAttribute("WeekEndsAt", os.time() + 2 * 86400 + 4 * 3600)
	local names = {
		"SnowKing",
		"xXFrostyXx",
		"Lily_2015",
		"BigBallBen",
		"Pengu",
		"IceQueen",
		"RollerJoe",
		"Mia",
		"Toby",
		"Zara",
		"Kai",
		"Noah",
	}
	local base = { Distance = 4200, Luck = 52000, Income = 0, Earned = 0 }
	for _, key in { "Distance", "Luck", "Income", "Earned" } do
		for _, p in { "All", "Week" } do
			local rows = {}
			for i, n in names do
				local score
				if key == "Distance" then
					score = math.floor(4200 / (i ^ 0.35))
				elseif key == "Luck" then
					score = math.floor(52000 / (i ^ 0.9))
				else
					score = math.floor((9.2 - i * 0.31) * 1e10)
				end
				table.insert(rows, { U = 1000 + i, N = n, S = score })
			end
			local v = Instance.new("StringValue")
			v.Name = key .. "_" .. p
			v.Value = HttpService:JSONEncode(rows)
			v.Parent = f
		end
	end
	f.Parent = services.ReplicatedStorage
	return f
end
SCENARIOS.lbwindow = function()
	fakeBoards()
	R.task.wait(0.3)
	controllers.LeaderboardController:Open("Distance")
end
SCENARIOS.lbwindow2 = function()
	fakeBoards()
	R.task.wait(0.3)
	controllers.LeaderboardController:Open("Income")
end
SCENARIOS.lbstand = function()
	fakeBoards()
	local Config = env.require(shared.Config.Leaderboards)
	local stands = workspace:WaitForChild("Mountain"):WaitForChild("Summit"):WaitForChild("Leaderboards")
	local stand = Instance.new("Model")
	stand.Name = "Stand_Luck"
	local screen = Instance.new("Part")
	screen.Name = "Screen"
	screen:SetAttribute("Board", "Luck")
	screen.Parent = stand
	stand.Parent = stands
	R.task.wait(1)
	local surface = playerGui:FindFirstChild("Stand_Luck")
	local sg = Instance.new("ScreenGui")
	sg.Name = "StandView"
	local holder = Instance.new("Frame")
	holder.BackgroundColor3 = R.Color3.fromRGB(40, 44, 54)
	holder.Size = R.UDim2.fromOffset(Config.ScreenSize.X * 40, Config.ScreenSize.Y * 40)
	holder.Position = R.UDim2.fromOffset(20, 10)
	holder.Parent = sg
	if surface then
		surface:FindFirstChild("Canvas").Parent = holder
	else
		print("[lbstand] no SurfaceGui")
	end
	sg.Parent = playerGui
	controllers.HudController:Mode()
end
SCENARIOS.lbcard = function()
	fire(
		"RankEvent",
		{ Kind = "Passed", Board = "Distance", Scope = "World", UserId = 1003, Name = "Lily_2015", Rank = 7 }
	)
end
SCENARIOS.lbrecord = function()
	fire("ServerRecord", { Board = "Luck", UserId = 1004, Name = "BigBallBen", Score = 523000 })
end
SCENARIOS.nametag = function()
	player:SetAttribute("VIP", true)
	player:SetAttribute("ServerRank", 1)
	player:SetAttribute("WorldRank", 7)
	player:SetAttribute("WorldBoard", "Distance")
	player:SetAttribute("IncomePerSec", 12400)
	R.task.wait(0.3)
	local tags = playerGui:FindFirstChild("Nametags")
	local sg = Instance.new("ScreenGui")
	sg.Name = "TagView"
	local y = 20
	for _, b in (tags and tags:GetChildren() or {}) do
		local holder = Instance.new("Frame")
		holder.BackgroundColor3 = R.Color3.fromRGB(120, 170, 220)
		holder.Size = R.UDim2.fromOffset(9 * 40, 2.7 * 40)
		holder.Position = R.UDim2.fromOffset(20, y)
		holder.Parent = sg
		for _, c in b:GetChildren() do
			c.Parent = holder
		end
		y += 130
	end
	sg.Parent = playerGui
end

-------------------------------------------------------------------------- run

R.autoWorld = true
local bootCo = R.task.spawn(boot)
R.advance(1.5)
if coroutine.status(bootCo) ~= "dead" then
	print("[boot] still waiting: " .. debug.traceback(bootCo))
end
-- server state arrives
fire("PlayerState", data)
R.advance(1)
local fn = SCENARIOS[scenario]
if not fn then
	error("unknown scenario " .. scenario)
end
R.task.spawn(fn)
R.advance(tonumber(process.args[4]) or 1.2)

local screens = {}
for _, g in playerGui:GetChildren() do
	if g.ClassName == "ScreenGui" then
		table.insert(screens, Dump.node(g, R.typeof, function(x, k)
			return x[k]
		end))
	end
end
fs.writeFile(outPath, serde.encode("json", screens))
print(`{scenario} {deviceName}: {#screens} screens`)
