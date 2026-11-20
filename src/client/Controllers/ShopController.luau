--!strict
-- The Shop (GAME_PLAN §6): Robux only, one scrolling window with section buttons on the
-- right, kid order (Offers, Rollers, Eggs, Passes, Boosts, Cash, Codes last), cheapest
-- first. A GIFT TO bar at the top sends giftable products to another player. Products with
-- Id 0 (not created yet) show "SOON". Opens from the HUD SHOP button or the server
-- (OpenShop, e.g. at Cash after the 3rd "not enough cash").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Rollers = require(Shared.Config.Rollers)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local ShopController = {}

local C: any
local window: Frame
local list: ScrollingFrame
local headers: { [string]: Frame } = {}
local items: { { def: any, pass: boolean, card: Frame, buy: TextButton } } = {}
local giftLabel: TextLabel
local giftTo: Player? = nil
local starterCard: Frame? = nil

local SECTIONS = { "Offers", "Rollers", "Eggs", "Passes", "Boosts", "Cash", "Codes" }
local KIND_SECTION: { [string]: string } = {
	StarterPack = "Offers",
	RobuxRoller = "Rollers",
	EggPack = "Eggs",
	HugePet = "Eggs",
	Boost = "Boosts",
	TrainTime = "Boosts",
	PowerPack = "Boosts",
	LuckyRoll = "Boosts",
	SuperLucky = "Boosts",
	ServerLuck = "Boosts",
	GoldenRuns = "Boosts",
	Avalanche = "Boosts",
	CashPack = "Cash",
}

local KIND_ICON: { [string]: string } = {
	StarterPack = "Chest",
	RobuxRoller = "Power",
	EggPack = "GoldenEgg",
	HugePet = "Pets",
	Boost = "Bolt",
	TrainTime = "Clock",
	PowerPack = "Power",
	LuckyRoll = "Luck",
	SuperLucky = "Luck",
	ServerLuck = "Luck",
	GoldenRuns = "Star",
	Avalanche = "Storm",
	CashPack = "Cash",
}
local PASS_ICON: { [string]: string } = {
	Train2x = "Power",
	Cash2x = "Cash",
	AutoTrain = "Shoe",
	PopMagnet = "Magnet",
	Lucky = "Luck",
	GoldenSnowball = "Star",
	VIP = "Crown",
	ExtraEquips = "Pets",
	ExtraSlots = "Base",
	FastHatch = "Clock",
}

local function describe(def: any): string
	if def.Description then
		return def.Description
	end
	local k = def.Kind
	if k == "StarterPack" then
		return "Iron Roller + Epic egg + 3 Lucky Rolls + 15 min 2x Power. Once only!"
	elseif k == "RobuxRoller" then
		local r = Rollers.RobuxById[def.Roller]
		return if r then `x{r.Mult} training forever` else "Training forever"
	elseif k == "EggPack" then
		return `{def.Egg} eggs from your best zone`
	elseif k == "HugePet" then
		return "A Huge pet, yours forever"
	elseif k == "ServerLuck" then
		return `Everyone in the server, {def.Minutes} min`
	elseif k == "Avalanche" then
		return "Starts an Avalanche for the whole server now"
	elseif k == "CashPack" then
		return "Cash that grows with your income"
	elseif k == "LuckyRoll" or k == "SuperLucky" then
		return "Rolls with extra luck for eggs"
	elseif k == "GoldenRuns" then
		return "Smashes 1.5x its size, x2 coins"
	end
	return ""
end

local function buy(def: any, pass: boolean)
	local target = if giftTo and giftTo.Parent and not pass and def.Giftable then giftTo.UserId else nil
	if giftTo and not target then
		Ui.toast("This one can't be gifted", "Bad")
		return
	end
	local ok, why = Net.func("PromptPurchase"):InvokeServer(def.Key, target)
	if not ok and why then
		Ui.toast(why, "Bad")
	end
end

