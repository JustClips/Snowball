--!strict
-- Cash upgrades (GAME_PLAN §5.8): Snowball Core, Egg Slots, Pet Slots, Pack Zone.
-- Snow Rollers are bought through TrainService (BuyRoller).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Upgrades = require(Shared.Config.Upgrades)

local UpgradeService = {}

local S: any

local APPLY: { [string]: (data: any) -> string } = {
	Core = function(data)
		data.Core += 1
		return Upgrades.Cores[data.Core].Name .. "!"
	end,
	EggSlots = function(data)
		data.EggSlots += 1
		return `Your ball holds {data.EggSlots} eggs now`
	end,
	PetSlots = function(data)
		data.PetSlots += 1
		return `{data.PetSlots} pet slots on your base`
	end,
	PackZone = function(data)
		data.PackZone += 1
		return "Wider green zone!"
	end,
}

local function buy(player: Player, id: any): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data or type(id) ~= "string" or not APPLY[id] then
		return false, "Bad request"
	end
	local price = Upgrades.nextPrice(id, data)
	if not price then
		return false, "Maxed out"
	end
	local ok, why = S.CashService:Spend(player, price, "Upgrade" .. id)
	if not ok then
		return false, why
	end
	local text = APPLY[id](data)
	if id == "Core" then
		S.AnalyticsService:Custom(player, "CoreBought", data.Core)
	elseif id == "PetSlots" and S.PetService then
		S.PetService:RefreshBase(player)
	end
	S.StateService:Mark(player)
	Net.fire("Notify", player, text, "Good")
	return true, nil
end

function UpgradeService:Init(services)
	S = services
	Net.onInvoke("BuyUpgrade", buy)
end

return UpgradeService
