--!strict
-- The Robux Shop, ported from Sweep the World (JustClips/Dev ShopController + gen_ui.py
-- shop(), Dev 2026-11-20: "if you can't do something good just get it from sweep the world").
-- Same window and layout, with Snowball's products and pictures:
--   * a dim screen behind; one Window = the Shop panel + the section buttons to its right
--   * the panel: a green stud header ("Shop" + red X), a dark stud body, ONE list that
--     scrolls down (no sideways rows). Sections sit one under the other, each under a
--     centred "-- PASSES --" heading in its colour.
--   * cards in a grid, 3 per row: a coloured stud square, a big picture on a white glow,
--     one line ("+$24K", "2x CASH") and a purple gift button beside a green Robux button.
--   * Featured: the Starter Pack banner (title strip, what's inside as pictures, timer,
--     WORTH pill, Buy). Boosts: the Server Luck card (level now > next level, timer).
--   * the section buttons right of the panel jump the list to their section.
--   * window size: fits the screen height on phones (Sweep's modal scale), smaller on PC.
-- Buying goes through Buy (the Shop hides, "Processing..." shows, the Shop comes back).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

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

-------------------------------------------------------------------------- look (gen_ui.py)

local INK = Color3.fromRGB(23, 25, 30)
local WHITE = Color3.new(1, 1, 1)
local BODY = Color3.fromRGB(58, 62, 73) -- SHOP_BODY
local BODY_STUDS = Color3.fromRGB(74, 79, 92)
local GREEN = Color3.fromRGB(76, 209, 55) -- SHOP_GREEN: header + Robux buttons
local GIFT = Color3.fromRGB(178, 77, 255) -- SHOP_GIFT
local RED = Color3.fromRGB(255, 77, 94) -- DANGER
local BADGE_RED = Color3.fromRGB(255, 46, 77)
local GREY = Color3.fromRGB(166, 174, 194)
local LIGHT = Color3.fromRGB(200, 208, 232)
local YELLOW = "#FFE34D"
-- Sweep's own stud texture and white glow (same uploader, so they load here too).
local STUD = "rbxassetid://117181516497135"
local GLOW = "rbxassetid://139963628852518"

local WIN = Vector2.new(820, 520) -- WIN_W x WIN_H
local PANEL_W = 720
local NAV_W = 96
local CELL = Vector2.new(220, 226) -- 3 cards per row
local BANNER_H = 172
local LUCK_H = 132

type Section = { Key: string, Title: string, Icon: string, Heading: Color3, Card: Color3 }
local SECTIONS: { Section } = {
	{
		Key = "Featured",
		Title = "Featured",
		Icon = "Gift",
		Heading = Color3.fromRGB(255, 212, 59),
		Card = Color3.fromRGB(255, 77, 94),
	},
	{
		Key = "Passes",
		Title = "Passes",
		Icon = "Star",
		Heading = Color3.fromRGB(197, 155, 255),
		Card = Color3.fromRGB(155, 107, 255),
	},
	{
		Key = "Boosts",
		Title = "Boosts",
		Icon = "Luck",
		Heading = Color3.fromRGB(255, 154, 60),
		Card = Color3.fromRGB(255, 128, 48),
	},
	{
		Key = "Power",
		Title = "Power",
		Icon = "Power",
		Heading = Color3.fromRGB(127, 200, 255),
		Card = Color3.fromRGB(62, 142, 240),
	},
	{
		Key = "Rolls",
		Title = "Rolls",
		Icon = "Roll",
		Heading = Color3.fromRGB(255, 126, 182),
		Card = Color3.fromRGB(255, 95, 162),
	},
	{
		Key = "Money",
		Title = "Money",
		Icon = "Cash",
		Heading = Color3.fromRGB(107, 227, 74),
		Card = Color3.fromRGB(76, 209, 55),
	},
}
-- Old section names other code still opens.
local ALIAS: { [string]: string } = { Cash = "Money", Offers = "Featured", Luck = "Rolls", ServerLuck = "Boosts" }

-- Pass cards: the picture and the one line (yellow part + white part).
type Info = { Pic: string, Hi: string, Lo: string, Tag: string? }
local PASS_INFO: { [string]: Info } = {
	Cash2x = { Pic = "Shop_Pass2xCash", Hi = "2x", Lo = "CASH", Tag = "POPULAR" },
	Train2x = { Pic = "Shop_Pass2xPower", Hi = "2x", Lo = "POWER" },
	AutoTrain = { Pic = "Shop_PassFastTrain", Hi = "2x", Lo = "TRAIN SPEED" },
	Lucky = { Pic = "Shop_PassLucky", Hi = "+50%", Lo = "LUCK" },
	PopMagnet = { Pic = "Magnet", Hi = "AUTO", Lo = "POPS" },
	ExtraEquips = { Pic = "Pets", Hi = "+2", Lo = "PET EQUIPS" },
	ExtraSlots = { Pic = "Base", Hi = "+4", Lo = "PET SLOTS" },
	FastHatch = { Pic = "Clock", Hi = "2x", Lo = "HATCH SPEED" },
	CarryTwo = { Pic = "GoldenEgg", Hi = "CARRY", Lo = "2 EGGS" },
	GoldenSnowball = { Pic = "Shop_PassGoldBall", Hi = "GOLD", Lo = "BALL", Tag = "BEST" },
	VIP = { Pic = "Shop_PassVIP", Hi = "", Lo = "VIP" },
}

-------------------------------------------------------------------------- state

local C: any
local gui: ScreenGui
local holder: Frame -- dim + window; Buy hides it while Roblox's buy box is up
local window: Frame
local scale: UIScale
local list: ScrollingFrame
local nav: Frame
local giftPicker: Frame
local giftList: ScrollingFrame
local giftEmpty: TextLabel
local pill: Frame? = nil
local headings: { [string]: GuiObject } = {}
local navButtons: { [string]: GuiButton } = {}
local timers: { () -> () } = {}
local built: { Instance } = {}
local nextOrder = 0

local function canBuy(def: any): boolean
	return def ~= nil and (def.Id ~= 0 or (Products.StudioTestBuys == true and RunService:IsStudio()))
end

local function robux(price: number): string
	return `{Ui.ROBUX} {price}`
end

local function shopBuy(key: string, giftTo: number?)
	task.spawn(Buy.prompt, key, giftTo, holder)
end

-------------------------------------------------------------------------- kit (gen_ui.py primitives)

local function studs(parent: GuiObject, tint: Color3, tile: number?, transparency: number?): ImageLabel
	local s = Instance.new("ImageLabel")
	s.Name = "Studs"
	s.BackgroundTransparency = 1
	s.Image = STUD
	s.ScaleType = Enum.ScaleType.Tile
	s.TileSize = UDim2.fromOffset(tile or 40, tile or 40)
	s.ImageColor3 = tint
	s.ImageTransparency = transparency or 0
	s.Size = UDim2.fromScale(1, 1)
	s.ZIndex = parent.ZIndex
	s.Parent = parent
	return s
end

local function border(parent: GuiObject, thickness: number?, color: Color3?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or INK
	s.Thickness = thickness or 4
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

local function shine(parent: GuiObject, dark: Color3?)
	local g = Instance.new("UIGradient")
	g.Name = "Shine"
	g.Color = ColorSequence.new(WHITE, dark or Color3.fromRGB(188, 196, 212))
	g.Rotation = 90
	g.Parent = parent
end

local function bevel(parent: GuiObject, inset: number, transparency: number)
	local f = Ui.frame({
		Name = "Bevel",
		Size = UDim2.new(1, -inset, 1, -inset),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = parent.ZIndex,
	})
	local s = Instance.new("UIStroke")
	s.Color = WHITE
	s.Thickness = 2
	s.Transparency = transparency
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	f.Parent = parent
end

-- A label (Fredoka, outlined) that fits its box: never bigger than maxSize.
local function text(props: { [string]: any }, maxSize: number, strokeWidth: number?): TextLabel
	props.ZIndex = props.ZIndex or 3
	local l = Ui.label(props)
	local c = Instance.new("UITextSizeConstraint")
	c.Name = "Fit"
	c.MaxTextSize = maxSize
	c.MinTextSize = 7
	c.Parent = l
	local st = l:FindFirstChildOfClass("UIStroke")
	if st then
		local w = strokeWidth or 2.5
		st.Thickness = w
		st.Enabled = w > 0
	end
	return l
end

-- A plate: flat fill with a soft shade and a dark outline (tags, pills).
local function plate(props: { [string]: any }, stroke: number?): Frame
	local f = Ui.frame(props)
	border(f, stroke or 2.5)
	local g = Instance.new("UIGradient")
	g.Name = "Shade"
	g.Color = ColorSequence.new(WHITE, Color3.fromRGB(220, 224, 231))
	g.Rotation = 90
	g.Parent = f
	return f
end

local function tint(object: GuiObject, color: Color3)
	object.BackgroundColor3 = color
	local s = object:FindFirstChild("Studs") :: ImageLabel?
	if s then
		s.ImageColor3 = color
	end
end

-- A raised stud button (square, outlined, lighter top edge) with a "Label" or an icon.
local function button(props: { [string]: any }, label: string?, iconName: string?, textMax: number?): TextButton
	local b = Instance.new("TextButton")
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	for k, v in props do
		(b :: any)[k] = v
	end
	border(b, 3)
	shine(b)
	studs(b, b.BackgroundColor3, 64, 0.45)
	bevel(b, 6, 0.55)
	if iconName then
		Ui.icon(iconName, {
			Size = UDim2.fromOffset(34, 34),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = b.ZIndex + 1,
		}).Parent =
			b
	end
	if label then
		text({
			Name = "Label",
			Size = UDim2.new(1, -12, 1, -6),
			Position = UDim2.fromOffset(6, 3),
			Text = label,
			ZIndex = b.ZIndex + 1,
		}, textMax or 28).Parent =
			b
	end
	return b
end

-- Press feel + click sound.
local function onPress(b: GuiButton, fn: () -> ())
	local s = Instance.new("UIScale")
	s.Parent = b
	b.Activated:Connect(function()
		Ui.sound("Click")
		s.Scale = 0.92
		TweenService:Create(s, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		fn()
	end)
end

local function setPrice(b: GuiButton, label: string, color: Color3)
	Ui.setText(b, label)
	tint(b, color)
end

local function line(hi: string?, lo: string?): string
	local parts = {}
	if hi and hi ~= "" then
		table.insert(parts, `<font color="{YELLOW}">{hi}</font>`)
	end
	if lo and lo ~= "" then
		table.insert(parts, lo)
	end
	return table.concat(parts, " ")
end

local function glow(parent: GuiObject, px: number, pos: UDim2, transparency: number)
	local g = Instance.new("ImageLabel")
	g.Name = "Glow"
	g.BackgroundTransparency = 1
	g.Image = GLOW
	g.ImageTransparency = transparency
	g.Size = UDim2.fromOffset(px, px)
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = pos
	g.ZIndex = 2
	g.Parent = parent
end

local function place(object: GuiObject)
	nextOrder += 1
	object.LayoutOrder = nextOrder
	object.Parent = list
	table.insert(built, object)
end

-------------------------------------------------------------------------- pieces

local function addHeading(section: Section)
	local row =
		Ui.frame({ Name = "Heading_" .. section.Key, Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1 })
	text({
		Name = "Title",
		Size = UDim2.fromScale(1, 1),
		Text = `-- {string.upper(section.Title)} --`,
		TextColor3 = section.Heading,
	}, 40, 4).Parent =
		row
	headings[section.Key] = row
	place(row)
end

type Tile = {
	Key: string,
	Hi: string?,
	Lo: string?,
	Pic: string?,
	Tag: string?,
	Owned: boolean?,
	Gift: boolean?,
}

local function buildCard(item: Tile, color: Color3): Frame
	local def = Products.ProductByKey[item.Key] or Products.PassByKey[item.Key]
	local enabled = not item.Owned and canBuy(def)
	local col = if item.Owned then GREY else color
	local card = Ui.frame({ Name = item.Key, Size = UDim2.fromOffset(CELL.X, CELL.Y), ZIndex = 2 })
	border(card, 4)
	studs(card, col, 40)
	tint(card, col)
	bevel(card, 8, 0.6)
	glow(card, 230, UDim2.new(0.5, 0, 0, 78), 0.25)
	Ui.icon(item.Pic or "Shop", {
		Name = "Icon",
		Size = UDim2.fromOffset(120, 120),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		ZIndex = 3,
	}).Parent =
		card
	if item.Tag then
		local tag = plate({
			Name = "Tag",
			Size = UDim2.fromOffset(104, 26),
			Position = UDim2.fromOffset(-6, 6),
			BackgroundColor3 = BADGE_RED,
			ZIndex = 6,
		})
		text({
			Name = "Label",
			Size = UDim2.new(1, -6, 1, 0),
			Position = UDim2.fromOffset(3, 0),
			Text = item.Tag,
			ZIndex = 7,
		}, 16, 2).Parent =
			tag
		tag.Parent = card
	end
	text({
		Name = "Label",
		Size = UDim2.new(1, -12, 0, 32),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -60),
		Text = line(item.Hi, item.Lo),
		RichText = true,
		ZIndex = 4,
	}, 28, 3).Parent =
		card
	local giftable = item.Gift == true and def ~= nil and def.Giftable == true and enabled
	local buy = button({
		Name = "Buy",
		Size = if giftable then UDim2.new(1, -68, 0, 46) else UDim2.new(1, -16, 0, 46),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -8),
		BackgroundColor3 = GREEN,
		ZIndex = 4,
	}, "")
	buy.Parent = card
	if item.Owned then
		setPrice(buy, "Owned", GREY)
	elseif not enabled then
		setPrice(buy, "SOON", GREY)
	else
		setPrice(buy, robux(def.Price), GREEN)
		onPress(buy, function()
			shopBuy(item.Key)
		end)
	end
	if giftable then
		local gift = button({
			Name = "Gift",
			Size = UDim2.fromOffset(50, 46),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 8, 1, -8),
			BackgroundColor3 = GIFT,
			ZIndex = 4,
		}, nil, "Gift")
		gift.Parent = card
		onPress(gift, function()
			ShopController:OpenGift(item.Key)
		end)
	end
	return card
