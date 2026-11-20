--!strict
-- The reward screen after a roll (UI polish 2026-11-20, from the Reward Screen pack Dev
-- sent): the screen dims, a black band runs across the middle and the rewards pop onto it
-- one by one as stud cards: a cash card (+$2.4K) and one card per egg in its rarity colour,
-- each with rays behind the picture. Above the band: the zone you reached in its colour
-- (+ a NEW BEST! tag). Rare eggs add the tiered luck word: LUCKY! > SUPER LUCKY! > INSANE
-- LUCK! > GODLY LUCK!! > IMPOSSIBLE!!!. Tap anywhere (or wait) to continue.
-- Also the big flash words during a roll (Flash).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Zones = require(Shared.Config.Zones)
local Ui = require(script.Parent.Parent.Ui)

local ResultsController = {}

local gui: ScreenGui
local screen: TextButton -- full-screen tap catcher + dim
local band: Frame
local row: Frame
local zoneLabel: TextLabel
local tag: TextLabel
local banner: TextLabel
local bannerScale: UIScale
local serial = 0

local CARD = Vector2.new(150, 190)
local MAX_CARDS = 6

local TIERS = {
	{ Order = 3, Text = "LUCKY!", Color = Color3.fromRGB(255, 70, 70) },
	{ Order = 4, Text = "SUPER LUCKY!", Color = Color3.fromRGB(255, 90, 210) },
	{ Order = 5, Text = "INSANE LUCK!", Color = Color3.fromRGB(120, 240, 60) },
	{ Order = 6, Text = "GODLY LUCK!!", Color = Color3.fromRGB(255, 205, 30) },
	{ Order = 7, Text = "IMPOSSIBLE!!!", Color = Color3.fromRGB(190, 110, 255) },
}

function ResultsController:Flash(text: string, color: Color3)
	Ui.word(text, color)
end

-- The HUD hides while the reward screen is up (nothing else competes with the rewards).
local function setHud(on: boolean)
	local hud = gui.Parent and gui.Parent:FindFirstChild("Hud")
	if hud and hud:IsA("ScreenGui") then
		hud.Enabled = on
	end
end

local function close()
	if screen.Visible then
		setHud(true)
	end
	screen.Visible = false
end

function ResultsController:Close()
	serial += 1
	close()
end

function ResultsController:IsOpen(): boolean
	return screen ~= nil and screen.Visible
end