local function header(name: string, order: number)
	local h = Ui.frame({
		Name = "Header_" .. name,
		Size = UDim2.new(1, -12, 0, 40),
		LayoutOrder = order,
		BackgroundColor3 = Ui.Colors.PanelDark,
	})
	Ui.label({
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		Text = string.upper(name),
		TextXAlignment = Enum.TextXAlignment.Left,
	}).Parent =
		h
	h.Parent = list
	headers[name] = h
end

local function card(def: any, pass: boolean, order: number): Frame
	local f = Ui.frame({
		Name = def.Key,
		Size = UDim2.new(1, -12, 0, 76),
		LayoutOrder = order,
		BackgroundColor3 = Ui.Colors.Panel,
	})
	Ui.stroke(f, 2)
	Ui.icon((if pass then PASS_ICON[def.Key] else KIND_ICON[def.Kind]) or "Gift", {
		Size = UDim2.fromOffset(66, 66),
		Position = UDim2.fromOffset(5, 5),
	}).Parent =
		f
	Ui.label({
		Name = "Name",
		Size = UDim2.new(1, -250, 0, 32),
		Position = UDim2.fromOffset(78, 6),
		Text = def.Name,
		TextXAlignment = Enum.TextXAlignment.Left,
	}).Parent =
		f
	Ui.label({
		Name = "Info",
		Size = UDim2.new(1, -250, 0, 26),
		Position = UDim2.fromOffset(78, 42),
		Text = describe(def),
		TextColor3 = Ui.Colors.Ice,
		TextXAlignment = Enum.TextXAlignment.Left,
	}).Parent =
		f
	local b = Ui.button(
		{
			Name = "Buy",
			Size = UDim2.fromOffset(150, 60),
			Position = UDim2.new(1, -158, 0, 8),
			BackgroundColor3 = Ui.Colors.Robux,
		},
		`{Ui.ROBUX}{def.Price}`,
		function()
			buy(def, pass)
		end
	)
	b.Parent = f
	f.Parent = list
	table.insert(items, { def = def, pass = pass, card = f, buy = b })
	return f
end

local function render(data)
	local now = State.now()
	for _, item in items do
		local def = item.def
		local text = `{Ui.ROBUX}{def.Price}`
		local color = Ui.Colors.Robux
		if def.Id == 0 then
			text, color = "SOON", Ui.Colors.PanelDark
		elseif item.pass and data.Gamepasses[def.Key] then
			text, color = "OWNED", Ui.Colors.PanelDark
		elseif def.Kind == "RobuxRoller" and data.RobuxRollers[def.Roller] then
			text, color = "OWNED", Ui.Colors.PanelDark
		elseif giftTo then
			text = if def.Giftable and not item.pass then `GIFT {Ui.ROBUX}{def.Price}` else "NO GIFT"
		end
		Ui.setText(item.buy, text)
		item.buy.BackgroundColor3 = color
	end
	if starterCard then
		local ends = data.Flags.StarterPackEnds
		local live = not data.Flags.StarterPackBought
			and type(ends) == "number"
			and ends > now
			and data.Flags.TutorialDone
		starterCard.Visible = live
		headers.Offers.Visible = live
		if live then
			((starterCard :: Frame):FindFirstChild("Info") :: TextLabel).Text =
				`{describe(Products.ProductByKey.StarterPack)} Ends in {Format.time(ends - now)}`
		end
	end
end

local function setGift(target: Player?)
	giftTo = target
	giftLabel.Text = if target then `GIFT TO: {target.DisplayName}` else "BUYING FOR: YOU"
	if State.data then
		render(State.data)
	end
end

-- Cycles: you -> each other player -> you.
local function nextGift()
	local others = {}
	for _, p in Players:GetPlayers() do
		if p ~= player then
			table.insert(others, p)
		end
	end
	if #others == 0 then
		Ui.toast("Nobody else is in this server yet", "Info")
		setGift(nil)
		return
	end
	local index = 0
	for i, p in others do
		if p == giftTo then
			index = i
		end
	end
	setGift(others[index + 1])
