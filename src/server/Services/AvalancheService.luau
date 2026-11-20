--!strict
-- Avalanche (GAME_PLAN §5.12): finished runs fill a server meter. When it's full: a 10 s
-- warning, then 60 s of Avalanche: 2x luck for every run, Pop Rush on the rollers, and every
-- run that ends brings one extra Rare+ frozen egg. The biggest ball since the last one wins
-- the crown (+25% luck for 5 min). Trigger Avalanche (Robux) starts it right away.
-- State for clients: ServerState attributes AvalancheMeter (0-1), AvalancheAt (warning
-- ends, unix), AvalancheEnds (unix), CrownUserId.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Avalanche)
local Net = require(Shared.Net)

local AvalancheService = {}

local S: any
local meter = 0
local startsAt = 0 -- unix time the active part starts (0 = no warning running)
local endsAt = 0
local biggest: { player: Player?, radius: number } = { player = nil, radius = 0 }

local function publish()
	local state = S.StateService:GetServerState()
	state:SetAttribute("AvalancheMeter", meter)
	state:SetAttribute("AvalancheAt", if startsAt > 0 then startsAt else nil)
	state:SetAttribute("AvalancheEnds", if endsAt > os.time() then endsAt else nil)
end

function AvalancheService:IsActive(): boolean
	local now = os.time()
	return startsAt > 0 and now >= startsAt and now < endsAt
end

function AvalancheService:Trigger(buyer: Player?)
	if startsAt > 0 and os.time() < endsAt then
		return -- one is already on its way
	end
	startsAt = os.time() + Config.WarningSeconds
	endsAt = startsAt + Config.ActiveSeconds
	meter = 1
	publish()
	local who = if buyer then `{buyer.DisplayName} started an ` else "An "
	Net.fireAll("Announce", `{who}AVALANCHE! It hits in {Config.WarningSeconds} seconds!`)
	-- Crown for the biggest ball of the round.
	local winner = biggest.player
	if winner and winner.Parent then
		S.BoostService:AddPersonal(winner, "Crown", Config.CrownMinutes)
		S.StateService:GetServerState():SetAttribute("CrownUserId", winner.UserId)
		Net.fireAll("Announce", `{winner.DisplayName} rolled the biggest ball ({math.floor(biggest.radius)})! Crown + luck for {Config.CrownMinutes} min`)
	end
	biggest = { player = nil, radius = 0 }
	for player in S.DataService:GetSessions() do
		S.AnalyticsService:Custom(player, "AvalancheStarted", 1, { Bought = tostring(buyer ~= nil) })
	end
end

-- A run ended with this radius.
function AvalancheService:AddRadius(player: Player, radius: number)
	if radius > biggest.radius then
		biggest = { player = player, radius = radius }
	end
	if AvalancheService:IsActive() then
		local data = S.DataService:GetData(player)
		local rarity = S.InventoryService:AddZoneEgg(player, data and data.BestZone or 1, "Avalanche", Config.BonusEggFloor)
		Net.fire("Notify", player, `Avalanche bonus: {rarity} egg!`, "Good")
		return
	end
	if startsAt > 0 then
		return
	end
	meter = math.min(1, meter + radius / Config.FillRadius)
	if meter >= 1 then
		AvalancheService:Trigger(nil)
	else
		publish()
	end
end

function AvalancheService:Init(services)
	S = services
end

function AvalancheService:Start()
	publish()
	task.spawn(function()
		while true do
			task.wait(1)
			if startsAt > 0 and os.time() >= endsAt then
				startsAt, endsAt, meter = 0, 0, 0
				Net.fireAll("Announce", "The Avalanche is over. Fill the meter again!")
				publish()
			elseif startsAt > 0 then
				publish()
			end
		end
	end)
end

return AvalancheService
