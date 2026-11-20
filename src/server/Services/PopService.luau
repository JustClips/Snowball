--!strict
-- Snow Pops (GAME_PLAN §5.3). Only while a player trains on their roller, every 8-15 s the
-- server rolls a pop (tier, a screen spot as 0-1 coordinates in a safe area, an id) and
-- sends it. ClaimPop(id) only works for that live pop inside its 4 s window. Rainbow Pops
-- show their Robux price and open the product prompt; ShopService grants them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Pops = require(Shared.Config.Pops)
local Products = require(Shared.Config.Products)

local PopService = {}

local S: any
local rng = Random.new()

type Live = { id: number, tier: string, expires: number, rainbow: boolean }
type PopState = { nextAt: number, live: Live?, counter: number, declineUntil: number, force: string? }
local states: { [Player]: PopState } = {}

local function stateOf(player: Player): PopState
	local st = states[player]
	if not st then
		st = { nextAt = 0, live = nil, counter = 0, declineUntil = 0 }
		states[player] = st
	end
	return st
end

local function rush(): boolean
	return S.AvalancheService ~= nil and S.AvalancheService:IsActive()
end

-- Seconds from one pop appearing to the next (Pop Rush during an Avalanche).
local function gap(): number
	if rush() then
		return Pops.PopRushGap
	end
	return Pops.LifeSeconds + rng:NextNumber(Pops.MinGap, Pops.MaxGap)
end

-- Seconds this player has played in total (saved playtime + this session).
local function playtime(player: Player): number
	local session = S.DataService:GetSession(player)
	if not session then
		return 0
	end
	return session.Data.Stats.Playtime + os.time() - session.JoinedAt
end

local function rainbowAllowed(player: Player, st: PopState): boolean
	local data = S.DataService:GetData(player)
	if not data or not data.Flags.TutorialDone then
		return false
	end
	local now = os.time()
	if
		playtime(player) < Pops.RainbowNotBefore
		or now - data.LastRainbowPop < Pops.RainbowEvery
		or now < st.declineUntil
	then
		return false
	end
	local def = Products.ProductByKey.RainbowPop25
	return def ~= nil and def.Id ~= 0
end

local function clear(player: Player, claimed: boolean, reward: any?)
	local st = states[player]
	if st and st.live then
		local live = st.live
		st.live = nil
		Net.fire("PopGone", player, live.id, claimed, reward)
		if not claimed then
			S.AnalyticsService:Custom(player, "PopMissed", 1, { Tier = live.tier })
		end
	end
end

-- Seconds of income, never below a floor so pops pay before pets earn much.
local function incomeFor(player: Player, seconds: number): number
	local rate = if S.PetService then S.PetService:GetIncomePerSec(player) else 0
	return math.max(rate, Economy.MinIncomeForRewards) * seconds * S.BoostService:GetCashMult(player)
end

local function grant(player: Player, tierId: string): string
	local def = Pops.ById[tierId]
	local data = S.DataService:GetData(player)
	if def.Kind == "Train" then
		S.BoostService:ApplyPop(player, def.Mult, def.Seconds)
		return `x{def.Mult} TRAINING!`
	elseif def.Kind == "Coin" then
		local cash = S.CashService:Give(player, incomeFor(player, def.Mult), "CoinPop")
		return "+" .. Format.cash(cash)
	elseif def.Kind == "Luck" then
		data.Charges.LuckPop = (data.Charges.LuckPop or 0) + 1
		S.StateService:Mark(player)
		return `x{def.Mult} LUCK next roll!`
	elseif def.Kind == "Present" then
		-- Half the time an egg from your best zone (if your bag has room), else cash.
		if S.InventoryService and rng:NextNumber() < 0.5 and S.InventoryService:HasEggRoom(player) then
			local rarity = S.InventoryService:AddZoneEgg(player, data.BestZone, "Present")
			return `{rarity} egg!`
		end
		local cash = S.CashService:Give(player, incomeFor(player, def.Mult), "PresentPop")
		return "+" .. Format.cash(cash)
	end
	return ""
end

