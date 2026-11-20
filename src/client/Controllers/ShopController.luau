--!strict
-- The Robux Shop, laid out like Sweep the World's (Dev 2026-11-20: "replicate what we have
-- in Sweep the World", which copied the top games): ONE scrolling list, no tabs or pages.
--   * the Starter Pack banner on top while it's for sale (pictures, timer, -x%, buy)
--   * sections one under the other, each under a centred coloured "-- EGGS --" heading
--   * square picture cards: big picture on a light glow, ONE short line, a purple gift
--     button and a green price button (OWNED / SOON / locked when they can't be bought)
--   * a Server Luck card with the four levels in a row and the live server timer
--   * a Codes box last, with its own text field
--   * section buttons (icon + one word) to the RIGHT of the window jump the list there.
-- Kid order: Offers, Rollers, Eggs, Passes, Boosts, Money, Codes; cheapest first inside a
-- section. Opens from the HUD Shop tile or the server (OpenShop, e.g. at Money after the 3rd
-- "not enough cash").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
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
local headings: { [string]: GuiObject } = {}
type Card = { def: any, pass: boolean, frame: Frame, buy: TextButton, gift: TextButton, tag: TextLabel }
local cards: { Card } = {}
local starterBanner: Frame
local starterTimer: TextLabel
local luckNow: TextLabel
local luckButtons: { { def: any, button: TextButton } } = {}
local giftPicker: Frame
local giftList: ScrollingFrame
local giftFor: Card? = nil

local YELLOW = "#FFE34D"
local GIFT = Color3.fromRGB(170, 90, 255)
local PRICE = Color3.fromRGB(70, 205, 95)
local GREY = Color3.fromRGB(90, 96, 120)

type Section = { Key: string, Title: string, Icon: string, Word: string, Color: Color3 }
local SECTIONS: { Section } = {
	{ Key = "Offers", Title = "OFFERS", Icon = "Chest", Word = "Offers", Color = Color3.fromRGB(255, 110, 60) },
	{ Key = "Rollers", Title = "ROLLERS", Icon = "Power", Word = "Rollers", Color = Color3.fromRGB(255, 150, 40) },
	{ Key = "Eggs", Title = "EGGS", Icon = "Egg", Word = "Eggs", Color = Color3.fromRGB(170, 90, 255) },
	{ Key = "Passes", Title = "PASSES", Icon = "Crown", Word = "Passes", Color = Color3.fromRGB(60, 170, 255) },
	{ Key = "Boosts", Title = "BOOSTS", Icon = "Bolt", Word = "Boosts", Color = Color3.fromRGB(255, 80, 150) },
	{ Key = "Money", Title = "MONEY", Icon = "Cash", Word = "Money", Color = Color3.fromRGB(70, 205, 95) },
	{ Key = "Codes", Title = "CODES", Icon = "Codes", Word = "Codes", Color = Color3.fromRGB(150, 120, 255) },
}
local SECTION_COLOR: { [string]: Color3 } = {}
for _, s in SECTIONS do
	SECTION_COLOR[s.Key] = s.Color
end

local KIND_SECTION: { [string]: string } = {
	RobuxRoller = "Rollers",
	EggPack = "Eggs",
	HugePet = "Eggs",
	LuckyRoll = "Boosts",
	SuperLucky = "Boosts",
	GoldenRuns = "Boosts",
	TrainTime = "Boosts",
	PowerPack = "Boosts",
	Boost = "Boosts",
	Avalanche = "Boosts",
	CashPack = "Money",
}

local KIND_ICON: { [string]: string } = {
	RobuxRoller = "Power",
	EggPack = "GoldenEgg",
	HugePet = "Pets",
	LuckyRoll = "Luck",
	SuperLucky = "Luck",
	GoldenRuns = "Star",
	TrainTime = "Clock",
	PowerPack = "Power",
	Boost = "Bolt",
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
-- One short line per pass: big yellow part + small white part.
local PASS_LINE: { [string]: { string } } = {
	Train2x = { "2x", "POWER" },
	Cash2x = { "2x", "CASH" },
	AutoTrain = { "2x", "SPEED" },
	PopMagnet = { "AUTO", "POPS" },
	Lucky = { "+50%", "LUCK" },
	GoldenSnowball = { "GOLD", "BALL" },
	VIP = { "VIP", "" },
	ExtraEquips = { "+2", "EQUIP" },
	ExtraSlots = { "+4", "SLOTS" },
	FastHatch = { "FAST", "HATCH" },
}
local CASH_WORD = { Cash1 = "PILE", Cash2 = "BAG", Cash3 = "CRATE", Cash4 = "VAULT" }

local function line(hi: string, lo: string): string
	if lo == "" then
		return `<font color="{YELLOW}">{hi}</font>`
	end
	return `<font color="{YELLOW}">{hi}</font> {lo}`
end

local function cardLine(def: any, pass: boolean): string
	if pass then
		local l = PASS_LINE[def.Key] or { "", string.upper(def.Name) }
		return line(l[1], l[2])
	end
	local k = def.Kind
	if k == "RobuxRoller" then
		local r = Rollers.RobuxById[def.Roller]
		return line(if r then `x{Format.number(r.Mult)}` else "", "TRAIN")
	elseif k == "EggPack" then
		return line(`x{def.Count}`, string.upper(def.Egg))
	elseif k == "HugePet" then
		return line("HUGE", string.upper((string.gsub(def.Name, "^Huge ", ""))))
	elseif k == "LuckyRoll" then
		return line(`x{def.Count}`, "LUCKY")
	elseif k == "SuperLucky" then
		return line("x100", "LUCK")
	elseif k == "GoldenRuns" then
		return line(`x{def.Count}`, "GOLD")
	elseif k == "TrainTime" then
		return line(`{def.Minutes}m`, "TRAIN")
	elseif k == "PowerPack" then
		return line(`+{Format.number(def.Taps)}`, "REPS")
	elseif k == "Boost" then
		return line("2x", if def.Boost == "Cash2x" then `CASH {def.Minutes}m` else `POWER {def.Minutes}m`)
	elseif k == "Avalanche" then
		return line("NOW", "AVALANCHE")
	elseif k == "CashPack" then
		return line(CASH_WORD[def.Key] or "CASH", "")
	end
	return line("", string.upper(def.Name))
end

local function canBuy(def: any): boolean
	return def.Id ~= 0 or (Products.StudioTestBuys and RunService:IsStudio())
end

local function prompt(key: string, giftTo: number?)
	local ok, why = Net.func("PromptPurchase"):InvokeServer(key, giftTo)
	if not ok and why then
		Ui.toast(why, "Bad")
	end
end

-------------------------------------------------------------------------- pieces

local function heading(section: Section, order: number)
	local h = Ui.label({
		Name = "Heading_" .. section.Key,
		LayoutOrder = order,
		Size = UDim2.new(1, -20, 0, 50),
		Text = `-- {section.Title} --`,
		TextColor3 = section.Color,
	})
	local st = h:FindFirstChildOfClass("UIStroke")
	if st then
		st.Thickness = 4
	end
	h.Parent = list
	headings[section.Key] = h
end

local CELL = Vector2.new(164, 210)
local function grid(name: string, order: number): Frame
	local g = Ui.frame({
		Name = "Grid_" .. name,
		LayoutOrder = order,
		Size = UDim2.new(1, -16, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL.X, CELL.Y)
	layout.CellPadding = UDim2.fromOffset(10, 12)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = g
	g.Parent = list
	return g
end

local function smallButton(name: string, color: Color3, props: { [string]: any }, onClick: () -> ()): TextButton
	local b = Ui.button(props, "", onClick)
	b.Name = name
	b.BackgroundColor3 = color
	return b
end

local function card(parent: Frame, def: any, pass: boolean, order: number, color: Color3): Card
	local f = Ui.frame({ Name = def.Key, LayoutOrder = order, BackgroundColor3 = color })
	Ui.corner(f, 18)
	Ui.gradient(f)
	Ui.stroke(f, 4)
	local glow = Ui.frame({
		Name = "Glow",
		Size = UDim2.fromOffset(120, 120),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 72),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.72,
	})
	Ui.corner(glow, 60)
	glow.Parent = f
	Ui.icon((if pass then PASS_ICON[def.Key] else KIND_ICON[def.Kind]) or "Gift", {
		Size = UDim2.fromOffset(116, 116),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 72),
		ZIndex = 2,
	}).Parent =
		f
	Ui.label({
		Name = "Line",
		Size = UDim2.new(1, -12, 0, 32),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -58),
		Text = cardLine(def, pass),
		RichText = true,
		ZIndex = 3,
	}).Parent =
		f
	local tag = Ui.label({
		Name = "Tag",
		Size = UDim2.fromOffset(82, 26),
		Position = UDim2.fromOffset(-6, 6),
		Rotation = -8,
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.Colors.Red,
		Text = "",
		Visible = false,
		ZIndex = 5,
	})
	Ui.corner(tag, 8)
	tag.Parent = f
	local entry: Card
	local gift = smallButton("Gift", GIFT, {
		Size = UDim2.fromOffset(48, 44),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -8),
		ZIndex = 4,
	}, function()
		ShopController:OpenGift(entry)
	end)
	Ui.icon("Gift", { Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), ZIndex = 5 }).Parent = gift
	gift.Visible = def.Giftable == true and not pass
	gift.Parent = f
	local buy = smallButton("Buy", PRICE, {
		Size = if gift.Visible then UDim2.new(1, -70, 0, 44) else UDim2.new(1, -16, 0, 44),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -8),
		ZIndex = 4,
	}, function()
		prompt(def.Key)
	end)
	buy.Parent = f
	f.Parent = parent
	entry = { def = def, pass = pass, frame = f, buy = buy, gift = gift, tag = tag }
	table.insert(cards, entry)
	return entry
