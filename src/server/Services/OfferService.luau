--!strict
-- Contextual offers (GAME_PLAN §6 "When offers appear"). The server decides when; the
-- client only shows the popup (OfferController). Never before the tutorial is done, at
-- most one every 3 minutes (the Starter Pack ignores that), each offer at most every 15.
--   1 Starter Pack once, after the tutorial (and the first hatch)
--   2 next roller costs > 5 min of income for 3+ min: Training Time
--   3 eggs bounced off a FULL ball 3 times: Egg Slots nudge (opens Upgrades)
--   4 Rare+ egg placed: Skip Hatch for that rarity
--   5 3 bonks in a session: Golden Snowball (1 run)
--   6 Avalanche meter at 80%+: Server Luck
--   7 returning player: Double Offline (on the welcome-back card, PetService)
--   8 3rd "not enough cash": prompts the cash pack that covers it (ShopService:OfferCashFor)
-- Added 2026-11-20 (Dev: "start improving monetization like where packs and stuff start to
-- appear on screen"), the moments the top games use:
--   9 a rare hatch (Epic+): you feel lucky, so Lucky Rolls
--  10 3 rolls in a row without a new best: a Power pack ("roll further")
--  11 saving for the next roller takes long: the cash pack that buys it now (rule 2 now
--     offers cash first, Training Time when no pack is live)
--  12 8 min into a session with no cash boost running: 2x Cash for 15 min
-- Never while rolling or during the egg rescue (yeti chase), never stacked.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Rollers = require(Shared.Config.Rollers)

local Rules = Economy.Offers

local OfferService = {}
local cashPackFor: (Player, number) -> any

local S: any

local function offerState(session)
	local state = session.Runtime.Offers
	if not state then
		state = { lastAny = -math.huge, lastByKey = {}, full = 0, bonks = 0, stuckSince = nil, avalancheShown = false }
		session.Runtime.Offers = state
	end
	return state
end

local function isLive(productKey: string): boolean
	local def = Products.ProductByKey[productKey] or Products.PassByKey[productKey]
	-- Studio test buys (Products.StudioTestBuys) make offers testable before products exist.
	return def ~= nil and (def.Id ~= 0 or (Products.StudioTestBuys and RunService:IsStudio()))
end

type Offer = { Key: string, Product: string?, Title: string, Text: string, Open: string?, Pic: string? }

local function show(player: Player, offer: Offer, ignoreGlobal: boolean?): boolean
	local session = S.DataService:GetSession(player)
	if not session or not session.Data.Flags.TutorialDone then
		return false
	end
	if offer.Product and not isLive(offer.Product) then
		return false
	end
	-- Nothing pops over a roll or the yeti chase.
	local phase = if S.RollService then S.RollService:GetPhase(player) else "Idle"
	if
		phase == "Packing"
		or phase == "Rolling"
		or phase == "Stopped"
		or (S.EggRescueService and S.EggRescueService:IsRescuing(player))
	then
		return false
	end
	local state = offerState(session)
	local now = os.clock()
	if not ignoreGlobal and now - state.lastAny < Rules.GlobalCooldown then
		return false
	end
	if now - (state.lastByKey[offer.Key] or -math.huge) < Rules.PerOfferCooldown then
		return false
	end
	state.lastAny = now
	state.lastByKey[offer.Key] = now
	local def = offer.Product and (Products.ProductByKey[offer.Product] or Products.PassByKey[offer.Product])
	Net.fire("ShowOffer", player, {
		Key = offer.Key,
		Product = offer.Product,
		Title = offer.Title,
		Text = offer.Text,
		Price = def and def.Price,
		Open = offer.Open,
		Pic = offer.Pic,
	})
	S.AnalyticsService:Custom(player, "OfferShown", 1, { Offer = offer.Key })
	return true
end

-- Rule 1: the Starter Pack window (StarterPackController), a few seconds after the tutorial
-- ends (after its reward toast), then once per session on later joins while it's still for
-- sale. The HUD tile keeps a countdown until it leaves.
local function tryStarterPack(player: Player)
	local session = S.DataService:GetSession(player)
	local data = session and session.Data
	if not data or session.Runtime.StarterShown or not Economy.starterPackLive(data, os.time()) then
		return
	end
	if S.RollService and S.RollService:IsBusy(player) then
		return -- not in the middle of a roll
	end
	local doneAt = session.Runtime.TutorialDoneAt
	if not doneAt then
		session.Runtime.TutorialDoneAt = os.clock()
		return
	end
	if os.clock() - doneAt < Economy.StarterPack.ShowDelay then
		return
	end
	if
		show(player, {
			Key = "StarterPack",
			Product = "StarterPack",
			Title = "STARTER PACK!",
			Text = "",
		}, true)
	then
		session.Runtime.StarterShown = true
	end
end

-- The cheapest live cash pack that gives at least `need` (else the biggest live one).
cashPackFor = function(player: Player, need: number): any
	if not S.ShopService then
		return nil
	end
	local amounts = S.ShopService:CashPackAmounts(player)
	local best, biggest = nil, nil
	local packs = {}
	for _, def in Products.Products do
		if def.Kind == "CashPack" and isLive(def.Key) then
			table.insert(packs, def)
		end
	end
	table.sort(packs, function(a, b)
		return a.Price < b.Price
	end)
	for _, def in packs do
		biggest = def
		if not best and (amounts[def.Key] or 0) >= need then
			best = def
		end
	end
	return best or biggest
end

-- Rule 2: saving up for the next roller is taking a while.
local function checkStuck(player: Player, session)
	local data = session.Data
	local state = offerState(session)
	local nextRoller = Rollers.get(data.Roller + 1)
	local income = if S.PetService then S.PetService:GetIncomePerSec(player) else 0
	local stuck = nextRoller ~= nil
		and nextRoller.Price > math.max(income, 1) * Rules.StuckIncomeMinutes * 60
		and BigNum.lt(data.Cash, nextRoller.Price)
	if not stuck then
		state.stuckSince = nil
		return
	end
	state.stuckSince = state.stuckSince or os.clock()
	if os.clock() - state.stuckSince >= Rules.StuckSeconds then
		-- The smallest cash pack that buys the next roller right now.
		local short = nextRoller.Price - BigNum.toNumber(data.Cash)
		local pack = cashPackFor(player, short)
		local shown = if pack
			then show(player, {
				Key = "RollerCash",
				Product = pack.Key,
				Title = `GET THE {string.upper(nextRoller.Name)} NOW!`,
				Text = `You're {Format.cash(short)} short. This pack covers it.`,
				Pic = "Shop_" .. pack.Key,
			})
			else show(player, {
				Key = "TrainTime",
				Product = "TrainTime15",
				Title = "TRAIN FASTER!",
				Text = "15 minutes of training right now, at your best speed.",
				Pic = "Power",
			})
		if shown then
			state.stuckSince = nil
		end
	end
end

-- Rule 6: the Avalanche is close.
local function checkAvalanche(player: Player, session)
	local state = offerState(session)
	local meter = S.StateService:GetServerState():GetAttribute("AvalancheMeter") or 0
	if meter < Rules.AvalancheMeter then
		state.avalancheShown = false
		return
	end
	if state.avalancheShown or (S.AvalancheService and S.AvalancheService:IsActive()) then
		return
	end
	if
		show(player, {
			Key = "ServerLuck",
			Product = "ServerLuck2",
			Pic = "Shop_ServerLuck",
			Title = "AVALANCHE SOON!",
			Text = "Add 2x Server Luck for everyone before it hits.",
		})
	then
		state.avalancheShown = true
	end
end

function OfferService:AfterRun(player: Player, result)
	local session = S.DataService:GetSession(player)
	if not session then
		return
	end
	local state = offerState(session)
	state.full += result.Full or 0
	state.bonks += result.Bonks or 0
	tryStarterPack(player)
	-- Rule 10: rolls without a new best in a row.
	if result.Record then
		state.noRecord = 0
	else
		state.noRecord = (state.noRecord or 0) + 1
	end
	if state.noRecord >= Rules.FailRuns then
		local pack = Products.ProductByKey.PowerPack2
		local gain = if pack and S.TrainService then S.TrainService:PowerPerTap(player) * pack.Taps else 0
		if
			show(player, {
				Key = "FailPower",
				Product = "PowerPack2",
				Title = "ROLL FURTHER!",
				Text = `+{Format.big(gain)} Power: a bigger ball rolls further.`,
				Pic = "Shop_Power2",
			})
		then
			state.noRecord = 0
			return
		end
	end
	if state.full >= Rules.FullBounces then
		if
			show(player, {
				Key = "EggSlots",
				Title = "YOUR BALL IS FULL!",
				Text = "Eggs bounced off. Buy Egg Slots to carry more.",
				Open = "Upgrades",
				Pic = "Egg",
			})
		then
			state.full = 0
		end
	elseif state.bonks >= Rules.Bonks and (session.Data.Charges.GoldenRuns or 0) == 0 then
		if
			show(player, {
				Key = "GoldenRuns",
				Product = "GoldenRuns1",
				Pic = "Shop_PassGoldBall",
				Title = "SMASH EVERYTHING!",
				Text = "A Golden Snowball smashes obstacles 1.5x its size and gets x2 coins.",
			})
		then
			state.bonks = 0
		end
	end
end

function OfferService:OnEggPlaced(player: Player, rarity: string)
	local def = Eggs.ByName[rarity]
	local from = Eggs.ByName[Rules.SkipHatchFrom]
	if not def or not from or def.Order < from.Order then
		return
	end
	local key = "SkipHatch" .. rarity
	show(player, {
		Key = key,
		Product = key,
		Title = `{string.upper(rarity)} EGG!`,
		Text = "Hatch it right now instead of waiting.",
		Pic = "Clock",
	})
end

function OfferService:OnHatch(player: Player, order: number?, rarity: string?)
	tryStarterPack(player)
	-- Rule 9: a rare pet just came out, the player feels lucky.
	local from = Eggs.ByName[Rules.LuckyAfterHatch]
	if order and from and order >= from.Order then
		show(player, {
			Key = "HatchLuck",
			Product = "LuckyRoll10",
			Title = `{string.upper(rarity or "RARE")} PET! YOU'RE LUCKY!`,
			Text = "Keep the luck going: 10 Lucky Rolls.",
			Pic = "Shop_Lucky10",
		})
	end
end

-- Rule 12: a while into the session, 2x Cash if no cash boost is running.
local function checkSessionBoost(player: Player, session)
	local state = offerState(session)
	state.joinedAt = state.joinedAt or os.clock()
	if state.boostShown or os.clock() - state.joinedAt < Rules.SessionBoostMinutes * 60 then
		return
	end
	local boosts = session.Data.Boosts
	if type(boosts) == "table" and boosts.Cash2x ~= nil then
		return
	end
	if
		show(player, {
			Key = "SessionCash",
			Product = "Cash2xBoost",
			Title = "DOUBLE YOUR CASH!",
			Text = "2x cash from every pet for 15 minutes.",
			Pic = "Shop_Pass2xCash",
		})
	then
		state.boostShown = true
	end
end

function OfferService:Init(services)
	S = services
end

function OfferService:Start()
	task.spawn(function()
		while true do
			task.wait(2)
			for player, session in S.DataService:GetSessions() do
				if session.Data and session.Data.Flags.TutorialDone then
					tryStarterPack(player)
					checkStuck(player, session)
					checkAvalanche(player, session)
					checkSessionBoost(player, session)
				end
			end
		end
	end)
end

return OfferService
