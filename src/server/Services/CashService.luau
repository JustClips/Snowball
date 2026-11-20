--!strict
-- Cash in and out, with the economy analytics. Every cash change goes through here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local CashService = {}

local S: any

-- Adds cash (already multiplied by the caller if it should be). Returns the amount.
function CashService:Give(
	player: Player,
	amount: BigNum.BigNum | number,
	source: string,
	txType: Enum.AnalyticsEconomyTransactionType?
): BigNum.BigNum
	local data = S.DataService:GetData(player)
	local value = BigNum.floor(BigNum.from(amount))
	if not data or value.m <= 0 then
		return BigNum.zero()
	end
	data.Cash = BigNum.add(data.Cash, value)
	data.CashEarned = BigNum.add(data.CashEarned, value)
	S.StateService:Mark(player)
	S.AnalyticsService:Source(
		player,
		BigNum.toNumber(value),
		txType or Enum.AnalyticsEconomyTransactionType.Gameplay,
		source
	)
	return value
end

function CashService:CanAfford(player: Player, price: BigNum.BigNum | number): boolean
	local data = S.DataService:GetData(player)
	return data ~= nil and BigNum.gte(data.Cash, price)
end

-- Takes cash if the player has it. Returns ok, message.
function CashService:Spend(player: Player, price: BigNum.BigNum | number, sku: string): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading"
	end
	if not BigNum.gte(data.Cash, price) then
		local short = BigNum.sub(price, data.Cash)
		Net.fire("Notify", player, `You need {Format.cash(short)} more`, "Bad")
		if S.ShopService then
			S.ShopService:OfferCashFor(player, short)
		end
		return false, "Not enough cash"
	end
	data.Cash = BigNum.sub(data.Cash, price)
	S.StateService:Mark(player)
	S.AnalyticsService:Sink(player, BigNum.toNumber(price), Enum.AnalyticsEconomyTransactionType.Shop, sku)
	return true, nil
end

function CashService:Init(services)
	S = services
end

return CashService
