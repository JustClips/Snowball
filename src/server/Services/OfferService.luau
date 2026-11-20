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
--   8 3rd "not enough cash": opens the Shop at Cash (ShopService:OfferCashFor)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Rollers = require(Shared.Config.Rollers)

local Rules = Economy.Offers

local OfferService = {}

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

type Offer = { Key: string, Product: string?, Title: string, Text: string, Open: string? }

local function show(player: Player, offer: Offer, ignoreGlobal: boolean?): boolean
	local session = S.DataService:GetSession(player)
	if not session or not session.Data.Flags.TutorialDone then
		return false
	end
	if offer.Product and not isLive(offer.Product) then
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
		if
			show(player, {
				Key = "TrainTime",
				Product = "TrainTime15",
				Title = "TRAIN FASTER!",
				Text = "15 minutes of training right now, at your best speed.",
			})
		then
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
	if state.full >= Rules.FullBounces then
		if
			show(player, {
				Key = "EggSlots",
				Title = "YOUR BALL IS FULL!",
				Text = "Eggs bounced off. Buy Egg Slots to carry more.",
				Open = "Upgrades",
			})
		then
			state.full = 0
		end
	elseif state.bonks >= Rules.Bonks and (session.Data.Charges.GoldenRuns or 0) == 0 then
		if
			show(player, {
				Key = "GoldenRuns",
				Product = "GoldenRuns1",
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
	})
end

function OfferService:OnHatch(player: Player)
	tryStarterPack(player)
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
				end
			end
		end
	end)
end

return OfferService
