--!strict
-- Rebirth (GAME_PLAN §5.11). Needs the Village reached since the last rebirth plus cash
-- (Economy.rebirthCost). Resets Cash, Power, the cash Snow Roller, the Snowball Core and
-- the Village flag. Keeps pets, eggs, Index, Egg/Pet Slots, Pack Zone, Robux rollers, passes.
-- Each rebirth: x1.5 training, +50% cash, +10% luck (BoostService reads data.Rebirths).
-- Snowball skins at R1/R3/R5/R10 go into data.Trails; the Glacier Roller needs R2.
-- Skip Rebirth (Robux) calls Rebirth(player, true): ShopService already checked the 30% rule.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local RebirthService = {}

local S: any

local SKINS: { [number]: string } = {
	[1] = "FrostSkin",
	[3] = "CandySkin",
	[5] = "AuroraSkin",
	[10] = "StarSkin",
}

function RebirthService:CanRebirth(player: Player): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Not loaded"
	end
	if not data.ReachedVillage then
		return false, "Reach the Village first"
	end
	local cost = Economy.rebirthCost(data.Rebirths)
	if BigNum.lt(data.Cash, cost) then
		return false, `You need {Format.cash(cost)}`
	end
	return true, nil
end

-- skipped = paid with Robux (the cash check is skipped, the Village check stays in ShopService).
function RebirthService:Rebirth(player: Player, skipped: boolean?): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Not loaded"
	end
	if not skipped then
		local ok, why = RebirthService:CanRebirth(player)
		if not ok then
			return false, why
		end
		if S.RollService:IsBusy(player) then
			return false, "Finish your roll first"
		end
	end
	data.Rebirths += 1
	data.Cash = BigNum.from(0)
	data.Power = BigNum.from(0)
	data.Roller = 1
	data.Core = 1
	data.ReachedVillage = false
	local skin = SKINS[data.Rebirths]
	if skin then
		data.Trails[skin] = true
	end
	S.TrainService:RefreshRoller(player)
	S.AnalyticsService:Rebirthed(player, data.Rebirths)
	S.StateService:Mark(player)
	local n = data.Rebirths
	local extra = if skin then " New snowball skin!" else ""
	Net.fire(
		"Notify",
		player,
		`REBIRTH {n}! x{Format.big(Economy.rebirthTrainMult(n))} training, x{Economy.rebirthCashMult(n)} cash.{extra}`,
		"Good"
	)
	Net.fireAll("Announce", `{player.DisplayName} reached Rebirth {n}!`)
	return true, nil
end

function RebirthService:Init(services)
	S = services
	Net.onInvoke("Rebirth", function(player: Player)
		return RebirthService:Rebirth(player, false)
	end)
end

return RebirthService