end

local function addGrid(items: { Tile }, color: Color3)
	if #items == 0 then
		return
	end
	local grid = Ui.frame({
		Name = "Grid",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	})
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.fromOffset(CELL.X, CELL.Y)
	g.CellPadding = UDim2.fromOffset(10, 12)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.HorizontalAlignment = Enum.HorizontalAlignment.Center
	g.Parent = grid
	for i, item in items do
		local card = buildCard(item, color)
		card.LayoutOrder = i
		card.Parent = grid
	end
	place(grid)
end

-- The dark title strip on banners: tag, title, timer pill. Returns the timer label.
local function titleStrip(parent: GuiObject, tag: string, title: string): TextLabel
	local strip = Ui.frame({
		Name = "Strip",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		ZIndex = 3,
	})
	local t = plate({
		Name = "Tag",
		Size = UDim2.fromOffset(96, 30),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		BackgroundColor3 = RED,
		ZIndex = 4,
	})
	text(
		{ Name = "Label", Size = UDim2.new(1, -8, 1, 0), Position = UDim2.fromOffset(4, 0), Text = tag, ZIndex = 5 },
		18,
		2
	).Parent =
		t
	t.Parent = strip
	text({
		Name = "Title",
		Size = UDim2.new(1, -320, 1, -6),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 114, 0.5, 0),
		Text = title,
		TextColor3 = Color3.fromRGB(255, 227, 77),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	}, 30, 3).Parent =
		strip
	local pillFrame = Ui.frame({
		Name = "TimerPill",
		Size = UDim2.fromOffset(200, 30),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(27, 16, 48),
		BackgroundTransparency = 0.2,
		ZIndex = 4,
	})
	Ui.icon("Clock", {
		Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		ZIndex = 5,
	}).Parent =
		pillFrame
	local timer = text({
		Name = "Timer",
		Size = UDim2.new(1, -36, 1, -4),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 32, 0.5, 0),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	}, 18, 0)
	timer.Parent = pillFrame
	pillFrame.Parent = strip
	strip.Parent = parent
	return timer
