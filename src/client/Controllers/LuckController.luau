--!strict
-- Luck you can see (Dev 2026-11-20: "make some visual indications when your next roll is
-- lucky... take a look at slime rng" and "make some visual effects after we time the hit
-- that shows our luck like throw food for animals does").
--
--  * Above ROLL: a clover pill "LUCKY IN 3" with 10 pips (Slime RNG's roll counter). Every
--    Economy.LuckyEvery-th roll is a free Lucky Roll; when the next one is (or you hold a
--    Lucky/Super Lucky charge) the pill turns rainbow, says LUCKY ROLL! and ROLL gets a
--    spinning rainbow glow behind it.
--  * After the pack-meter hit: the luck reveal (Throw Food's multiplier pop). LUCK x1.2 in
--    the middle of the screen, then each bonus drops in as a chip (PERFECT x1.5, LUCKY ROLL
--    x5, ...) and the number counts up to the total, changing colour by tier (white, green,
--    blue, purple, gold, rainbow), with a punch and a sound at the end.
--  * A lucky roll: a big rainbow LUCKY ROLL! banner, and the ball itself glows rainbow with
--    sparkles (everyone in the server sees that ball).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local LuckController = {}

local C: any

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 90)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 190, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(120, 240, 90)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 200, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(170, 100, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 90)),
})

-- Luck tiers for the reveal's colour.
local TIERS: { { At: number, Color: Color3? } } = {
	{ At = 0, Color = Color3.fromRGB(240, 244, 255) },
	{ At = 2, Color = Color3.fromRGB(110, 235, 90) },
	{ At = 5, Color = Color3.fromRGB(80, 175, 255) },
	{ At = 10, Color = Color3.fromRGB(190, 110, 255) },
	{ At = 50, Color = Color3.fromRGB(255, 205, 50) },
	{ At = 100, Color = nil }, -- rainbow
}

local gui: ScreenGui
-- Roll counter
local pill: Frame? = nil
local pillText: TextLabel
local pillGrad: UIGradient
local pips: { Frame } = {}
local glow: Frame? = nil
local glowGrad: UIGradient
local ready = false
local rollRef: GuiObject? = nil
local raysRef: ImageLabel? = nil
-- Reveal
local reveal: Frame
local revealScale: UIScale
local valueLabel: TextLabel
local valueGrad: UIGradient
local titleLabel: TextLabel
local chipRow: Frame
local banner: TextLabel
local bannerScale: UIScale
local revealSerial = 0
-- Lucky balls
local balls: { [BasePart]: { Highlight } } = {}

local function fmt(v: number): string
	if v >= 1000 then
		return string.format("x%.1fK", v / 1000)
	elseif v >= 10 then
		return "x" .. tostring(math.floor(v + 0.5))
	end
	local s = string.format("%.1f", v)
	if string.sub(s, -2) == ".0" then
		s = string.sub(s, 1, -3)
	end
	return "x" .. s
end

local function tierOf(v: number): Color3?
	local color: Color3? = TIERS[1].Color
	for _, t in TIERS do
		if v >= t.At then
			color = t.Color
		end
	end
	return color
end

local function rainbowLabel(label: TextLabel): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = RAINBOW
	g.Enabled = false
	g.Parent = label
	return g
end

-------------------------------------------------------------------------- roll counter

-- Rolls until the free Lucky Roll: 0 = the next one is lucky.
local function rollsLeft(): (number, boolean)
	local data = State.data :: any
	if not data or not data.Stats then
		return Economy.LuckyEvery - 1, false
	end
	local charges = data.Charges or {}
	local charged = (charges.LuckyRoll or 0) > 0 or (charges.SuperLucky or 0) > 0
	local n = (data.Stats.Runs or 0) + 1
	local left = (Economy.LuckyEvery - n % Economy.LuckyEvery) % Economy.LuckyEvery
	return left, charged
end