local function show(player: Player, st: PopState)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	local tier
	local rainbow = false
	if st.force then
		tier = Pops.ById[st.force]
		rainbow = tier.Kind == "Rainbow"
		st.force = nil
	elseif not data.Flags.FirstPopDone then
		tier = Pops.ById[Pops.FirstPopTier]
	elseif rainbowAllowed(player, st) and rng:NextNumber() < Pops.RainbowChance then
		tier = Pops.rollRainbow(rng)
		rainbow = true
		data.LastRainbowPop = os.time()
	else
		tier = Pops.rollFree(rng)
	end
	st.counter += 1
	local live: Live = { id = st.counter, tier = tier.Id, expires = os.clock() + Pops.LifeSeconds, rainbow = rainbow }
	st.live = live
	local area = Pops.SafeArea
	local x = rng:NextNumber(area.MinX, area.MaxX)
	local y = rng:NextNumber(area.MinY, area.MaxY)
	local price = nil
	if rainbow and tier.Product then
		local product = Products.ProductByKey[tier.Product]
		price = product and product.Price
	end
	Net.fire("PopShown", player, live.id, tier.Id, x, y, Pops.LifeSeconds, price)
	S.AnalyticsService:Custom(player, "PopShown", 1, { Tier = tier.Id })
	-- Pop Magnet claims free pops for you (never the Rainbow Pop).
	if data.Gamepasses.PopMagnet and not rainbow and data.Settings.FreePops ~= false then
		task.delay(0.6, function()
			if st.live == live then
				PopService:Claim(player, live.id)
			end
		end)
	end
end

function PopService:Claim(player: Player, id: any)
	local st = states[player]
	local live = st and st.live
	if not st or not live or type(id) ~= "number" or live.id ~= id then
		return
	end
	if os.clock() > live.expires + Pops.ClaimGrace then
		return
	end
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	if live.rainbow then
		-- Tapping a Rainbow Pop opens its purchase prompt; the boost comes from the receipt.
		local def = Pops.ById[live.tier]
		st.live = nil
		Net.fire("PopGone", player, live.id, true, nil)
		S.AnalyticsService:Custom(player, "RainbowPop", def.Mult, { Result = "Tapped" })
		S.ShopService:Prompt(player, def.Product or "", nil)
		return
	end
	local reward = grant(player, live.tier)
	data.Stats.PopsClaimed += 1
	if not data.Flags.FirstPopDone then
		data.Flags.FirstPopDone = true
		S.AnalyticsService:Funnel(player, "FirstPop")
	end
	S.AnalyticsService:Custom(player, "PopClaimed", 1, { Tier = live.tier })
	clear(player, true, reward)
end

-- Admin /pop: the next pop is this tier and comes right away.
function PopService:ForceNext(player: Player, tierId: string)
	local st = stateOf(player)
	st.force = tierId
	st.nextAt = os.clock()
end

-- The player closed a Rainbow Pop's prompt without buying: wait longer for the next one.
function PopService:RainbowDeclined(player: Player)
	stateOf(player).declineUntil = os.time() + Pops.RainbowAfterDecline
end

local function onTraining(player: Player, on: boolean)
	local st = stateOf(player)
	if on then
		local data = S.DataService:GetData(player)
		local first = data and not data.Flags.FirstPopDone
		st.nextAt = os.clock() + (if first then Pops.FirstPopAfter else gap())
	else
		-- Stepping off the roller clears any pop on screen (the boost keeps running).
		clear(player, false)
	end
end

function PopService:Init(services)
	S = services
	Net.onEvent("ClaimPop", function(player, id)
		PopService:Claim(player, id)
	end)
	S.TrainService.TrainingChanged:Connect(onTraining)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

function PopService:Start()
	task.spawn(function()
		while true do
			task.wait(0.25)
			local now = os.clock()
			for player, st in states do
				if st.live and now > st.live.expires + Pops.ClaimGrace then
					clear(player, false)
				end
				if not st.live and S.TrainService:IsTraining(player) and now >= st.nextAt and st.nextAt > 0 then
					show(player, st)
					st.nextAt = now + gap()
				end
			end
		end
	end)
end

return PopService