end

-- Starter Pack banner (pictures of what's inside, timer, buy).
local function buildStarter(order: number)
	local b = Ui.frame({
		Name = "StarterBanner",
		LayoutOrder = order,
		Size = UDim2.new(1, -16, 0, 176),
		BackgroundColor3 = Color3.fromRGB(255, 90, 70),
	})
	Ui.corner(b, 18)
	Ui.stroke(b, 4, Color3.fromRGB(255, 190, 40))
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 190, 120))
	g.Rotation = 90
	g.Parent = b
	local strip = Ui.frame({
		Name = "Strip",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
	})
	Ui.corner(strip, 18)
	strip.Parent = b
	local tag = Ui.label({
		Name = "Tag",
		Size = UDim2.fromOffset(92, 30),
		Position = UDim2.fromOffset(8, 7),
		Rotation = -5,
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.Colors.Red,
		Text = "ONCE!",
		ZIndex = 3,
	})
	Ui.corner(tag, 8)
	tag.Parent = strip
	Ui.label({
		Name = "Title",
		Size = UDim2.new(1, -330, 0, 34),
		Position = UDim2.fromOffset(112, 5),
		Text = "STARTER PACK",
		TextColor3 = Color3.fromRGB(255, 227, 77),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	}).Parent =
		strip
	local pill = Ui.frame({
		Name = "TimerPill",
		Size = UDim2.fromOffset(190, 32),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(27, 16, 48),
		BackgroundTransparency = 0.2,
		ZIndex = 3,
	})
	Ui.corner(pill, 16)
	Ui.icon("Clock", { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(2, 1), ZIndex = 4 }).Parent = pill
	starterTimer = Ui.label({
		Name = "Timer",
		Size = UDim2.new(1, -44, 1, -6),
		Position = UDim2.fromOffset(38, 3),
		Text = "",
		ZIndex = 4,
	})
	starterTimer.Parent = pill
	pill.Parent = strip
	strip.Parent = b
	-- What's inside.
	local pack = Economy.StarterPack
	local chips = {
		{ "Power", "ROLLER" },
		{ "GoldenEgg", string.upper(pack.EggRarity) },
		{ "Luck", `x{pack.LuckyRolls}` },
		{ "Bolt", `2x {pack.Train2xMinutes}m` },
	}
	local row = Ui.frame({
		Name = "Items",
		Size = UDim2.new(1, -250, 0, 116),
		Position = UDim2.fromOffset(10, 52),
		BackgroundTransparency = 1,
	})
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.Padding = UDim.new(0, 8)
	rl.Parent = row
	for i, c in chips do
		local chip = Ui.frame({ Name = "Chip" .. i, Size = UDim2.fromOffset(92, 116), BackgroundTransparency = 1 })
		local back = Ui.frame({
			Name = "Back",
			Size = UDim2.fromOffset(84, 84),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.7,
		})
		Ui.corner(back, 14)
		Ui.stroke(back, 2, Color3.new(1, 1, 1))
		back.Parent = chip
		Ui.icon(c[1], { Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), ZIndex = 2 }).Parent = back
		Ui.label({
			Name = "Caption",
			Size = UDim2.new(1, 6, 0, 28),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Text = c[2],
			ZIndex = 3,
		}).Parent =
			chip
		chip.Parent = row
	end
	row.Parent = b
	local def = Products.ProductByKey.StarterPack
	local buy = smallButton("Buy", PRICE, {
		Size = UDim2.fromOffset(210, 64),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -14),
		ZIndex = 4,
	}, function()
		prompt("StarterPack")
	end)
	Ui.setText(buy, `{Ui.ROBUX}{def.Price}`)
	buy.Parent = b
	starterBanner = b
	b.Parent = list