end

-- What the Starter Pack's items cost on their own (for the WORTH pill).
local function starterWorth(): number
	local pack = Economy.StarterPack
	local byKey = Products.ProductByKey
	local total = 0
	if byKey.LuckyRoll3 then
		total += byKey.LuckyRoll3.Price * pack.LuckyRolls / 3
	end
	if byKey.Train2xBoost then
		total += byKey.Train2xBoost.Price * pack.Train2xMinutes / byKey.Train2xBoost.Minutes
	end
	if byKey.FrozenEgg1 then
		total += byKey.FrozenEgg1.Price
	end
	return math.floor(total)
end

local function addStarterBanner(data)
	local def = Products.ProductByKey.StarterPack
	if not def or not Economy.starterPackLive(data, State.now()) then
		return
	end
	local color = Color3.fromRGB(255, 77, 94)
	local banner = Ui.frame({ Name = "StarterPack", Size = UDim2.new(1, 0, 0, BANNER_H), ZIndex = 2 })
	border(banner, 4, Color3.fromRGB(255, 176, 32))
	studs(banner, color, 40)
	tint(banner, color)
	local timer = titleStrip(banner, "OFFER", "STARTER PACK")
	local items = Ui.frame({
		Name = "Items",
		Size = UDim2.new(1, -220, 0, 100),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		BackgroundTransparency = 1,
		ZIndex = 3,
	})
	local hl = Instance.new("UIListLayout")
	hl.FillDirection = Enum.FillDirection.Horizontal
	hl.Padding = UDim.new(0, 6)
	hl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	hl.SortOrder = Enum.SortOrder.LayoutOrder
	hl.Parent = items
	local pack = Economy.StarterPack
	local chips = {
		{ "Shop_StarterRoller", "ROLLER" },
		{ "Shop_EpicEgg", `{pack.EggRarity} Egg` },
		{ "Shop_Lucky3", `x{pack.LuckyRolls} Rolls` },
		{ "Shop_Pass2xPower", `2x {pack.Train2xMinutes}m` },
	}
	for i, chip in chips do
		local c = Ui.frame({
			Name = "Chip" .. i,
			LayoutOrder = i,
			Size = UDim2.fromOffset(70, 84),
			BackgroundTransparency = 1,
		})
		local back = Ui.frame({
			Name = "Back",
			Size = UDim2.fromOffset(60, 60),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.82,
			ZIndex = 3,
		})
		border(back, 2, WHITE).Transparency = 0.4
		back.Parent = c
		Ui.icon(chip[1], {
			Size = UDim2.fromOffset(54, 54),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 3),
			ZIndex = 4,
		}).Parent =
			c
		text({
			Name = "Caption",
			Size = UDim2.new(1, 6, 0, 22),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Text = chip[2],
			ZIndex = 4,
		}, 16, 2).Parent =
			c
		c.Parent = items
	end
	items.Parent = banner
	local worth = starterWorth()
	if worth > def.Price then
		local w = plate({
			Name = "Worth",
			Size = UDim2.fromOffset(150, 26),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -22, 1, -70),
			BackgroundColor3 = Color3.fromRGB(27, 16, 48),
			ZIndex = 4,
		}, 2)
		text({
			Name = "Label",
			Size = UDim2.new(1, -8, 1, -2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Text = `WORTH {robux(worth)}`,
			TextColor3 = Color3.fromRGB(255, 227, 77),
			ZIndex = 5,
		}, 16, 2).Parent =
			w
		w.Parent = banner
	end
	local b = button({
		Name = "Buy",
		Size = UDim2.fromOffset(190, 54),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -10),
		BackgroundColor3 = GREEN,
		ZIndex = 4,
	}, "", nil, 30)
	b.Parent = banner
	if canBuy(def) then
		setPrice(b, robux(def.Price), GREEN)
		onPress(b, function()
			shopBuy("StarterPack")
		end)
	else
		setPrice(b, "SOON", GREY)
	end
	table.insert(timers, function()
		local ends = data.Flags.StarterPackEnds
		timer.Text = if type(ends) == "number" then Format.dhms(math.max(0, ends - State.now())) else ""
	end)
	place(banner)
