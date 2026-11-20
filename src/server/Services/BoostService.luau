--!strict
-- Every multiplier in one place: training, cash and luck (GAME_PLAN §5.1, §5.3, §6).
-- Timed personal boosts live in data.Boosts as name -> EndsAt (unix). The Snow Pop boost is
-- data.Boosts.Pop = { Mult, EndsAt } (one at a time: a better pop replaces it).
-- Server Luck (shared, Sweep's rule: a purchase raises the level or adds time) and the
-- Avalanche luck are attributes on ReplicatedStorage.ServerState for every client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local Rollers = require(Shared.Config.Rollers)
local Upgrades = require(Shared.Config.Upgrades)

local BoostService = {}

local S: any
local serverLuck = { Mult = 1, EndsAt = 0 }

local function active(endsAt: any): boolean
	return type(endsAt) == "number" and endsAt > os.time()
end

-- The live pop multiplier (1 when none).
function BoostService:GetPopMult(player: Player): number
	local data = S.DataService:GetData(player)
	local pop = data and data.Boosts.Pop
	if type(pop) == "table" and active(pop.EndsAt) then
		return pop.Mult
	end
	return 1
end

-- Applies a pop boost. A better (or equal) pop replaces the current one and resets the
-- timer; a weaker one is ignored while the better one runs. Returns true if applied.
function BoostService:ApplyPop(player: Player, mult: number, seconds: number): boolean
	local data = S.DataService:GetData(player)
	if not data then
		return false
	end
	local current = BoostService:GetPopMult(player)
	if mult < current then
		return false
	end
	data.Boosts.Pop = { Mult = mult, EndsAt = os.time() + seconds }
	S.StateService:Mark(player)
	return true
end

function BoostService:AddPersonal(player: Player, name: string, minutes: number)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	local now = os.time()
	local from = if active(data.Boosts[name]) then data.Boosts[name] else now
	data.Boosts[name] = from + minutes * 60
	S.StateService:Mark(player)
end

-- Everything that multiplies Power per tap, except the roller's own Power.
function BoostService:GetTrainMult(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 1
	end
	local mult = Rollers.robuxMult(data.RobuxRollers)
	mult *= 1 + (if S.PetService then S.PetService:GetTrainBonus(player) else 0)
	mult *= BoostService:GetPopMult(player)
	mult *= Economy.rebirthTrainMult(data.Rebirths)
	if data.Gamepasses.Train2x then
		mult *= Economy.Train2xPass
	end
	if active(data.Boosts.Train2x) then
		mult *= 2
	end
	return mult
end

function BoostService:GetCashMult(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 1
	end
	local mult = Economy.rebirthCashMult(data.Rebirths)
	if data.Gamepasses.VIP then
		mult += Economy.VIPCashBonus
	end
	if data.Gamepasses.Cash2x then
		mult *= Economy.Cash2xPass
	end
	if active(data.Boosts.Cash2x) then
		mult *= 2
	end
	return mult
end

-- Luck for egg rolls (Core, passes, rebirths, Server Luck, Avalanche). Per-roll charges
-- (Lucky Roll, Luck Pop) are added by RollService.
function BoostService:GetLuck(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 1
	end
	local core = Upgrades.Cores[data.Core] or Upgrades.Cores[1]
	local bonus = data.Rebirths * Economy.RebirthLuckBonus
	if data.Gamepasses.Lucky then
		bonus += Economy.LuckyPassBonus
	end
	if data.Gamepasses.VIP then
		bonus += Economy.VIPLuckBonus
	end
	if active(data.Boosts.Crown) then
		bonus += 0.25
	end
	local luck = core.Luck * (1 + bonus) * BoostService:GetServerLuck()
	if S.AvalancheService and S.AvalancheService:IsActive() then
		luck *= 2
	end
	return luck
end

function BoostService:GetServerLuck(): number
	return if serverLuck.EndsAt > os.time() then serverLuck.Mult else 1
end

local function publishServerLuck()
	local state = S.StateService:GetServerState()
	local on = serverLuck.EndsAt > os.time()
	state:SetAttribute("ServerLuck", if on then serverLuck.Mult else nil)
	state:SetAttribute("ServerLuckEnds", if on then serverLuck.EndsAt else nil)
end

-- A Server Luck purchase: a higher level replaces the running one (keeping its time if
-- longer), the same level adds time.
function BoostService:AddServerLuck(mult: number, minutes: number, buyer: Player?)
	local now = os.time()
	if serverLuck.EndsAt > now and serverLuck.Mult == mult then
		serverLuck.EndsAt += minutes * 60
	else
		serverLuck.Mult = math.max(mult, if serverLuck.EndsAt > now then serverLuck.Mult else 1)
		serverLuck.EndsAt = math.max(serverLuck.EndsAt, now + minutes * 60)
	end
	publishServerLuck()
	if buyer then
		Net.fireAll("Announce", `{buyer.DisplayName} turned on {serverLuck.Mult}x Server Luck for everyone!`)
	end
end

function BoostService:Init(services)
	S = services
end

function BoostService:Start()
	task.spawn(function()
		while true do
			task.wait(5)
			publishServerLuck()
		end
	end)
end

return BoostService
