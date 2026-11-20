--!strict
-- The Robux Shop, copied from the games Dev picked (Dev 2026-11-20: "copy the popular games,
-- not Sweep the World"):
--   * Steal an Egg sells only a few things in its Shop (a handful of passes, Robux speed
--     boosts from small to huge, timer skips), so we sell a short list too: Passes, Power,
--     Luck, Server Luck and Cash. Rollers are sold on the roller's upgrade board, egg skips
--     and rescue items where you need them, the rest through contextual offers.
--   * Throw Food For Animals' Food Shop look: magenta gradient header + red X (Ui.window),
--     dark body, rows of cards that scroll SIDEWAYS. A card is tinted like a rarity (grey >
--     green > blue > purple > orange > pink as the item gets bigger), has its name on top
--     with a small word under it, a big picture, a grey plate with what it does, and ONE
--     full-width button (green Robux price / dark OWNED / grey SOON).
--   * Steal an Egg's cheap pill under the Shop button ("x2 Speed / ONLY 13 R$").
-- Every product has its own picture (art/icons_shop, ForgeUI); a product whose picture isn't
-- uploaded yet falls back to a pack icon.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Buy = require(script.Parent.Parent.Buy)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local ShopController = {}

local C: any
local window: Frame
local list: ScrollingFrame
local rows: { [string]: GuiObject } = {}
type Card = { def: any, pass: boolean, buy: TextButton, gift: GuiButton, stroke: UIStroke, plate: TextLabel }
local cards: { Card } = {}
local starterBanner: Frame
local starterTimer: TextLabel
local luckNow: TextLabel
local giftPicker: Frame
local giftList: ScrollingFrame
local giftFor: Card? = nil
local pill: Frame? = nil

local GIFT = Color3.fromRGB(170, 90, 255)
local PRICE = Color3.fromRGB(70, 205, 95)
local GREY = Color3.fromRGB(90, 96, 120)
local DARK = Color3.fromRGB(40, 44, 66)

-- Rarity-style tints (Throw Food card backgrounds), smallest to biggest.
local TINT = {
	Color3.fromRGB(150, 156, 172), -- grey
	Color3.fromRGB(80, 190, 90), -- green
	Color3.fromRGB(70, 140, 240), -- blue
	Color3.fromRGB(160, 90, 240), -- purple
	Color3.fromRGB(255, 150, 40), -- orange
	Color3.fromRGB(255, 90, 170), -- pink
}

-- What the Shop sells, in kid order. Each entry: product/pass key, its picture, the small
-- word under the name, the plate line, the tint step, and a fallback pack icon.
type Item = { Key: string, Pass: boolean?, Pic: string, Word: string, Plate: string, Tint: number, Fallback: string }
type Row = { Key: string, Title: string, Icon: string, Items: { Item } }
local ROWS: { Row } = {
	{
		Key = "Passes",
		Title = "PASSES",
		Icon = "Crown",
		Items = {
			{
				Key = "Cash2x",
				Pass = true,
				Pic = "Pass2xCash",
				Word = "FOREVER",
				Plate = "2x CASH",
				Tint = 2,
				Fallback = "Cash",
			},
			{
				Key = "Train2x",
				Pass = true,
				Pic = "Pass2xPower",
				Word = "FOREVER",
				Plate = "2x POWER",
				Tint = 5,
				Fallback = "Power",
			},
			{
				Key = "AutoTrain",
				Pass = true,
				Pic = "PassFastTrain",
				Word = "FOREVER",
				Plate = "2x SPEED",
				Tint = 3,
				Fallback = "Shoe",
			},
			{
				Key = "Lucky",
				Pass = true,
				Pic = "PassLucky",
				Word = "FOREVER",
				Plate = "+50% LUCK",
				Tint = 2,
				Fallback = "Luck",
			},
			{
				Key = "GoldenSnowball",
				Pass = true,
				Pic = "PassGoldBall",
				Word = "FOREVER",
				Plate = "GOLD BALL",
				Tint = 5,
				Fallback = "Star",
			},
			{
				Key = "VIP",
				Pass = true,
				Pic = "PassVIP",
				Word = "FOREVER",
				Plate = "VIP",
				Tint = 6,
				Fallback = "Crown",
			},
		},
	},
	{
		Key = "Power",
		Title = "POWER",
		Icon = "Power",
		Items = {
			{ Key = "PowerPack1", Pic = "Power1", Word = "SMALL", Plate = "+POWER", Tint = 1, Fallback = "Power" },
			{ Key = "PowerPack2", Pic = "Power2", Word = "BIG", Plate = "+POWER", Tint = 2, Fallback = "Power" },
			{ Key = "PowerPack3", Pic = "Power3", Word = "HUGE", Plate = "+POWER", Tint = 4, Fallback = "Power" },
			{ Key = "PowerPack4", Pic = "Power4", Word = "MEGA", Plate = "+POWER", Tint = 5, Fallback = "Power" },
		},
	},
	{
		Key = "Luck",
		Title = "LUCKY ROLLS",
		Icon = "Luck",
		Items = {
			{
				Key = "SuperLucky",
				Pic = "SuperLucky",
				Word = "1 ROLL",
				Plate = "x100 LUCK",
				Tint = 6,
				Fallback = "Luck",
			},
			{ Key = "LuckyRoll3", Pic = "Lucky3", Word = "ROLLS", Plate = "x3", Tint = 1, Fallback = "Luck" },
			{ Key = "LuckyRoll10", Pic = "Lucky10", Word = "ROLLS", Plate = "x10", Tint = 2, Fallback = "Luck" },
			{ Key = "LuckyRoll35", Pic = "Lucky35", Word = "ROLLS", Plate = "x35", Tint = 4, Fallback = "Luck" },
			{ Key = "LuckyRoll100", Pic = "Lucky100", Word = "ROLLS", Plate = "x100", Tint = 5, Fallback = "Luck" },
		},
	},
	{
		Key = "ServerLuck",
		Title = "SERVER LUCK",
		Icon = "Luck",
		Items = {
			{ Key = "ServerLuck2", Pic = "ServerLuck", Word = "15 MIN", Plate = "2x ALL", Tint = 2, Fallback = "Luck" },
			{ Key = "ServerLuck4", Pic = "ServerLuck", Word = "15 MIN", Plate = "4x ALL", Tint = 3, Fallback = "Luck" },
			{ Key = "ServerLuck8", Pic = "ServerLuck", Word = "15 MIN", Plate = "8x ALL", Tint = 4, Fallback = "Luck" },
			{
				Key = "ServerLuck16",
				Pic = "ServerLuck",
				Word = "15 MIN",
				Plate = "16x ALL",
				Tint = 5,
				Fallback = "Luck",
			},
		},
	},
	{
		Key = "Money",
		Title = "CASH",
		Icon = "Cash",
		Items = {
			{ Key = "Cash1", Pic = "Cash1", Word = "PILE", Plate = "+CASH", Tint = 1, Fallback = "Cash" },
			{ Key = "Cash2", Pic = "Cash2", Word = "BAG", Plate = "+CASH", Tint = 2, Fallback = "Cash" },
			{ Key = "Cash3", Pic = "Cash3", Word = "CRATE", Plate = "+CASH", Tint = 4, Fallback = "Cash" },
			{ Key = "Cash4", Pic = "Cash4", Word = "VAULT", Plate = "+CASH", Tint = 5, Fallback = "Cash" },
		},
	},
}

local function pic(name: string, fallback: string): string
	return Ui.Images["Shop_" .. name] or Ui.Images[fallback] or ""
end
ShopController.Pic = pic

local function canBuy(def: any): boolean
	return def.Id ~= 0 or (Products.StudioTestBuys and RunService:IsStudio())
end

-- Shop hides, "Processing..." shows, the Shop comes back after (Buy).
local function prompt(key: string, giftTo: number?)
	task.spawn(Buy.prompt, key, giftTo, window)
end

-------------------------------------------------------------------------- pieces

local CARD = Vector2.new(150, 214)

local function card(parent: GuiObject, item: Item, def: any, order: number)
	local tint = TINT[item.Tint] or TINT[1]
	local f = Ui.frame({ Name = item.Key, LayoutOrder = order, Size = UDim2.fromOffset(CARD.X, CARD.Y) })
	f.BackgroundColor3 = tint
	Ui.corner(f, 14)
	Ui.gradient(f)
	local stroke = Ui.stroke(f, 3)
	Ui.label({
		Name = "Name",
		Size = UDim2.new(1, -12, 0, 26),
		Position = UDim2.fromOffset(6, 6),
		Text = string.upper(def.Name),
		ZIndex = 3,
	}).Parent =
		f
	Ui.label({
		Name = "Word",
		Size = UDim2.new(1, -12, 0, 16),
		Position = UDim2.fromOffset(6, 32),
		Text = item.Word,
		TextColor3 = Color3.fromRGB(235, 240, 255),
		ZIndex = 3,
	}).Parent =
		f
	local image = Instance.new("ImageLabel")
	image.Name = "Picture"
	image.BackgroundTransparency = 1
	image.Image = pic(item.Pic, item.Fallback)
	image.ScaleType = Enum.ScaleType.Fit
	image.Size = UDim2.fromOffset(96, 96)
	image.AnchorPoint = Vector2.new(0.5, 0)
	image.Position = UDim2.new(0.5, 0, 0, 50)
	image.ZIndex = 2
	image.Parent = f
	-- Grey plate (Throw Food's "Tier N").
	local plate = Ui.frame({
		Name = "Plate",
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, CARD.Y - 80),
		BackgroundColor3 = Color3.fromRGB(70, 74, 92),
		BackgroundTransparency = 0.1,
		ZIndex = 3,
	})
	Ui.corner(plate, 6)
	local plateText = Ui.label({
		Name = "Text",
		Size = UDim2.new(1, -8, 1, -4),
		Position = UDim2.fromOffset(4, 2),
		Text = item.Plate,
		TextColor3 = Color3.fromRGB(255, 227, 77),
		ZIndex = 4,
	})
	plateText.Parent = plate
	plate.Parent = f
	local buy = Ui.button(
		{
			Name = "Buy",
			Size = UDim2.new(1, -16, 0, 42),
			Position = UDim2.new(0, 8, 1, -50),
			BackgroundColor3 = PRICE,
			ZIndex = 3,
		},
		"",
		function()
			prompt(def.Key)
		end
	)
	buy.Parent = f
	-- Small purple gift corner (only on giftable products).
	local gift = Instance.new("ImageButton")
	gift.Name = "Gift"
	gift.BackgroundColor3 = GIFT
	gift.BorderSizePixel = 0
	gift.Size = UDim2.fromOffset(34, 34)
	gift.AnchorPoint = Vector2.new(1, 0)
	gift.Position = UDim2.new(1, 6, 0, 44)
	gift.Image = Ui.Images.Gift or ""
	gift.ZIndex = 5
	Ui.corner(gift, 10)
	Ui.stroke(gift, 2)
	gift.Parent = f
	local entry: Card =
		{ def = def, pass = item.Pass == true, buy = buy, gift = gift, stroke = stroke, plate = plateText }
	gift.Activated:Connect(function()
		Ui.sound("Click")
		ShopController:OpenGift(entry)
	end)
	f.Parent = parent
	table.insert(cards, entry)
end

local function row(r: Row, order: number)
	local holder = Ui.frame({
		Name = "Row_" .. r.Key,
		LayoutOrder = order,
		Size = UDim2.new(1, -12, 0, CARD.Y + 56),
		BackgroundTransparency = 1,
	})
	Ui.icon(r.Icon, { Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(4, 2), ZIndex = 2 }).Parent = holder
	local title = Ui.label({
		Name = "Title",
		Size = UDim2.new(0.6, 0, 0, 32),
		Position = UDim2.fromOffset(46, 4),
		Text = r.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	title.Parent = holder
	if r.Key == "ServerLuck" then
		luckNow = Ui.label({
			Name = "Now",
			Size = UDim2.new(0.45, 0, 0, 26),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 8),
			Text = "",
			TextColor3 = Color3.fromRGB(140, 255, 150),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		luckNow.Parent = holder
	end
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "Cards"
	strip.Size = UDim2.new(1, 0, 0, CARD.Y + 14)
	strip.Position = UDim2.fromOffset(0, 42)
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.ScrollBarThickness = 6
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.CanvasSize = UDim2.new()
	strip.ElasticBehavior = Enum.ElasticBehavior.Always
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 10)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = strip
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingTop = UDim.new(0, 2)
	pad.Parent = strip
	strip.Parent = holder
	local n = 0
	for _, item in r.Items do
		local def = if item.Pass then Products.PassByKey[item.Key] else Products.ProductByKey[item.Key]
		if def then
			n += 1
			card(strip, item, def, n)
		end
	end
	holder.Parent = list
	rows[r.Key] = holder
end

-- Starter Pack banner on top while it's for sale (straight, no tilted tags).
local function buildStarter(order: number)
	local b = Ui.frame({
		Name = "StarterBanner",
		LayoutOrder = order,
		Size = UDim2.new(1, -12, 0, 170),
		BackgroundColor3 = Color3.fromRGB(255, 110, 70),
	})
	Ui.corner(b, 16)
	Ui.gradient(b)
	Ui.stroke(b, 4, Color3.fromRGB(255, 200, 50))
	Ui.label({
		Name = "Title",
		Size = UDim2.new(1, -260, 0, 36),
		Position = UDim2.fromOffset(14, 8),
		Text = "STARTER PACK",
		TextColor3 = Color3.fromRGB(255, 240, 120),
		TextXAlignment = Enum.TextXAlignment.Left,
	}).Parent =
		b
	local timerPill = Ui.frame({
		Name = "TimerPill",
		Size = UDim2.fromOffset(170, 34),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		BackgroundColor3 = Color3.fromRGB(27, 16, 48),
		BackgroundTransparency = 0.2,
	})
	Ui.corner(timerPill, 17)
	Ui.icon("Clock", { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(2, 2), ZIndex = 2 }).Parent =
		timerPill
	starterTimer = Ui.label({
		Name = "Timer",
		Size = UDim2.new(1, -44, 1, -8),
		Position = UDim2.fromOffset(38, 4),
		Text = "",
		ZIndex = 2,
	})
	starterTimer.Parent = timerPill
	timerPill.Parent = b
	local pack = Economy.StarterPack
	local chips = {
		{ "StarterRoller", "Power", "ROLLER" },
		{ "EpicEgg", "GoldenEgg", string.upper(pack.EggRarity) },
		{ "Lucky3", "Luck", `x{pack.LuckyRolls}` },
		{ "Pass2xPower", "Bolt", `2x {pack.Train2xMinutes}m` },
	}
	local items = Ui.frame({
		Name = "Items",
		Size = UDim2.new(1, -250, 0, 112),
		Position = UDim2.fromOffset(12, 50),
		BackgroundTransparency = 1,
	})
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.Padding = UDim.new(0, 8)
	rl.Parent = items
	for i, c in chips do
		local chip = Ui.frame({ Name = "Chip" .. i, Size = UDim2.fromOffset(90, 112), BackgroundTransparency = 1 })
		local back = Ui.frame({
			Size = UDim2.fromOffset(84, 84),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.7,
		})
		Ui.corner(back, 14)
		back.Parent = chip
		local im = Instance.new("ImageLabel")
		im.BackgroundTransparency = 1
		im.Image = pic(c[1], c[2])
		im.ScaleType = Enum.ScaleType.Fit
		im.Size = UDim2.new(1, -8, 1, -8)
		im.Position = UDim2.fromOffset(4, 4)
		im.ZIndex = 2
		im.Parent = back
		Ui.label({
			Size = UDim2.new(1, 6, 0, 26),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Text = c[3],
			ZIndex = 3,
		}).Parent =
			chip
		chip.Parent = items
	end
	items.Parent = b
	local def = Products.ProductByKey.StarterPack
	local buy = Ui.button(
		{
			Name = "Buy",
			Size = UDim2.fromOffset(210, 64),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -14, 1, -14),
			BackgroundColor3 = PRICE,
		},
		`{Ui.ROBUX}{def.Price}`,
		function()
			prompt("StarterPack")
		end
	)
	buy.Parent = b
	starterBanner = b
	b.Parent = list
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
			local b = Ui.button(
				{
					Name = p.Name,
					LayoutOrder = n,
					Size = UDim2.new(1, -12, 0, 50),
					BackgroundColor3 = Ui.Colors.HeaderDark,
				},
				p.DisplayName,
				function()
					giftTo(p)
				end
			)
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
	Ui.button(
		{
			Name = "Close",
			Size = UDim2.fromOffset(42, 42),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 6),
			BackgroundColor3 = Ui.Colors.Red,
			ZIndex = 43,
		},
		"X",
		function()
			giftPicker.Visible = false
			giftFor = nil
		end
	).Parent =
		head
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

-- Steal an Egg's cheap pill under the Shop button: "x2 POWER / ONLY R$13".
local PILL_KEY = "Train2xBoost"
local function buildPill()
	local def = Products.ProductByKey[PILL_KEY]
	local shopTile = C.HudController:Tile("Shop")
	if not def or not shopTile then
		return
	end
	local rail = C.HudController:Buttons()
	local p = Ui.frame({
		Name = "ShopPill",
		Size = UDim2.fromOffset(138, 46),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 0, -8),
		BackgroundColor3 = Color3.fromRGB(60, 200, 255),
		Visible = false,
	})
	Ui.corner(p, 12)
	Ui.gradient(p)
	Ui.stroke(p, 3)
	Ui.label({
		Size = UDim2.new(1, -10, 0, 24),
		Position = UDim2.fromOffset(5, 2),
		Text = "x2 POWER",
		ZIndex = 2,
	}).Parent =
		p
	Ui.label({
		Size = UDim2.new(1, -10, 0, 16),
		Position = UDim2.fromOffset(5, 26),
		Text = `ONLY {Ui.ROBUX}{def.Price}`,
		TextColor3 = Color3.fromRGB(255, 240, 120),
		ZIndex = 2,
	}).Parent =
		p
	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 3
	hit.Activated:Connect(function()
		Ui.sound("Click")
		prompt(PILL_KEY)
	end)
	hit.Parent = p
	p.Parent = rail
	pill = p
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
	for _, c in cards do
		local def = c.def
		local owned = c.pass and data.Gamepasses[def.Key] == true
		if owned then
			setButton(c.buy, "OWNED", DARK)
		elseif not canBuy(def) then
			setButton(c.buy, "SOON", GREY)
		else
			setButton(c.buy, `{Ui.ROBUX}{def.Price}`, PRICE)
		end
		c.stroke.Color = if owned then Color3.fromRGB(200, 255, 200) else Ui.Colors.Ink
		c.gift.Visible = def.Giftable == true and not c.pass and canBuy(def)
		-- Cash packs show what they give you right now (it grows with your income).
		if def.Kind == "CashPack" and type(data.CashPacks) == "table" and data.CashPacks[def.Key] then
			c.plate.Text = "+" .. Format.cash(data.CashPacks[def.Key])
		end
	end
	local live = Economy.starterPackLive(data, now)
	starterBanner.Visible = live
	if live then
		starterTimer.Text = Format.countdown(data.Flags.StarterPackEnds - now)
	end
	local mult = State.server("ServerLuck")
	local ends = State.server("ServerLuckEnds")
	if luckNow then
		luckNow.Text = if type(mult) == "number"
				and type(ends) == "number"
				and ends > now
			then `NOW {mult}x  {Format.countdown(ends - now)}`
			else ""
	end
	-- The Shop pill: after the tutorial, while 2x Power isn't running.
	if pill then
		local def = Products.ProductByKey[PILL_KEY]
		local boosts = data.Boosts
		local running = type(boosts) == "table" and boosts.Train2x ~= nil
		pill.Visible = data.Flags.TutorialDone == true and canBuy(def) and not running
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
	local key = if section == "Cash" then "Money" elseif section == "Offers" then nil else section
	list.CanvasPosition = Vector2.zero
	if key and rows[key] then
		task.defer(function()
			local h = rows[key]
			list.CanvasPosition = Vector2.new(0, h.AbsolutePosition.Y - list.AbsolutePosition.Y + list.CanvasPosition.Y)
		end)
	end
end

function ShopController:Init(controllers)
	C = controllers
	local gui = Ui.screen("Shop", 20)
	local body
	window, body = Ui.window(gui, "Window", "SHOP", Vector2.new(720, 560))
	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = Color3.fromRGB(154, 163, 184)
	list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = list
	list.Parent = body
	buildStarter(1)
	for i, r in ROWS do
		row(r, i + 1)
	end
	buildGiftPicker()
	buildPill()
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
		ShopController:Toggle(if type(section) == "string" then section else "Passes")
	end)
	Players.PlayerRemoving:Connect(function(p)
		if giftPicker.Visible then
			local b = giftList:FindFirstChild(p.Name)
			if b then
				b:Destroy()
			end
		end
	end)
end

return ShopController
