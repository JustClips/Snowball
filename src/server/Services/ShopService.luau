--!strict
-- (Ported from Sweep the World.) Robux purchases: idempotent ProcessReceipt, gamepass checks, gifting, and what every
-- product grants. Products with Id 0 aren't created yet: their buttons stay hidden.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Eggs = require(Shared.Config.Eggs)
local Products = require(Shared.Config.Products)
local Pets = require(Shared.Config.Pets)
local Rollers = require(Shared.Config.Rollers)

local ShopService = {}

local S: any
-- buyer -> pending gift choice, set when the server opens the purchase prompt.
local pendingGifts: { [Player]: { productId: number, toUserId: number, at: number } } = {}

-- Regional pricing (Dev turned it on 2026-10-31): Roblox charges players in some countries
-- up to 70% less. Gifting would let a cheap-region player buy items for full-price players
-- at a discount, so a gift is only allowed when the buyer's price level (1-1000, 1000 = full
-- price) is at least the recipient's, as Roblox recommends. Kinds in FULL_PRICE_KINDS have
-- regional pricing turned OFF on Roblox (tools/create_products.py keeps it off): gift-only
-- passes and server-wide boosts, since one buyer's price would pay for the whole server.
-- Levels are fetched on join and never kept past the session (Roblox's rule).
local FULL_PRICE_KINDS = Products.FullPriceKinds
local priceLevels: { [number]: number } = {}

local function fetchPriceLevel(player: Player): number?
	local ok, result = pcall(function()
		return MarketplaceService:GetUsersPriceLevelsAsync({ player.UserId })
	end)
	if ok and type(result) == "table" then
		for _, info in result do
			if info.UserId == player.UserId and type(info.PriceLevel) == "number" then
				priceLevels[player.UserId] = info.PriceLevel
			end
		end
	end
	return priceLevels[player.UserId]
end

local function priceLevel(player: Player): number?
	return priceLevels[player.UserId] or fetchPriceLevel(player)
end

-- Whether buyer may gift this product to recipient under regional pricing.
local function giftAllowed(product, buyer: Player, recipient: Player): (boolean, string?)
	if FULL_PRICE_KINDS[product.Kind] then
		return true, nil -- everyone pays the full price for these
	end
	local mine, theirs = priceLevel(buyer), priceLevel(recipient)
	if not mine or not theirs then
		return false, "Gifting is busy, try again in a moment"
	end
	if mine < theirs then
		return false, `Robux prices are different where {recipient.DisplayName} lives, so you can't gift them this`
	end
	return true, nil
end

local function notify(player: Player, text: string, kind: string?)
	Net.fire("Notify", player, text, kind or "Good")
end

-- The 3rd "not enough cash" in a session opens the Shop at Cash (Sweep's shortfall rule),
-- at most SHORTFALL_MAX_OPENS times a session and never twice within the cooldown.
local SHORTFALL_OPENS_AT = 3
local SHORTFALL_MAX_OPENS = 3
local SHOP_OPEN_COOLDOWN = 180

-- Cash packs scale with the player: Seconds of their income, and at least FloorFactor x the
-- next roller they're saving for.
local function cashPackAmount(player: Player, product): number
	local data = S.DataService:GetData(player)
	if not data then
		return 100
	end
	local rate = math.max(S.PetService:GetIncomePerSec(player), Economy.MinIncomeForRewards)
	local nextRoller = Rollers.get(data.Roller + 1)
	local goal = if nextRoller then nextRoller.Price else Economy.rebirthCost(data.Rebirths) * 0.1
	return math.floor(math.max(rate * (product.Seconds or 600), goal * (product.FloorFactor or 1), 100))
end

function ShopService:CashFor(player: Player, seconds: number, floorFactor: number?): number
	return cashPackAmount(player, { Seconds = seconds, FloorFactor = floorFactor or 0 })
end

function ShopService:OfferCashFor(player: Player, _shortfall: any)
	local session = S.DataService:GetSession(player)
	if not session or not session.Data.Flags.TutorialDone then
		return
	end
	local runtime = session.Runtime
	runtime.Shortfalls = (runtime.Shortfalls or 0) + 1
	if runtime.Shortfalls < SHORTFALL_OPENS_AT or (runtime.ShopOpens or 0) >= SHORTFALL_MAX_OPENS then
		return
	end
	if os.clock() - (runtime.ShopOpenedAt or -math.huge) < SHOP_OPEN_COOLDOWN then
		return
	end
	runtime.ShopOpens = (runtime.ShopOpens or 0) + 1
	runtime.ShopOpenedAt = os.clock()
	Net.fire("OpenShop", player, "Cash")
end

local function applyPassEffects(player: Player)
	local data = S.DataService:GetData(player)
	player:SetAttribute("VIP", data and data.Gamepasses.VIP == true or nil)
	if S.PetService then
		S.PetService:RefreshBase(player)
	end
	S.StateService:Mark(player)
end

-- What each product does. Runs without yielding so a receipt can't be granted twice.
local GRANTS: { [string]: (product: any, buyer: Player, recipient: Player) -> () } = {
	StarterPack = function(_product, _buyer, recipient)
		local data = S.DataService:GetData(recipient)
		local pack = Economy.StarterPack
		data.Flags.StarterPackBought = true
		if data.Roller < 3 then
			data.Roller = 3
			S.TrainService:RefreshRoller(recipient)
		end
		S.InventoryService:AddEgg(recipient, pack.EggRarity, "Pine", "StarterPack")
		data.Charges.LuckyRoll += pack.LuckyRolls
		S.BoostService:AddPersonal(recipient, "Train2x", pack.Train2xMinutes)
		notify(
			recipient,
			`Starter Pack: Iron Roller, an {pack.EggRarity} egg, {pack.LuckyRolls} Lucky Rolls and {pack.Train2xMinutes} min of 2x training!`
		)
	end,
	KeepRolling = function(_product, _buyer, recipient)
		-- The ball normally still waits (phase Stopped). If the receipt came too late (left,
		-- server restart), the push isn't lost: the next roll becomes a Lucky Roll.
		if not S.RollService:Continue(recipient) then
			local data = S.DataService:GetData(recipient)
			data.Charges.LuckyRoll += 1
			notify(recipient, "Your push is saved: your next roll is a Lucky Roll!")
		end
	end,
	RainbowPop = function(product, _buyer, recipient)
		-- Granted even if the pop already melted (GAME_PLAN quality bar 6).
		S.BoostService:ApplyPop(recipient, product.Mult, product.Seconds)
		S.AnalyticsService:Custom(recipient, "RainbowPop", product.Mult, { Result = "Bought" })
		notify(recipient, `RAINBOW x{product.Mult} TRAINING for 2 minutes!`)
	end,
	RobuxRoller = function(product, _buyer, recipient)
		local data = S.DataService:GetData(recipient)
		data.RobuxRollers[product.Roller] = true
		S.TrainService:RefreshRoller(recipient)
		notify(recipient, `{product.Name}: x{Rollers.RobuxById[product.Roller].Mult} training forever!`)
	end,
	TrainTime = function(product, _buyer, recipient)
		-- That many minutes of training at Auto Train speed, at your current rate.
		local taps = product.Minutes * 60 * Economy.AutoTrainTapsPerSecond
		local gain = S.TrainService:Grant(recipient, taps, true)
		notify(recipient, `+{Format.big(gain)} Power!`)
	end,
	PowerPack = function(product, _buyer, recipient)
		local gain = S.TrainService:Grant(recipient, product.Taps, true)
		notify(recipient, `+{Format.big(gain)} Power!`)
	end,
	Boost = function(product, _buyer, recipient)
		S.BoostService:AddPersonal(recipient, product.Boost, product.Minutes)
		notify(recipient, `{product.Name} started!`)
	end,
	LuckyRoll = function(product, _buyer, recipient)
		local data = S.DataService:GetData(recipient)
		data.Charges.LuckyRoll += product.Count
		notify(recipient, `+{product.Count} Lucky Rolls!`)
	end,
	SuperLucky = function(product, _buyer, recipient)
		local data = S.DataService:GetData(recipient)
		data.Charges.SuperLucky += product.Count
		notify(recipient, "Your next roll has x100 luck!")
	end,
	ServerLuck = function(product, buyer)
		S.BoostService:AddServerLuck(product.Mult, product.Minutes, buyer)
	end,
	GoldenRuns = function(product, _buyer, recipient)
		local data = S.DataService:GetData(recipient)
		data.Charges.GoldenRuns += product.Count
		notify(recipient, `+{product.Count} Golden Snowball runs!`)
	end,
	EggPack = function(product, _buyer, recipient)
		local data = S.DataService:GetData(recipient)
		local floor = Eggs.BoughtFloor[product.Egg]
		for _ = 1, product.Count do
			S.InventoryService:AddZoneEgg(recipient, math.max(data.BestZone, 3), "Bought", floor)
		end
		notify(recipient, `{product.Name} added to your bag!`)
	end,
	HugePet = function(product, _buyer, recipient)
		S.PetService:GivePet(recipient, product.Pet, { Zone = "Meadow" })
		notify(recipient, `{Pets.ById[product.Pet].Name} is yours!`)
	end,
	SkipHatch = function(product, _buyer, recipient)
		S.HatchService:SkipOne(recipient, product.Rarity)
	end,
	CashPack = function(product, _buyer, recipient)
		local cash = cashPackAmount(recipient, product)
		S.CashService:Give(recipient, cash, product.Key, Enum.AnalyticsEconomyTransactionType.IAP)
		notify(recipient, `+{Format.cash(cash)}!`)
	end,
	Avalanche = function(_product, buyer)
		S.AvalancheService:Trigger(buyer)
	end,
	SkipRebirth = function(_product, _buyer, recipient)
		S.RebirthService:Rebirth(recipient, true)
	end,
	WheelSpins = function(product, _buyer, recipient)
		S.RewardService:AddSpins(recipient, product.Count)
		notify(recipient, `+{product.Count} Lucky Wheel spins!`)
	end,
	DoubleOffline = function(_product, _buyer, recipient)
		S.PetService:DoubleOffline(recipient)
	end,
}

local function processReceipt(info): Enum.ProductPurchaseDecision
	local buyer = Players:GetPlayerByUserId(info.PlayerId)
	local session = buyer and S.DataService:GetSession(buyer)
	if not buyer or not session then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = session.Data
	local purchaseId = tostring(info.PurchaseId)
	if data.ReceiptsGranted[purchaseId] then
		-- Granted before; just make sure it's saved.
		return if S.DataService:SaveNow(buyer)
			then Enum.ProductPurchaseDecision.PurchaseGranted
			else Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local product = Products.ProductById[info.ProductId]
	if not product then
		warn(`[ShopService] receipt for unknown product id {info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local recipient = buyer
	local gift = pendingGifts[buyer]
	if gift and gift.productId == info.ProductId and os.clock() - gift.at <= Products.GiftWindowSeconds then
		pendingGifts[buyer] = nil
		local target = Players:GetPlayerByUserId(gift.toUserId)
		if target and S.DataService:GetSession(target) then
			recipient = target
		else
			notify(buyer, "Your gift's player left, so it went to you instead.", "Info")
		end
	end

	local ok, err = pcall(GRANTS[product.Kind], product, buyer, recipient)
	if not ok then
		warn(`[ShopService] grant {product.Key} failed: {err}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	S.DataService:RecordReceipt(data, purchaseId, tostring(recipient.UserId))
	S.StateService:Mark(recipient)
	-- What the buyer really paid (less than Price with regional pricing).
	local spent = if type(info.CurrencySpent) == "number" then info.CurrencySpent else product.Price
	S.AnalyticsService:Custom(
		buyer,
		"RobuxPurchase",
		spent,
		{ Product = product.Key, Gift = tostring(recipient ~= buyer) }
	)
	S.AnalyticsService:Purchased(buyer, product.Key, spent, product.Kind == "WheelSpins")
	-- The purchase celebration (PurchaseController): instant "you got it" feedback.
	if recipient ~= buyer then
		Net.fire("Purchased", recipient, product.Key, { From = buyer.DisplayName })
		Net.fire("Purchased", buyer, product.Key, { To = recipient.DisplayName })
		S.DataService:SaveNow(recipient)
	else
		Net.fire("Purchased", buyer, product.Key, {})
	end
	if S.DataService:SaveNow(buyer) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function checkPasses(player: Player)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	for _, pass in Products.Gamepasses do
		if pass.Id == 0 and not data.GiftedPasses[pass.Key] then
			-- Never keep a Studio test buy of a pass that doesn't exist yet.
			data.Gamepasses[pass.Key] = nil
		end
		if pass.Id ~= 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
			if ok then
				data.Gamepasses[pass.Key] = (owns or data.GiftedPasses[pass.Key]) or nil
			elseif data.GiftedPasses[pass.Key] then
				data.Gamepasses[pass.Key] = true
			end
		end
	end
	applyPassEffects(player)
end

-- Validates and opens a purchase prompt. giftToUserId makes it a gift.

local function studioTest(def): boolean
	return def.Id == 0 and Products.StudioTestBuys == true and RunService:IsStudio()
end

-- Studio only: grant a product/pass that has no Id yet, as if it was bought.
local function studioGrant(player: Player, def, isPass: boolean, recipient: Player)
	if isPass then
		local data = S.DataService:GetData(recipient)
		data.Gamepasses[def.Key] = true
		applyPassEffects(recipient)
	else
		local ok, err = pcall(GRANTS[def.Kind], def, player, recipient)
		if not ok then
			warn(`[ShopService] studio grant {def.Key} failed: {err}`)
			return
		end
		S.StateService:Mark(recipient)
	end
	print(`[ShopService] STUDIO TEST BUY: {def.Key} for {recipient.Name} (no Robux, Studio only)`)
	Net.fire("Purchased", recipient, def.Key, if recipient ~= player then { From = player.DisplayName } else {})
end

local function promptPurchase(player: Player, key: any, giftToUserId: any): (boolean, string?)
	if type(key) ~= "string" then
		return false, "Bad request"
	end
	local session = S.DataService:GetSession(player)
	if not session then
		return false, "Still loading"
	end
	local pass = Products.PassByKey[key]
	if pass then
		if session.Data.Gamepasses[key] then
			return false, "You already own this"
		end
		if studioTest(pass) then
			studioGrant(player, pass, true, player)
			return true, nil
		end
		if pass.Id == 0 then
			return false, "Coming soon!"
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
		S.AnalyticsService:PromptShown(player, pass.Key)
		return true, nil
	end
	local product = Products.ProductByKey[key]
	if not product or (product.Id == 0 and not studioTest(product)) then
		return false, "Coming soon!"
	end
	local recipient = player
	if giftToUserId ~= nil then
		if type(giftToUserId) ~= "number" or not product.Giftable then
			return false, "This can't be gifted"
		end
		local target = Players:GetPlayerByUserId(giftToUserId)
		if not target or target == player or not S.DataService:GetSession(target) then
			return false, "That player isn't here"
		end
		recipient = target
	end
	local targetData = S.DataService:GetData(recipient)
	if recipient ~= player then
		local allowed, why = giftAllowed(product, player, recipient)
		if not allowed then
			pendingGifts[player] = nil
			return false, why
		end
		pendingGifts[player] = { productId = product.Id, toUserId = recipient.UserId, at = os.clock() }
	else
		pendingGifts[player] = nil
	end
	if product.Kind == "StarterPack" and targetData.Flags.StarterPackBought then
		return false, "Already bought"
	elseif product.Kind == "RobuxRoller" then
		if targetData.RobuxRollers[product.Roller] then
			return false, "Already owned"
		end
		local nextDef = Rollers.nextRobux(targetData.RobuxRollers)
		if not nextDef or nextDef.Id ~= product.Roller then
			return false, "Get the rollers before this one first"
		end
	elseif product.Kind == "SkipRebirth" then
		if not targetData.ReachedVillage then
			return false, "Reach the Village first"
		end
		local need = Economy.rebirthCost(targetData.Rebirths) * Economy.SkipRebirthMinShare
		if BigNum.lt(targetData.Cash, need) then
			return false,
				`Save up {Format.cash(need)} first ({math.floor(Economy.SkipRebirthMinShare * 100)}% of the rebirth)`
		end
	elseif product.Kind == "SkipHatch" and not S.HatchService:HasHatching(recipient, product.Rarity) then
		return false, "No egg of that rarity is hatching"
	elseif product.Kind == "KeepRolling" then
		if recipient ~= player or not S.RollService:ContinueBuying(player) then
			return false, "Your ball already cracked"
		end
	end
	if studioTest(product) then
		studioGrant(player, product, false, recipient)
		return true, nil
	end
	MarketplaceService:PromptProductPurchase(player, product.Id)
	S.AnalyticsService:PromptShown(player, product.Key)
	return true, nil
end

function ShopService:Prompt(player: Player, key: string, giftToUserId: number?): (boolean, string?)
	return promptPurchase(player, key, giftToUserId)
end

function ShopService:Init(services)
	S = services
	MarketplaceService.ProcessReceipt = processReceipt
	Net.onInvoke("PromptPurchase", promptPurchase)
	S.DataService.ProfileLoaded:Connect(function(player, session)
		checkPasses(player)
		local data = session.Data
		if data.Flags.StarterPackEnds == nil and not data.Flags.StarterPackBought and data.Rebirths == 0 then
			data.Flags.StarterPackEnds = os.time() + Economy.StarterPack.Hours * 3600
		end
	end)
	Players.PlayerAdded:Connect(fetchPriceLevel)
	for _, player in Players:GetPlayers() do
		task.spawn(fetchPriceLevel, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		priceLevels[player.UserId] = nil
		pendingGifts[player] = nil
	end)
end

function ShopService:Start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local pass = Products.PassById[passId]
		local data = S.DataService:GetData(player)
		if purchased and pass and data then
			data.Gamepasses[pass.Key] = true
			applyPassEffects(player)
			if pass.Key == "FrostfireRoller" then
				S.TrainService:RefreshRoller(player)
			end
			Net.fire("Purchased", player, pass.Key, {})
			S.AnalyticsService:Custom(player, "GamepassPurchase", pass.Price, { Pass = pass.Key })
			S.AnalyticsService:Purchased(player, pass.Key, pass.Price)
		elseif not purchased and pass then
			S.AnalyticsService:Custom(player, "PurchaseCancelled", pass.Price, { Product = pass.Key })
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		local player = Players:GetPlayerByUserId(userId)
		local product = Products.ProductById[productId]
		if player and product and not purchased then
			S.AnalyticsService:Custom(player, "PurchaseCancelled", product.Price, { Product = product.Key })
			if product.Kind == "KeepRolling" then
				S.RollService:ContinueDeclined(player)
			end
			if product.Kind == "RainbowPop" then
				S.PopService:RainbowDeclined(player)
				S.AnalyticsService:Custom(player, "RainbowPop", product.Mult, { Result = "Declined" })
			end
		end
	end)
	local missing = 0
	for _, def in Products.Products do
		if def.Id == 0 then
			missing += 1
		end
	end
	for _, def in Products.Gamepasses do
		if def.Id == 0 then
			missing += 1
		end
	end
	if missing > 0 then
		warn(
			`[ShopService] {missing} products/gamepasses have no ID yet (Config/Products). Their buttons stay hidden until IDs are added (tools/create_products.py).`
		)
	end
end

return ShopService