end

-------------------------------------------------------------------------- server luck card

local LUCK_TIERS = { 2, 4, 8, 16 }

local function luckLevel(): number
	local mult = State.server("ServerLuck")
	local ends = State.server("ServerLuckEnds")
	if type(mult) == "number" and type(ends) == "number" and ends > State.now() then
		return mult
	end
	return 1
end

-- The next Server Luck product above the level running now (the top one again at max).
local function luckNext(level: number): any
	for _, m in LUCK_TIERS do
		if m > level then
			return Products.ProductByKey["ServerLuck" .. m]
		end
	end
	return Products.ProductByKey["ServerLuck" .. LUCK_TIERS[#LUCK_TIERS]]
end

local function addLuckCard()
	if not luckNext(1) then
		return
	end
	local color = Color3.fromRGB(46, 158, 74)
	local card = Ui.frame({ Name = "ServerLuck", Size = UDim2.new(1, 0, 0, LUCK_H), ZIndex = 2 })
	border(card, 4)
	studs(card, color, 40)
	tint(card, color)
	glow(card, 150, UDim2.new(0, 62, 0.5, 0), 0.35)
	Ui.icon("Shop_ServerLuck", {
		Size = UDim2.fromOffset(100, 100),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 62, 0.5, 0),
		ZIndex = 3,
	}).Parent =
		card
	text({
		Name = "Title",
		Size = UDim2.fromOffset(260, 28),
		Position = UDim2.fromOffset(124, 10),
		Text = "SERVER LUCK",
		TextColor3 = Color3.fromRGB(255, 227, 77),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 26, 3).Parent =
		card
	local levels = text({
		Name = "Levels",
		Size = UDim2.new(1, -320, 0, 56),
		Position = UDim2.fromOffset(124, 38),
		Text = "",
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 50, 3.5)
	levels.Parent = card
	local desc = text({
		Name = "Desc",
		Size = UDim2.new(1, -320, 0, 22),
		Position = UDim2.fromOffset(124, 96),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 16, 2)
	desc.Parent = card
	local timer = text({
		Name = "Timer",
		Size = UDim2.fromOffset(190, 26),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
	}, 20, 2.5)
	timer.Parent = card
	local b = button({
		Name = "Buy",
		Size = UDim2.fromOffset(180, 54),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -14),
		BackgroundColor3 = GREEN,
		ZIndex = 3,
	}, "", nil, 30)
	b.Parent = card
	onPress(b, function()
		local def = luckNext(luckLevel())
		if def and canBuy(def) then
			shopBuy(def.Key)
		end
	end)
	local function fill()
		local level = luckLevel()
		local def = luckNext(level)
		local nextMult = def.Mult or level
		if nextMult > level then
			levels.Text = `{level}x <font color="{YELLOW}">&gt; {nextMult}x</font>`
			desc.Text = "Luckier rolls for EVERYONE here!"
		else
			levels.Text = `<font color="{YELLOW}">{level}x MAX</font>`
			desc.Text = `Top level! Buying adds {def.Minutes} min.`
		end
		local ends = State.server("ServerLuckEnds")
		local left = if type(ends) == "number" then ends - State.now() else 0
		timer.Text = if level > 1 and left > 0 then Format.dhms(left) else `Lasts {def.Minutes} min`
		if canBuy(def) then
			setPrice(b, robux(def.Price), GREEN)
		else
			setPrice(b, "SOON", GREY)
		end
	end
	fill()
	table.insert(timers, fill)
	place(card)
end

-------------------------------------------------------------------------- sections

local function buildFeatured(data, _color: Color3)
	addStarterBanner(data)
end

local function buildPasses(data, color: Color3)
	local passes = {}
	for _, pass in Products.Gamepasses do
		if PASS_INFO[pass.Key] then
			table.insert(passes, pass)
		end
	end
	table.sort(passes, function(a, b)
		local ownA, ownB = data.Gamepasses[a.Key] == true, data.Gamepasses[b.Key] == true
		if ownA ~= ownB then
			return ownB
		end
		return a.Price < b.Price
	end)
	local tiles: { Tile } = {}
	for _, pass in passes do
		local info = PASS_INFO[pass.Key]
		local owned = data.Gamepasses[pass.Key] == true
		table.insert(tiles, {
			Key = pass.Key,
			Hi = info.Hi,
			Lo = info.Lo,
			Pic = info.Pic,
			Tag = if owned then nil else info.Tag,
			Owned = owned,
		})
	end
	addGrid(tiles, color)
end

local function buildBoosts(_data, color: Color3)
	addLuckCard()
	addGrid({
		{ Key = "Train2xBoost", Hi = "2x", Lo = "POWER 10m", Pic = "Shop_Pass2xPower", Gift = true, Tag = "CHEAP" },
		{ Key = "Cash2xBoost", Hi = "2x", Lo = "CASH 15m", Pic = "Shop_Pass2xCash", Gift = true },
		{ Key = "SuperLuckyRoll", Hi = "x100", Lo = "LUCK ROLL", Pic = "Shop_SuperLucky", Gift = true },
	}, color)
end

local function buildPower(data, color: Color3)
	local tiles: { Tile } = {}
	local amounts = if type(data.PowerPacks) == "table" then data.PowerPacks else {}
	for i = 1, 4 do
		local key = "PowerPack" .. i
		local amount = amounts[key]
		table.insert(tiles, {
			Key = key,
			-- What the pack gives YOU right now (it grows with your roller and boosts).
			Hi = if amount then "+" .. Format.big(amount) else "+",
			Lo = "POWER",
			Pic = "Shop_Power" .. i,
			Gift = true,
			Tag = if i == 4 then "BEST VALUE" else nil,
		})
	end
	addGrid(tiles, color)
end

local function buildRolls(_data, color: Color3)
	local tiles: { Tile } = {}
	for _, n in { 3, 10, 35, 100 } do
		table.insert(tiles, {
			Key = "LuckyRoll" .. n,
			Hi = `x{n}`,
			Lo = "LUCKY ROLLS",
			Pic = "Shop_Lucky" .. n,
			Gift = true,
			Tag = if n == 10 then "POPULAR" elseif n == 100 then "BEST VALUE" else nil,
		})
	end
	addGrid(tiles, color)
end

local function buildMoney(data, color: Color3)
	local tiles: { Tile } = {}
	local amounts = if type(data.CashPacks) == "table" then data.CashPacks else {}
	for i = 1, 4 do
		local key = "Cash" .. i
		local amount = amounts[key]
		table.insert(tiles, {
			Key = key,
			-- The server works out each pack for this player (it grows with your income).
			Hi = if amount then "+" .. Format.cash(amount) else "",
			Lo = if amount then nil else "CASH",
			Pic = "Shop_Cash" .. i,
			Gift = true,
			Tag = if i == 4 then "BEST VALUE" else nil,
		})
	end
	addGrid(tiles, color)
end

local BUILDERS: { [string]: (any, Color3) -> () } = {
	Featured = buildFeatured,
	Passes = buildPasses,
	Boosts = buildBoosts,
	Power = buildPower,
	Rolls = buildRolls,
	Money = buildMoney,
}

-------------------------------------------------------------------------- render

local function render()
	local data = State.data
	if not data then
		return
	end
	local scroll = list.CanvasPosition
	for _, object in built do
		object:Destroy()
	end
	table.clear(built)
	table.clear(timers)
	table.clear(headings)
	nextOrder = 0
	for _, section in SECTIONS do
		local before = nextOrder
		addHeading(section)
		BUILDERS[section.Key](data, section.Card)
		if nextOrder == before + 1 then
			-- Nothing for sale here right now: no lone heading.
			headings[section.Key]:Destroy()
			headings[section.Key] = nil
		end
		local navButton = navButtons[section.Key]
		if navButton then
			navButton.Visible = headings[section.Key] ~= nil
		end
	end
	for _, tick in timers do
		tick()
	end
	list.CanvasPosition = scroll
end

-- Scrolls the list so a section's heading is at the top (measured, so phone scales work).
local function jumpTo(key: string)
	local heading = headings[key]
	if not heading then
		return
	end
	local function offset(): number
		return heading.AbsolutePosition.Y - list.AbsolutePosition.Y
	end
	local c0 = list.CanvasPosition.Y
	local d0 = offset()
	local probe = if c0 > 20 then -20 else 20
	list.CanvasPosition = Vector2.new(0, c0 + probe)
	local d1 = offset()
	local k = (d0 - d1) / probe
	if k < 0.05 or k > 5 then
		k = if scale.Scale > 0 then scale.Scale else 1
	end
	list.CanvasPosition = Vector2.new(0, math.max(0, c0 + d0 / k - 4))
end

-- Sweep's modal scale: as big as the screen allows (fits the height on phones), and a
-- bit smaller on PC (Dev on Sweep: "hella huge for pc").
local function rescale()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local view = cam.ViewportSize
	local area = gui.AbsoluteSize -- the safe area (CoreUISafeInsets)
	if area.X < 2 or area.Y < 2 then
		area = view
	end
	local phone = math.min(view.X, view.Y) < 500
	local s = math.clamp(math.min(view.X / 1280, view.Y / 720) * 1.05, 0.4, 1.15)
	local fitScale = math.min((area.Y - 12) / WIN.Y, (area.X - 24) / WIN.X)
	local w = math.max(0.3, math.min(fitScale, math.max(s, 1)))
	scale.Scale = if phone then w else math.min(w, s * 0.8)
end

-------------------------------------------------------------------------- gift picker

local function closeGift()
	giftPicker.Visible = false
	nav.Visible = true
end

function ShopController:OpenGift(key: string)
	for _, c in giftList:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	local n = 0
	for _, other in Players:GetPlayers() do
		if other ~= player then
			n += 1
			local b = button({
				Name = other.Name,
				LayoutOrder = n,
				Size = UDim2.new(1, -10, 0, 46),
				BackgroundColor3 = Color3.fromRGB(47, 155, 255),
				ZIndex = 12,
			}, other.DisplayName, nil, 18)
			b.Parent = giftList
			onPress(b, function()
				closeGift()
				if other.Parent then
					shopBuy(key, other.UserId)
				end
			end)
		end
	end
	giftEmpty.Visible = n == 0
	giftPicker.Visible = true
	nav.Visible = false
end

local function buildGiftPicker()
	giftPicker = Ui.frame({
		Name = "GiftPicker",
		Size = UDim2.fromOffset(380, 330),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, PANEL_W / 2, 0.5, 20),
		BackgroundColor3 = BODY,
		Visible = false,
		ZIndex = 10,
	})
	border(giftPicker, 4)
	local head = Ui.frame({ Name = "Header", Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = GIFT, ZIndex = 10 })
	border(head, 3)
	Ui.icon("Gift", {
		Size = UDim2.fromOffset(38, 38),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		ZIndex = 11,
	}).Parent =
		head
	text({
		Name = "Title",
		Size = UDim2.new(1, -110, 1, 0),
		Position = UDim2.fromOffset(54, 0),
		Text = "Gift to...",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
	}, 28, 3).Parent =
		head
	head.Parent = giftPicker
	local close = button({
		Name = "Close",
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		BackgroundColor3 = RED,
		ZIndex = 12,
	}, "X", nil, 26)
	close.Parent = giftPicker
	onPress(close, closeGift)
	giftList = Instance.new("ScrollingFrame")
	giftList.Name = "List"
	giftList.Size = UDim2.new(1, -24, 1, -72)
	giftList.Position = UDim2.fromOffset(12, 62)
	giftList.BackgroundTransparency = 1
	giftList.BorderSizePixel = 0
	giftList.ScrollBarThickness = 8
	giftList.ScrollBarImageColor3 = INK
	giftList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	giftList.CanvasSize = UDim2.new()
	giftList.ZIndex = 11
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 8)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = giftList
	giftList.Parent = giftPicker
	giftEmpty = text({
		Name = "Empty",
		Size = UDim2.new(1, -24, 0, 40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Text = "Nobody else is in this server yet",
		TextWrapped = true,
		Visible = false,
		ZIndex = 11,
	}, 20, 2)
	giftEmpty.Parent = giftPicker
	giftPicker.Parent = window
end

-------------------------------------------------------------------------- codes box

-- Codes at the very end of the list (Sweep: a purple stud card, ticket, field, Redeem).
local function buildCodes()
	local color = Color3.fromRGB(107, 61, 240)
	local box = Ui.frame({ Name = "CodesBox", Size = UDim2.new(1, 0, 0, 172), LayoutOrder = 100001, ZIndex = 2 })
	border(box, 4)
	studs(box, color, 40)
	tint(box, color)
	Ui.icon("Codes", {
		Size = UDim2.fromOffset(108, 108),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		ZIndex = 3,
	}).Parent =
		box
	text({
		Name = "Title",
		Size = UDim2.new(1, -150, 0, 40),
		Position = UDim2.fromOffset(132, 10),
		Text = "CODES",
		TextColor3 = Color3.fromRGB(255, 200, 60),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 38, 3.5).Parent =
		box
	text({
		Name = "Sub",
		Size = UDim2.new(1, -150, 0, 22),
		Position = UDim2.fromOffset(132, 52),
		Text = "Join the group for free codes!",
		TextColor3 = LIGHT,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 18, 2).Parent =
		box
	local input = Instance.new("TextBox")
	input.Name = "Input"
	input.Size = UDim2.new(1, -318, 0, 54)
	input.Position = UDim2.fromOffset(132, 84)
	input.BackgroundColor3 = WHITE
	input.BorderSizePixel = 0
	input.Text = ""
	input.PlaceholderText = "Enter code..."
	input.PlaceholderColor3 = Color3.fromRGB(138, 144, 160)
	input.TextColor3 = INK
	input.TextSize = 24
	input.FontFace = Ui.FontBlack
	input.ClearTextOnFocus = false
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.ZIndex = 3
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.Parent = input
	border(input, 3)
	input.Parent = box
	local status = text({
		Name = "Status",
		Size = UDim2.new(1, -150, 0, 20),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 132, 1, -8),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 17, 2)
	status.Parent = box
	local redeem = button({
		Name = "Redeem",
		Size = UDim2.fromOffset(156, 54),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 84),
		BackgroundColor3 = GREEN,
		ZIndex = 3,
	}, "Redeem")
	redeem.Parent = box
	onPress(redeem, function()
		local code = input.Text
		if code == "" then
			return
		end
		local ok, why = Net.func("RedeemCode"):InvokeServer(code)
		status.Text = if type(why) == "string" then why elseif ok then "Redeemed!" else "That code doesn't work"
		status.TextColor3 = if ok then Color3.fromRGB(140, 255, 150) else Color3.fromRGB(255, 120, 120)
		if ok then
			input.Text = ""
		end
	end)
	box.Parent = list
end

-------------------------------------------------------------------------- the pill

-- Steal an Egg's cheap pill over the Shop button: "x2 POWER / ONLY R$13".
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
	border(p, 3)
	studs(p, p.BackgroundColor3, 40, 0.3)
	text({ Size = UDim2.new(1, -10, 0, 24), Position = UDim2.fromOffset(5, 2), Text = "x2 POWER" }, 24, 2.5).Parent = p
	text({
		Size = UDim2.new(1, -10, 0, 16),
		Position = UDim2.fromOffset(5, 26),
		Text = `ONLY {Ui.ROBUX}{def.Price}`,
		TextColor3 = Color3.fromRGB(255, 240, 120),
	}, 16, 2).Parent =
		p
	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 5
	hit.Activated:Connect(function()
		Ui.sound("Click")
		task.spawn(Buy.prompt, PILL_KEY, nil, nil)
	end)
	hit.Parent = p
	p.Parent = rail
	pill = p
end

local function updatePill(data)
	local p = pill
	if not p then
		return
	end
	local boosts = data.Boosts
	local running = type(boosts) == "table" and boosts.Train2x ~= nil
	p.Visible = data.Flags.TutorialDone == true and canBuy(Products.ProductByKey[PILL_KEY]) and not running
end

-------------------------------------------------------------------------- open / build

local function isOpen(): boolean
	return holder.Visible
end

function ShopController:Open(section: string?)
	Ui.openWindow(holder)
	closeGift()
	Net.event("Analytics"):FireServer("Open", "Shop")
	rescale()
	list.CanvasPosition = Vector2.zero
	render()
	local key = section and (ALIAS[section] or section)
	if key and key ~= "Featured" then
		-- Let the list lay out first, then aim a few times while the cards size.
		task.spawn(function()
			for _ = 1, 6 do
				task.wait(0.05)
				if not isOpen() then
					return
				end
				jumpTo(key)
			end
		end)
	end
end

function ShopController:Close()
	Ui.closeWindow(holder)
end

function ShopController:Toggle(section: string?)
	if isOpen() and not section then
		ShopController:Close()
	else
		ShopController:Open(section)
	end
end

function ShopController:Init(controllers)
	C = controllers
	gui = Ui.screen("Shop", 20)
	for _, old in gui:GetChildren() do
		old:Destroy()
	end
	holder = Ui.frame({ Name = "Holder", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
	-- Oversized and centred so it also covers the top bar and the notch.
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BorderSizePixel = 0
	dim.BackgroundColor3 = Color3.fromRGB(11, 14, 30)
	dim.BackgroundTransparency = 0.6
	dim.Size = UDim2.new(1, 400, 1, 400)
	dim.AnchorPoint = Vector2.new(0.5, 0.5)
	dim.Position = UDim2.fromScale(0.5, 0.5)
	dim.Parent = holder
	dim.Activated:Connect(function()
		ShopController:Close()
	end)
	window = Ui.frame({
		Name = "Window",
		Size = UDim2.fromOffset(WIN.X, WIN.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
	})
	scale = Instance.new("UIScale")
	scale.Name = "AutoScale"
	scale.Parent = window
	-- The panel: green stud header + dark stud body.
	local panel = Ui.frame({ Name = "Panel", Size = UDim2.new(0, PANEL_W, 1, 0), BackgroundColor3 = BODY })
	border(panel, 4)
	studs(panel, BODY_STUDS, 40)
	local head = Ui.frame({ Name = "Header", Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = GREEN, ZIndex = 3 })
	border(head, 4)
	studs(head, GREEN, 40)
	shine(head, Color3.fromRGB(216, 232, 208))
	text({
		Name = "Title",
		Size = UDim2.new(0, 300, 1, 0),
		Position = UDim2.fromOffset(18, 0),
		Text = "Shop",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	}, 44, 4).Parent =
		head
	local close = button({
		Name = "Close",
		Size = UDim2.fromOffset(58, 54),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		BackgroundColor3 = RED,
		ZIndex = 5,
	}, "X", nil, 34)
	close.Parent = head
	onPress(close, function()
		ShopController:Close()
	end)
	head.Parent = panel
	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.new(1, -12, 1, -80)
	list.Position = UDim2.fromOffset(6, 74)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = Color3.fromRGB(154, 163, 184)
	list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 2
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.Parent = list
	list.Parent = panel
	panel.Parent = window
	-- Section buttons right of the panel: icon + name, tap to jump there.
	-- On a dark stud backing so the buttons don't mix with the HUD behind (phones).
	nav = Ui.frame({
		Name = "Nav",
		Size = UDim2.fromOffset(NAV_W, #SECTIONS * 62 + 12),
		Position = UDim2.fromOffset(PANEL_W + 4, 76),
		BackgroundColor3 = BODY,
	})
	border(nav, 4)
	studs(nav, BODY_STUDS, 40)
	local navPad = Instance.new("UIPadding")
	navPad.PaddingTop = UDim.new(0, 6)
	navPad.Parent = nav
	local nl = Instance.new("UIListLayout")
	nl.Padding = UDim.new(0, 2)
	nl.SortOrder = Enum.SortOrder.LayoutOrder
	nl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	nl.Parent = nav
	for i, section in SECTIONS do
		local b = Instance.new("TextButton")
		b.Name = section.Key
		b.LayoutOrder = i
		b.Text = ""
		b.AutoButtonColor = false
		b.BackgroundTransparency = 1
		b.Size = UDim2.new(1, 0, 0, 60)
		b.ZIndex = 3
		Ui.icon(section.Icon, {
			Size = UDim2.fromOffset(42, 42),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			ZIndex = 3,
		}).Parent =
			b
		text({
			Name = "Label",
			Size = UDim2.new(1, 10, 0, 18),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Text = section.Title,
			TextColor3 = section.Heading,
			ZIndex = 4,
		}, 18, 3).Parent =
			b
		local key = section.Key
		onPress(b, function()
			jumpTo(key)
		end)
		b.Parent = nav
		navButtons[key] = b
	end
	nav.Parent = window
	window.Parent = holder
	holder.Parent = gui
	buildGiftPicker()
	buildCodes()
	buildPill()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	rescale()
end

function ShopController:Start()
	-- Rebuild only when something the Shop shows changed (cash ticks every second).
	local last = ""
	local function amounts(t: any, prefix: string): string
		if type(t) ~= "table" then
			return ""
		end
		local out = {}
		for i = 1, 4 do
			local v = t[prefix .. i]
			table.insert(out, if v then Format.big(v) else "")
		end
		return table.concat(out, ",")
	end
	State.observe(function(data)
		updatePill(data)
		local passes = {}
		for key, on in data.Gamepasses do
			if on then
				table.insert(passes, key)
			end
		end
		table.sort(passes)
		local signature = table.concat({
			table.concat(passes, ","),
			tostring(Economy.starterPackLive(data, State.now())),
			amounts(data.CashPacks, "Cash"),
			amounts(data.PowerPacks, "PowerPack"),
		}, "|")
		if signature ~= last then
			last = signature
			if isOpen() then
				render()
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if isOpen() then
				for _, tick in timers do
					tick()
				end
			end
		end
	end)
	Net.event("OpenShop").OnClientEvent:Connect(function(section)
		ShopController:Open(if type(section) == "string" then section else "Passes")
	end)
	Players.PlayerRemoving:Connect(function(p)
		local b = giftList:FindFirstChild(p.Name)
		if b then
			b:Destroy()
		end
	end)
end

return ShopController