local function buildCounter()
	local roll = C.HudController:RollButton() :: GuiObject
	rollRef = roll
	local action = roll.Parent :: GuiObject
	-- Rainbow glow behind ROLL (a sibling just under it, a little bigger).
	local g = Ui.frame({
		Name = "LuckyGlow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 18, 1, 18),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = math.max(0, roll.ZIndex - 1),
		Visible = false,
	})
	glowGrad = Instance.new("UIGradient")
	glowGrad.Color = RAINBOW
	glowGrad.Parent = g
	g.Parent = action
	glow = g

	local p = Ui.frame({
		Name = "LuckyCounter",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -8),
		Size = UDim2.fromOffset(236, 58),
		BackgroundTransparency = 1,
	})
	local body = Ui.frame({
		Name = "Body",
		Size = UDim2.fromOffset(236, 40),
		BackgroundColor3 = Color3.fromRGB(26, 30, 52),
		BackgroundTransparency = 0.15,
	})
	Ui.stroke(body, 3)
	pillGrad = Instance.new("UIGradient")
	pillGrad.Color = RAINBOW
	pillGrad.Enabled = false
	pillGrad.Parent = body
	body.Parent = p
	local icon = Ui.icon("Luck", {
		Size = UDim2.fromOffset(46, 46),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -12, 0.5, 0),
		ZIndex = 3,
	})
	icon.Parent = body
	pillText = Ui.label({
		Name = "Text",
		Size = UDim2.new(1, -46, 0, 30),
		Position = UDim2.fromOffset(40, 5),
		Text = "LUCKY IN 9",
		ZIndex = 3,
	})
	pillText.Parent = body
	-- 10 pips: one per roll, the last one gold (the lucky one).
	local row = Ui.frame({
		Name = "Pips",
		Size = UDim2.fromOffset(236, 12),
		Position = UDim2.fromOffset(0, 46),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	for i = 1, Economy.LuckyEvery do
		local pip = Ui.frame({
			Name = "Pip" .. i,
			LayoutOrder = i,
			Size = UDim2.fromOffset(19, 12),
			BackgroundColor3 = Color3.fromRGB(60, 66, 96),
		})
		Ui.stroke(pip, 2)
		pip.Parent = row
		pips[i] = pip
	end
	row.Parent = p
	p.Parent = roll
	pill = p
end

local function refreshCounter()
	if not pill then
		return
	end
	local left, charged = rollsLeft()
	ready = left == 0 or charged
	local done = Economy.LuckyEvery - 1 - left
	pillText.Text = if ready then "LUCKY ROLL!" else `LUCKY IN {left + 1}`
	pillGrad.Enabled = ready
	pillText.TextColor3 = if ready then Color3.new(1, 1, 1) else Color3.fromRGB(255, 225, 90)
	for i, pip in pips do
		local last = i == #pips
		local on = i <= done or ready
		pip.BackgroundColor3 = if last and on
			then Color3.fromRGB(255, 205, 50)
			elseif on then Color3.fromRGB(110, 235, 90)
			elseif last then Color3.fromRGB(120, 100, 40)
			else Color3.fromRGB(60, 66, 96)
	end
end

-------------------------------------------------------------------------- reveal

local function buildReveal()
	reveal = Ui.frame({
		Name = "Reveal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 190),
		BackgroundTransparency = 1,
		Visible = false,
	})
	Ui.autoScale(reveal)
	revealScale = Instance.new("UIScale")
	revealScale.Name = "Pop"
	revealScale.Parent = reveal
	local rays = Ui.icon("Rays", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(300, 300),
		ImageTransparency = 0.45,
		ZIndex = 1,
	})
	rays.Parent = reveal
	raysRef = rays
	titleLabel = Ui.label({
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(220, 40),
		Text = "LUCK",
		TextColor3 = Color3.fromRGB(255, 225, 90),
		ZIndex = 3,
	})
	titleLabel.Parent = reveal
	local clover = Ui.icon("Luck", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.5, -62, 0, 20),
		Size = UDim2.fromOffset(44, 44),
		ZIndex = 3,
	})
	clover.Parent = reveal
	valueLabel = Ui.label({
		Name = "Value",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 38),
		Size = UDim2.fromOffset(440, 96),
		Text = "x1",
		ZIndex = 3,
	})
	local st = valueLabel:FindFirstChildOfClass("UIStroke")
	if st then
		st.Thickness = 5
	end
	valueGrad = rainbowLabel(valueLabel)
	valueLabel.Parent = reveal
	chipRow = Ui.frame({
		Name = "Chips",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 142),
		Size = UDim2.fromOffset(460, 38),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = chipRow
	chipRow.Parent = reveal
	reveal.Parent = gui

	local holder = Ui.frame({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.fromOffset(700, 110),
		BackgroundTransparency = 1,
	})
	Ui.autoScale(holder)
	banner = Ui.label({
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		Text = "LUCKY ROLL!",
		TextColor3 = Color3.new(1, 1, 1),
		Visible = false,
	})
	local bs = banner:FindFirstChildOfClass("UIStroke")
	if bs then
		bs.Thickness = 6
	end
	local bg = Instance.new("UIGradient")
	bg.Color = RAINBOW
	bg.Parent = banner
	bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner
	banner.Parent = holder
	holder.Parent = gui
end

local function setValue(v: number)
	valueLabel.Text = fmt(v)
	local color = tierOf(v)
	valueGrad.Enabled = color == nil
	valueLabel.TextColor3 = color or Color3.new(1, 1, 1)
end

local function chip(text: string, order: number)
	local c = Ui.label({
		Name = "Chip",
		LayoutOrder = order,
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Color3.fromRGB(26, 30, 52),
		Text = " " .. text .. " ",
		TextScaled = false,
		TextSize = 24,
		TextColor3 = Color3.fromRGB(255, 225, 90),
		ZIndex = 3,
	})
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = c
	local sc = Instance.new("UIScale")
	sc.Scale = 0.3
	sc.Parent = c
	c.Parent = chipRow
	TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

local function punch(scale: UIScale, from: number)
	scale.Scale = from
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

-- Counts the shown value from a to b over `seconds` (yields).
local function countTo(a: number, b: number, seconds: number, mine: number)
	local t0 = os.clock()
	local lastTick = 0
	while os.clock() - t0 < seconds do
		if revealSerial ~= mine then
			return
		end
		local k = (os.clock() - t0) / seconds
		k = 1 - (1 - k) * (1 - k)
		-- Count in log space so x1 -> x500 doesn't sit on tiny numbers.
		setValue(math.exp(math.log(a) + (math.log(b) - math.log(a)) * k))
		if os.clock() - lastTick > 0.06 then
			lastTick = os.clock()
			Ui.sound("Tap", 1 + k * 0.6)
		end
		RunService.RenderStepped:Wait()
	end
	setValue(b)
end

local function showBanner()
	banner.Visible = true
	banner.TextTransparency = 0
	punch(bannerScale, 0.3)
	Ui.sound("RareReveal")
	task.delay(1.8, function()
		TweenService:Create(banner, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		task.wait(0.4)
		banner.Visible = false
	end)
end

local function playReveal(info: any)
	revealSerial += 1
	local mine = revealSerial
	for _, c in chipRow:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local base = math.max(1, tonumber(info.BaseLuck) or 1)
	local parts = if type(info.LuckParts) == "table" then info.LuckParts else {}
	local total = math.max(1, tonumber(info.Luck) or base)
	task.wait(0.45) -- after PERFECT!
	if revealSerial ~= mine then
		return
	end
	reveal.Visible = true
	setValue(1)
	punch(revealScale, 0.4)
	if info.Lucky then
		showBanner()
	end
	countTo(1, base, 0.35, mine)
	local value = base
	for i, part in parts do
		if revealSerial ~= mine then
			return
		end
		local mult = tonumber(part.Mult) or 1
		chip(`{part.Name} {fmt(mult)}`, i)
		Ui.sound("Pop", 1 + i * 0.08)
		countTo(value, value * mult, 0.3, mine)
		value *= mult
		punch(revealScale, 1.12)
	end
	if revealSerial ~= mine then
		return
	end
	setValue(total)
	punch(revealScale, 1.3)
	Ui.sound(if total >= 10 then "Winner" else "Reveal")
	if total >= 10 then
		C.BallController:Shake(0.5)
	end
	task.wait(1.4)
	if revealSerial ~= mine then
		return
	end
	TweenService:Create(revealScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Scale = 0,
	}):Play()
	task.wait(0.27)
	if revealSerial == mine then
		reveal.Visible = false
		revealScale.Scale = 1
	end
end

-------------------------------------------------------------------------- lucky ball

-- The lucky ball: rainbow outline + glow + sparkles (BallController calls this).
function LuckController:DecorateBall(part: BasePart)
	local h = Instance.new("Highlight")
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.FillTransparency = 0.7
	h.OutlineTransparency = 0
	h.Parent = part
	local light = Instance.new("PointLight")
	light.Range = 22
	light.Brightness = 3
	light.Parent = part
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = Ui.Images.Fx_Sparkle or ""
	sparkle.Color = RAINBOW
	sparkle.LightEmission = 1
	sparkle.Lifetime = NumberRange.new(0.6, 1.1)
	sparkle.Rate = 26
	sparkle.Speed = NumberRange.new(2, 6)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkle.Parent = part
	balls[part] = { h }
	part.Destroying:Connect(function()
		balls[part] = nil
	end)
	light.Name = "LuckyLight"
end

-------------------------------------------------------------------------- loop

local function step()
	local t = os.clock()
	-- Spin the rainbows.
	local r = (t * 120) % 360
	if glow then
		glow.Visible = ready and rollRef ~= nil and rollRef.Visible
	end
	if raysRef and reveal.Visible then
		raysRef.Rotation = (t * 40) % 360
	end
	if glow and glow.Visible then
		glowGrad.Rotation = r
		glowGrad.Offset = Vector2.new(math.sin(t * 2) * 0.2, 0)
	end
	if ready then
		pillGrad.Rotation = r
		pillGrad.Offset = Vector2.new((t * 0.6) % 2 - 1, 0)
	end
	if valueGrad.Enabled then
		valueGrad.Offset = Vector2.new((t * 0.8) % 2 - 1, 0)
	end
	local hue = (t * 0.5) % 1
	for part, list in balls do
		local c = Color3.fromHSV(hue, 0.75, 1)
		for _, h in list do
			h.OutlineColor = c
			h.FillColor = c
		end
		local light = part:FindFirstChild("LuckyLight") :: PointLight?
		if light then
			light.Color = c
		end
	end
end

function LuckController:Init(controllers)
	C = controllers
	gui = Ui.screen("Luck", 11)
	buildReveal()
end

function LuckController:Start()
	buildCounter()
	refreshCounter()
	State.observe(function()
		refreshCounter()
	end)
	Net.event("RunStarted").OnClientEvent:Connect(function(userId: number, info)
		if userId == player.UserId and type(info) == "table" then
			task.spawn(playReveal, info)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return LuckController