-- One reward card: a stud block in `color`, rays + picture, a one-line caption at the
-- bottom. Pops in after `delay`.
local function card(
	order: number,
	color: Color3,
	icon: string,
	tint: Color3?,
	caption: string,
	delay: number,
	mine: number
)
	local holder = Ui.frame({
		Name = "Card" .. order,
		LayoutOrder = order,
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
	})
	local pop = Instance.new("UIScale")
	pop.Scale = 0
	pop.Parent = holder
	local c = Ui.frame({ Name = "Card", Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, ZIndex = 4 })
	Ui.block(c, nil, 3, 7)
	c.Parent = holder
	Ui.icon("Fx_Rays", {
		Size = UDim2.fromOffset(CARD.X + 20, CARD.X + 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 78),
		ImageTransparency = 0.45,
		ZIndex = 5,
	}).Parent =
		c
	Ui.icon(icon, {
		Size = UDim2.fromOffset(110, 110),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 78),
		ImageColor3 = tint or Color3.new(1, 1, 1),
		ZIndex = 6,
	}).Parent =
		c
	local l = Ui.label({
		Name = "Caption",
		Size = UDim2.new(1, -12, 0, 36),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Text = caption,
		ZIndex = 7,
	})
	Ui.maxText(l, 30)
	local st = l:FindFirstChildOfClass("UIStroke")
	if st then
		st.Thickness = 2.5
	end
	l.Parent = c
	holder.Parent = row
	task.delay(delay, function()
		if serial ~= mine then
			return
		end
		Ui.sound("Pop", 0.9 + order * 0.06)
		TweenService:Create(pop, TweenInfo.new(0.32, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
end

function ResultsController:Show(result)
	if not result then
		return
	end
	serial += 1
	local mine = serial
	local zone = Zones.List[result.Zone] or Zones.List[1]
	tag.Text = if result.Village then "VILLAGE!" elseif result.Record then "NEW BEST!" else ""
	tag.Visible = tag.Text ~= ""
	zoneLabel.Text = string.upper(zone.Name)
	zoneLabel.TextColor3 = zone.Color
	for _, c in row:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local best = 0
	for _, rarity in result.Eggs do
		local def = Eggs.ByName[rarity]
		best = math.max(best, def and def.Order or 0)
	end
	local tier = nil
	for _, t in TIERS do
		if best >= t.Order then
			tier = t
		end
	end
	task.delay(0.6, function()
		if serial ~= mine then
			return
		end
		screen.Visible = true
		setHud(false)
		Ui.sound("Winner")
		-- Cards: cash first, then the eggs (rarest first), staggered.
		card(1, Ui.Colors.Green, "Cash", nil, "+" .. Format.cash(result.Cash), 0.15, mine)
		Ui.sound("Cash")
		local eggs = table.clone(result.Eggs)
		table.sort(eggs, function(a, b)
			local da, db = Eggs.ByName[a], Eggs.ByName[b]
			return (da and da.Order or 0) > (db and db.Order or 0)
		end)
		for i, rarity in eggs do
			if i > MAX_CARDS - 1 then
				break
			end
			local def = Eggs.ByName[rarity]
			local color = if def then def.Color else Ui.Colors.Muted
			card(
				i + 1,
				color,
				if def and def.Order >= 5 then "GoldenEgg" else "Egg",
				if def and def.Order < 5 then Color3.new(1, 1, 1):Lerp(color, 0.35) else nil,
				string.upper(rarity),
				0.15 + i * 0.18,
				mine
			)
		end
		if #eggs > MAX_CARDS - 1 then
			card(
				MAX_CARDS + 1,
				Ui.Colors.Muted,
				"Egg",
				nil,
				`+{#eggs - (MAX_CARDS - 1)}`,
				0.15 + MAX_CARDS * 0.18,
				mine
			)
		end
		if tier then
			banner.Text = tier.Text
			banner.TextColor3 = tier.Color
			banner.Visible = true
			bannerScale.Scale = 0.3
			TweenService:Create(bannerScale, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		else
			banner.Visible = false
		end
		task.delay(6, function()
			if serial == mine then
				close()
			end
		end)
	end)
end

function ResultsController:Init()
	gui = Ui.screen("Results", 15)
	local root = Ui.root(gui)
	-- Tap anywhere to continue; it also dims the world.
	screen = Instance.new("TextButton")
	screen.Name = "RewardScreen"
	screen.Text = ""
	screen.AutoButtonColor = false
	screen.BorderSizePixel = 0
	screen.BackgroundColor3 = Ui.Colors.Dim
	screen.BackgroundTransparency = 0.45
	screen.Size = UDim2.new(1, 400, 1, 400)
	screen.AnchorPoint = Vector2.new(0.5, 0.5)
	screen.Position = UDim2.fromScale(0.5, 0.5)
	screen.Visible = false
	screen.Activated:Connect(function()
		Ui.sound("Click")
		ResultsController:Close()
	end)
	screen.Parent = root

	-- Everything sits in a 1280x720 design frame that scales with the screen.
	local stage = Ui.frame({
		Name = "Stage",
		Size = UDim2.fromOffset(1280, 400),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	Ui.autoScale(stage)
	stage.Parent = screen

	band = Ui.frame({
		Name = "Band",
		Size = UDim2.new(4, 0, 0, 230),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 10),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.25,
		ZIndex = 2,
	})
	band.Parent = stage
	row = Ui.frame({
		Name = "Rewards",
		Size = UDim2.new(0, 1200, 0, CARD.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 10),
		BackgroundTransparency = 1,
		ZIndex = 3,
	})
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 16)
	list.Parent = row
	row.Parent = stage

	zoneLabel = Ui.label({
		Name = "Zone",
		Size = UDim2.fromOffset(700, 62),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.5, -112),
		Text = "",
		ZIndex = 4,
	})
	Ui.maxText(zoneLabel, 58)
	local zs = zoneLabel:FindFirstChildOfClass("UIStroke")
	if zs then
		zs.Thickness = 4
	end
	zoneLabel.Parent = stage
	tag = Ui.label({
		Name = "Tag",
		Size = UDim2.fromOffset(170, 40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 300, 0.5, -150),
		Rotation = 8,
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.Colors.Gold,
		Text = "",
		ZIndex = 6,
	})
	Ui.stroke(tag, 3)
	Ui.maxText(tag, 24)
	tag.Parent = stage

	banner = Ui.label({
		Name = "Banner",
		Size = UDim2.fromOffset(900, 90),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -60),
		Text = "",
		Visible = false,
		ZIndex = 6,
	})
	Ui.maxText(banner, 84)
	local bs = banner:FindFirstChildOfClass("UIStroke")
	if bs then
		bs.Thickness = 5
	end
	bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner
	banner.Parent = stage

	-- A small tap hint under the band (the pack's "Click Anywhere To Continue", as an icon).
	local hint = Ui.icon("Tap", {
		Name = "Tap",
		Size = UDim2.fromOffset(54, 54),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 136),
		ZIndex = 4,
	})
	hint.Parent = stage
end

return ResultsController