end

-- Server Luck: what's on now, and the four levels side by side.
local function buildLuck(order: number)
	local f = Ui.frame({
		Name = "ServerLuck",
		LayoutOrder = order,
		Size = UDim2.new(1, -16, 0, 168),
		BackgroundColor3 = Color3.fromRGB(46, 158, 74),
	})
	Ui.corner(f, 18)
	Ui.gradient(f)
	Ui.stroke(f, 4)
	Ui.icon("Luck", { Size = UDim2.fromOffset(96, 96), Position = UDim2.fromOffset(10, 8), ZIndex = 2 }).Parent = f
	Ui.label({
		Name = "Title",
		Size = UDim2.new(0, 300, 0, 40),
		Position = UDim2.fromOffset(116, 10),
		Text = "SERVER LUCK",
		TextColor3 = Color3.fromRGB(255, 227, 77),
		TextXAlignment = Enum.TextXAlignment.Left,
	}).Parent =
		f
	luckNow = Ui.label({
		Name = "Now",
		Size = UDim2.new(1, -130, 0, 30),
		Position = UDim2.fromOffset(116, 54),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	luckNow.Parent = f
	local row = Ui.frame({
		Name = "Levels",
		Size = UDim2.new(1, -20, 0, 52),
		Position = UDim2.new(0, 10, 1, -62),
		BackgroundTransparency = 1,
	})
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.Padding = UDim.new(0, 8)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rl.Parent = row
	local levels = {}
	for _, def in Products.Products do
		if def.Kind == "ServerLuck" then
			table.insert(levels, def)
		end
	end
	table.sort(levels, function(a, b)
		return a.Mult < b.Mult
	end)
	for i, def in levels do
		local b = smallButton("Level" .. def.Mult, PRICE, {
			LayoutOrder = i,
			Size = UDim2.new(1 / #levels, -8, 1, 0),
		}, function()
			prompt(def.Key)
		end)
		Ui.setText(b, `<font color="{YELLOW}">{def.Mult}x</font> {Ui.ROBUX}{def.Price}`)
		local l = b:FindFirstChild("Label") :: TextLabel?
		if l then
			l.RichText = true
		end
		b.Parent = row
		table.insert(luckButtons, { def = def, button = b })
	end
	row.Parent = f
	f.Parent = list
end

-- Codes box at the very end (Sweep: a purple card with the field right in the Shop).
local function buildCodes(order: number)
	local f = Ui.frame({
		Name = "CodesBox",
		LayoutOrder = order,
		Size = UDim2.new(1, -16, 0, 150),
		BackgroundColor3 = Color3.fromRGB(107, 61, 240),
	})
	Ui.corner(f, 18)
	Ui.gradient(f)
	Ui.stroke(f, 4)
	Ui.icon("Codes", {
		Size = UDim2.fromOffset(104, 104),
		Position = UDim2.fromOffset(12, 20),
		Rotation = -10,
		ZIndex = 2,
	}).Parent =
		f
	Ui.label({
		Name = "Title",
		Size = UDim2.new(1, -150, 0, 40),
		Position = UDim2.fromOffset(132, 12),
		Text = "CODES",
		TextColor3 = Color3.fromRGB(255, 227, 77),
		TextXAlignment = Enum.TextXAlignment.Left,
	}).Parent =
		f
	local box = Instance.new("TextBox")
	box.Name = "Input"
	box.Size = UDim2.new(1, -320, 0, 54)
	box.Position = UDim2.fromOffset(132, 64)
	box.BackgroundColor3 = Color3.new(1, 1, 1)
	box.BorderSizePixel = 0
	box.Text = ""
	box.PlaceholderText = "Code..."
	box.PlaceholderColor3 = Color3.fromRGB(138, 144, 160)
	box.TextColor3 = Ui.Colors.Ink
	box.FontFace = Ui.Font
	box.TextSize = 26
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.Parent = box
	Ui.corner(box, 12)
	Ui.stroke(box, 3)
	box.Parent = f
	local redeem = smallButton("Redeem", PRICE, {
		Size = UDim2.fromOffset(160, 54),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 64),
	}, function()
		if box.Text == "" then
			return
		end
		local ok, why = Net.func("RedeemCode"):InvokeServer(box.Text)
		Ui.toast(why or (if ok then "Redeemed!" else "That code doesn't work"), if ok then "Good" else "Bad")
		if ok then
			box.Text = ""
		end
	end)
	Ui.setText(redeem, "REDEEM")
	redeem.Parent = f
	f.Parent = list
	headings.Codes = f
end

-------------------------------------------------------------------------- gifting

local function giftTo(target: Player)
	local entry = giftFor
	giftPicker.Visible = false
	giftFor = nil
	if entry and target.Parent then
		prompt(entry.def.Key, target.UserId)
	end
end

function ShopController:OpenGift(entry: Card)
	for _, c in giftList:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	local n = 0
	for _, p in Players:GetPlayers() do
		if p ~= player then
			n += 1
			local b = smallButton(p.Name, Ui.Colors.HeaderDark, {
				LayoutOrder = n,
				Size = UDim2.new(1, -12, 0, 50),
			}, function()
				giftTo(p)
			end)
			Ui.setText(b, p.DisplayName)
			b.Parent = giftList
		end
	end
	if n == 0 then
		Ui.toast("Nobody else is in this server yet", "Info")
		return
	end
	giftFor = entry
	giftPicker.Visible = true
end

local function buildGiftPicker()
	giftPicker = Ui.frame({
		Name = "GiftPicker",
		Size = UDim2.fromOffset(380, 340),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Ui.Colors.PanelDark,
		Visible = false,
		ZIndex = 40,
	})
	Ui.corner(giftPicker, 16)
	Ui.stroke(giftPicker, 4)
	local head = Ui.frame({ Name = "Header", Size = UDim2.new(1, 0, 0, 54), BackgroundColor3 = GIFT, ZIndex = 41 })
	Ui.corner(head, 16)
	Ui.gradient(head)
	head.Parent = giftPicker
	Ui.icon("Gift", { Size = UDim2.fromOffset(42, 42), Position = UDim2.fromOffset(8, 6), ZIndex = 42 }).Parent = head
	Ui.label({
		Size = UDim2.new(1, -120, 1, -12),
		Position = UDim2.fromOffset(58, 6),
		Text = "GIFT TO...",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 42,
	}).Parent =
		head
	local x = smallButton("Close", Ui.Colors.Red, {
		Size = UDim2.fromOffset(42, 42),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		ZIndex = 43,
	}, function()
		giftPicker.Visible = false
		giftFor = nil
	end)
	Ui.setText(x, "X")
	x.Parent = head
	giftList = Instance.new("ScrollingFrame")
	giftList.Name = "Players"
	giftList.Size = UDim2.new(1, -16, 1, -66)
	giftList.Position = UDim2.fromOffset(8, 60)
	giftList.BackgroundTransparency = 1
	giftList.BorderSizePixel = 0
	giftList.ScrollBarThickness = 6
	giftList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	giftList.CanvasSize = UDim2.new()
	giftList.ZIndex = 41
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.Parent = giftList
	giftList.Parent = giftPicker
	giftPicker.Parent = window
end

-------------------------------------------------------------------------- live state

local function setButton(b: TextButton, text: string, color: Color3)
	Ui.setText(b, text)
	b.BackgroundColor3 = color
end

local function render(data)
	if not data then
		return
	end
	local now = State.now()
	local nextRoller = Rollers.nextRobux(data.RobuxRollers)
	for _, c in cards do
		local def = c.def
		local tag = ""
		if c.pass and data.Gamepasses[def.Key] then
			setButton(c.buy, "OWNED", GREY)
		elseif def.Kind == "RobuxRoller" and data.RobuxRollers[def.Roller] then
			setButton(c.buy, "OWNED", GREY)
		elseif not canBuy(def) then
			setButton(c.buy, "SOON", GREY)
		elseif def.Kind == "RobuxRoller" and (not nextRoller or nextRoller.Id ~= def.Roller) then
			setButton(c.buy, `{Ui.ROBUX}{def.Price}`, GREY)
			tag = "LOCKED"
		else
			setButton(c.buy, `{Ui.ROBUX}{def.Price}`, PRICE)
			if def.Kind == "RobuxRoller" then
				tag = "NEXT"
			end
		end
		c.tag.Text = tag
		c.tag.Visible = tag ~= ""
		c.tag.BackgroundColor3 = if tag == "LOCKED" then GREY else Ui.Colors.Red
		c.gift.Visible = def.Giftable == true and not c.pass and canBuy(def)
	end
	-- Starter banner.
	local live = Economy.starterPackLive(data, now)
	starterBanner.Visible = live
	headings.Offers.Visible = live
	if live then
		starterTimer.Text = Format.countdown(data.Flags.StarterPackEnds - now)
	end
	-- Server Luck.
	local mult = State.server("ServerLuck")
	local ends = State.server("ServerLuckEnds")
	if type(mult) == "number" and type(ends) == "number" and ends > now then
		luckNow.Text = `NOW: {mult}x  {Format.countdown(ends - now)}`
	else
		luckNow.Text = "15 min for EVERYONE"
	end
	for _, l in luckButtons do
		l.button.BackgroundColor3 = if canBuy(l.def) then PRICE else GREY
	end
end

-------------------------------------------------------------------------- open / build

function ShopController:Toggle(section: string?)
	if window.Visible and not section then
		Ui.closeWindow(window)
		return
	end
	Ui.openWindow(window)
	giftPicker.Visible = false
	Net.event("Analytics"):FireServer("Open", "Shop")
	render(State.data)
	-- Old callers use "Cash"; the section is called Money now.
	local key = if section == "Cash" then "Money" else section
	if key and headings[key] then
		task.defer(function()
			local h = headings[key]
			if not h.Visible then
				return
			end
			list.CanvasPosition = Vector2.new(0, h.AbsolutePosition.Y - list.AbsolutePosition.Y + list.CanvasPosition.Y)
		end)
	end
end

function ShopController:Init(controllers)
	C = controllers
	local gui = Ui.screen("Shop", 20)
	local body
	window, body = Ui.window(gui, "Window", "SHOP", Vector2.new(780, 560))

	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = Color3.fromRGB(154, 163, 184)
	list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.Parent = list
	list.Parent = body

	-- Sort products into sections, cheapest first.
	local bySection: { [string]: { { def: any, pass: boolean } } } = {}
	for _, s in SECTIONS do
		bySection[s.Key] = {}
	end
	for _, def in Products.Gamepasses do
		table.insert(bySection.Passes, { def = def, pass = true })
	end
	for _, def in Products.Products do
		local key = KIND_SECTION[def.Kind]
		if key then
			table.insert(bySection[key], { def = def, pass = false })
		end
	end

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	for _, s in SECTIONS do
		if s.Key == "Codes" then
			buildCodes(100_000)
		else
			heading(s, nextOrder())
			if s.Key == "Offers" then
				buildStarter(nextOrder())
			end
			local entries = bySection[s.Key]
			table.sort(entries, function(a, b)
				return a.def.Price < b.def.Price
			end)
			if #entries > 0 then
				local g = grid(s.Key, nextOrder())
				for i, e in entries do
					card(g, e.def, e.pass, i, s.Color)
				end
			end
			if s.Key == "Boosts" then
				buildLuck(nextOrder())
			end
		end
	end

	-- Section buttons right of the window: icon + one word, tap to jump there.
	local nav = Ui.frame({
		Name = "Nav",
		Size = UDim2.new(0, 84, 1, -70),
		Position = UDim2.new(1, 10, 0, 64),
		BackgroundTransparency = 1,
	})
	local navList = Instance.new("UIListLayout")
	navList.Padding = UDim.new(0, 4)
	navList.SortOrder = Enum.SortOrder.LayoutOrder
	navList.Parent = nav
	for i, s in SECTIONS do
		local holder = Ui.frame({
			Name = s.Key,
			LayoutOrder = i,
			Size = UDim2.fromOffset(84, 66),
			BackgroundTransparency = 1,
		})
		local t = Ui.tile(s.Key, s.Icon, s.Word, s.Color, function()
			ShopController:Toggle(s.Key)
		end, 46)
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.Position = UDim2.new(0.5, 0, 0, 0)
		t.Parent = holder
		holder.Parent = nav
	end
	nav.Parent = window

	buildGiftPicker()
end

function ShopController:Start()
	State.observe(render)
	task.spawn(function()
		while true do
			task.wait(1)
			if window.Visible then
				render(State.data)
			end
		end
	end)
	Net.event("OpenShop").OnClientEvent:Connect(function(section)
		ShopController:Toggle(if type(section) == "string" then section else "Offers")
	end)
	Players.PlayerRemoving:Connect(function(p)
		if giftPicker.Visible then
			for _, c in giftList:GetChildren() do
				if c.Name == p.Name then
					c:Destroy()
				end
			end
		end
	end)
end

return ShopController
