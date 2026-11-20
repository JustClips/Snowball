--!strict
-- Replicates each player's state to their own client as one snapshot, and runs the
-- server-confirmed tutorial (GAME_PLAN §4). Services call Mark(player) after changing
-- something; the snapshot goes out at most every Economy.StateFlushInterval seconds.
-- (Ported from Sweep the World, new fields.)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local PowerCurve = require(Shared.PowerCurve)
local Types = require(Shared.Types)

local StateService = {}

local S: any
local dirty: { [Player]: boolean } = {}
local sentInventory: { [Player]: number } = {}
local lastStep: { [Player]: string } = {}
local serverState: Folder

local TUTORIAL_POWER = 100 -- "Power 100! Go roll!"

-- Server-wide values (Avalanche meter, Server Luck...) live as attributes on
-- ReplicatedStorage.ServerState so every client gets them without extra remotes.
function StateService:GetServerState(): Folder
	return serverState
end

-- The tutorial: Train -> Roll -> Egg (place + hatch) -> Roller (free Stone Roller) ->
-- Pine (reach the Pine Forest). The player does every step. Never steps back.
local ORDER = { Train = 1, Roll = 2, Egg = 3, Roller = 4, Pine = 5, Done = 6 }

local function tutorialStep(player: Player, session: any): string
	local data = session.Data
	if data.Flags.TutorialDone then
		return "Done"
	end
	local step
	if data.Stats.Runs == 0 then
		step = if BigNum.toNumber(data.Power) < TUTORIAL_POWER then "Train" else "Roll"
	elseif S.HatchService and data.Stats.Hatches == 0 then
		step = "Egg"
	elseif data.Roller < 2 then
		step = "Roller"
	elseif data.BestZone < 2 then
		step = "Pine"
	else
		step = "Done"
	end
	local best = session.Runtime.TutorialMax
	if best and ORDER[best] > ORDER[step] then
		step = best
	end
	session.Runtime.TutorialMax = step
	if step == "Done" then
		data.Flags.TutorialDone = true
		if S.RewardService then
			task.defer(function()
				S.RewardService:TutorialReward(player)
			end)
		end
	end
	return step
end

function StateService:GetTutorialStep(player: Player): string?
	return lastStep[player]
end

function StateService:Build(player: Player, full: boolean?): Types.PlayerSnapshot?
	local session = S.DataService:GetSession(player)
	if not session then
		return nil
	end
	local data = session.Data
	local invVersion = S.InventoryService:GetVersion(player)
	local sendInventory = full == true or sentInventory[player] ~= invVersion
	sentInventory[player] = invVersion
	local step = tutorialStep(player, session)
	if lastStep[player] ~= step then
		lastStep[player] = step
		S.AnalyticsService:TutorialStep(player, step)
	end
	local power = data.Power
	return {
		Cash = data.Cash,
		Power = power,
		PowerPerTap = S.TrainService:PowerPerTap(player),
		TrainMult = S.BoostService:GetTrainMult(player),
		PopMult = S.BoostService:GetPopMult(player),
		Distance = PowerCurve.distance(power),
		Roller = data.Roller,
		RobuxRollers = data.RobuxRollers,
		Core = data.Core,
		EggSlots = data.EggSlots,
		PetSlots = data.PetSlots,
		PackZone = data.PackZone,
		Rebirths = data.Rebirths,
		RebirthCost = Economy.rebirthCost(data.Rebirths),
		BestDistance = data.BestDistance,
		BestZone = data.BestZone,
		ReachedVillage = data.ReachedVillage,
		BiggestRadius = data.BiggestRadius,
		InvVersion = invVersion,
		Pets = if sendInventory then data.Pets else nil,
		Eggs = if sendInventory then data.Eggs else nil,
		Hatching = data.Hatching,
		Index = data.Index,
		Boosts = data.Boosts,
		Charges = data.Charges,
		Gamepasses = data.Gamepasses,
		Flags = data.Flags,
		Stats = data.Stats,
		Settings = data.Settings,
		IncomePerSec = if S.PetService then S.PetService:GetIncomePerSec(player) else 0,
		Luck = S.BoostService:GetLuck(player),
		Rewards = if S.RewardService then S.RewardService:Snapshot(player) else nil,
		Spins = data.Spins,
		CashMult = S.BoostService:GetCashMult(player),
		TutorialStep = step,
		BaseIndex = session.Runtime.BaseIndex or 0,
		ServerTime = os.time(),
	} :: any
end

function StateService:Mark(player: Player)
	dirty[player] = true
end

function StateService:Init(services)
	S = services
	local existing = ReplicatedStorage:FindFirstChild("ServerState")
	if existing then
		existing:Destroy()
	end
	serverState = Instance.new("Folder")
	serverState.Name = "ServerState"
	serverState.Parent = ReplicatedStorage
	Net.onInvoke("GetState", function(player)
		return StateService:Build(player, true)
	end)
	S.DataService.ProfileLoaded:Connect(function(player)
		StateService:Mark(player)
	end)
	S.DataService.ProfileReleasing:Connect(function(player)
		dirty[player] = nil
		sentInventory[player] = nil
		task.defer(function()
			lastStep[player] = nil
		end)
	end)
end

function StateService:Start()
	task.spawn(function()
		while true do
			task.wait(Economy.StateFlushInterval)
			for player in dirty do
				dirty[player] = nil
				local ok, snapshot = pcall(StateService.Build, StateService, player)
				if ok and snapshot then
					Net.fire("PlayerState", player, snapshot)
				elseif not ok then
					warn("[StateService] snapshot failed: " .. tostring(snapshot))
				end
			end
		end
	end)
end

return StateService