end

function ShopController:Toggle(section: string?)
	if window.Visible and not section then
		Ui.closeWindow(window)
		return
	end
	Ui.openWindow(window)
	Net.event("Analytics"):FireServer("Open", "Shop")
	if section and headers[section] then
		task.defer(function()
			local h = headers[section]
			list.CanvasPosition = Vector2.new(0, h.AbsolutePosition.Y - list.AbsolutePosition.Y + list.CanvasPosition.Y)
		end)
	end
end

function ShopController:Init(controllers)
	C = controllers
	local gui = Ui.screen("Shop", 20)
	local body
	window, body = Ui.window(gui, "Window", "SHOP", Vector2.new(760, 540))
	-- Gift bar.
	local giftBar =
		Ui.frame({ Name = "Gift", Size = UDim2.new(1, -130, 0, 44), BackgroundColor3 = Ui.Colors.PanelDark })
	giftLabel = Ui.label({
		Size = UDim2.new(1, -140, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		Text = "BUYING FOR: YOU",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	giftLabel.Parent = giftBar
	Ui.button({
		Name = "Change",
		Size = UDim2.fromOffset(124, 38),
		Position = UDim2.new(1, -128, 0, 3),
		BackgroundColor3 = Ui.Colors.Yellow,
	}, "GIFT", nextGift).Parent =
		giftBar
	giftBar.Parent = body

	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.new(1, -130, 1, -52)
	list.Position = UDim2.fromOffset(0, 52)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	list.Parent = body

	-- Sections in kid order, cheapest first.
	local bySection: { [string]: { { def: any, pass: boolean } } } = {}
	for _, s in SECTIONS do
		bySection[s] = {}
	end
	for _, def in Products.Gamepasses do
		table.insert(bySection.Passes, { def = def, pass = true })
	end
	for _, def in Products.Products do
		local section = KIND_SECTION[def.Kind]
		if section then
			table.insert(bySection[section], { def = def, pass = false })
		end
	end
	local order = 0
	for _, s in SECTIONS do
		order += 1
		header(s, order)
		local entries = bySection[s]
		table.sort(entries, function(a, b)
			return a.def.Price < b.def.Price
		end)
		for _, e in entries do
			order += 1
			local f = card(e.def, e.pass, order)
			if e.def.Kind == "StarterPack" then
				starterCard = f
			end
		end
		if s == "Codes" then
			order += 1
			Ui.button(
				{
					Name = "OpenCodes",
					Size = UDim2.new(1, -12, 0, 60),
					LayoutOrder = order,
					BackgroundColor3 = Ui.Colors.Ice,
				},
				"ENTER A CODE",
				function()
					C.RewardsController:Open("Codes")
				end
			).Parent =
				list
		end
	end

	-- Section buttons on the right.
	local nav = Ui.frame({
		Name = "Nav",
		Size = UDim2.new(0, 120, 1, 0),
		Position = UDim2.new(1, -120, 0, 0),
		BackgroundTransparency = 1,
	})
	local navList = Instance.new("UIListLayout")
	navList.Padding = UDim.new(0, 6)
	navList.SortOrder = Enum.SortOrder.LayoutOrder
	navList.Parent = nav
	for i, s in SECTIONS do
		Ui.button(
			{ Name = s, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = Ui.Colors.Panel },
			string.upper(s),
			function()
				ShopController:Toggle(s)
			end
		).Parent =
			nav
	end
	nav.Parent = body
end

function ShopController:Start()
	State.observe(render)
	Net.event("OpenShop").OnClientEvent:Connect(function(section)
		ShopController:Toggle(if type(section) == "string" then section else "Offers")
	end)
	Players.PlayerRemoving:Connect(function(p)
		if p == giftTo then
			setGift(nil)
		end
	end)
end

return ShopController
