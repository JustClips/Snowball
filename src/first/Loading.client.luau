--!strict
-- Loading screen (Dev 2026-11-20: "make a loading screen ... prefetch assets/sound effects").
-- Runs from ReplicatedFirst, so it shows before anything else. While it is up it preloads
-- every UI image, sound and animation in Config, plus the models the server puts in
-- ReplicatedStorage (Assets, EggModels), with ContentProvider:PreloadAsync in small
-- batches. Stud style: sky gradient, falling snow, the snowball rolling along a bar.
-- It never blocks play for long: at most MAX_SECONDS, and a SKIP button after SKIP_AFTER.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MIN_SECONDS = 1.5
local MAX_SECONDS = 25
local SKIP_AFTER = 8
local BATCH = 12

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
local INK = Color3.fromRGB(16, 18, 24)

local gui = Instance.new("ScreenGui")
gui.Name = "Loading"
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.DisplayOrder = 1000
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Global

local function stroke(parent: Instance, thickness: number, round: boolean?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = INK
	s.LineJoinMode = if round then Enum.LineJoinMode.Round else Enum.LineJoinMode.Miter
	s.Parent = parent
	return s
end

local function label(props: { [string]: any }, maxSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	for k, v in props do
		(l :: any)[k] = v
	end
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = l
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = INK
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = l
	return l
end

-- Background: a little winter scene the snowball rolls through (Dev 2026-11-20: "can't
-- you make it like move"). Layers back to front: sky, drifting clouds, snowy mountains,
-- hills that slide by, the snow ground with piles the ball scoops up, the ball, puffs.
local HORIZON = 0.66 -- ground line, as a share of the screen height
local Z = {
	Sky = 1,
	Cloud = 2,
	Mountain = 3,
	Hill = 4,
	Pile = 5,
	Ground = 6,
	Trail = 7,
	Ball = 8,
	Puff = 9,
	Snow = 10,
	Ui = 12,
}

local bg = Instance.new("Frame")
bg.Name = "Background"
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.new(1, 1, 1)
bg.BorderSizePixel = 0
bg.ZIndex = Z.Sky
local sky = Instance.new("UIGradient")
sky.Color = ColorSequence.new(Color3.fromRGB(40, 140, 255), Color3.fromRGB(190, 232, 255))
sky.Rotation = 90
sky.Parent = bg
bg.Parent = gui

local function round(f: GuiObject)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = f
end

local function box(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	for k, v in props do
		(f :: any)[k] = v
	end
	f.Parent = props.Parent or bg
	return f
end

local function shade(f: GuiObject, top: Color3, bottom: Color3, rotation: number?)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = f
end

-- Clouds: three puffs each, drifting left and wrapping around.
local clouds: { { f: Frame, speed: number } } = {}
for i = 1, 4 do
	local c = box({
		Name = "Cloud",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.16, 0.09),
		Position = UDim2.fromScale((i - 1) * 0.3 + 0.05, 0.08 + (i % 2) * 0.12),
		ZIndex = Z.Cloud,
	})
	for _, b in { { 0, 0.35, 0.45, 0.65 }, { 0.25, 0, 0.45, 1 }, { 0.55, 0.25, 0.45, 0.75 } } do
		local puff = box({
			Size = UDim2.fromScale(b[3], b[4]),
			Position = UDim2.fromScale(b[1], b[2]),
			BackgroundTransparency = 0.1,
			ZIndex = Z.Cloud,
			Parent = c,
		})
		round(puff)
	end
	table.insert(clouds, { f = c, speed = 0.012 + (i % 3) * 0.006 })
end

-- Mountains: big diamonds standing on the horizon (the ground hides their lower half),
-- each with a snow cap diamond that shares its top corner.
for _, m in { { 0.12, 0.62 }, { 0.36, 0.86 }, { 0.62, 0.7 }, { 0.88, 0.92 } } do
	local h = m[2] * 0.6
	local peak = box({
		Name = "Mountain",
		Size = UDim2.fromScale(h, h),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(m[1], HORIZON),
		Rotation = 45,
		ZIndex = Z.Mountain,
	})
	peak.BackgroundColor3 = Color3.fromRGB(104, 152, 214)
	local cap = h * 0.42
	local capTop = HORIZON - h * 0.7071
	box({
		Name = "Cap",
		Size = UDim2.fromScale(cap, cap),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(m[1], capTop + cap * 0.7071),
		Rotation = 45,
		ZIndex = Z.Mountain,
	})
	-- A mountain-coloured diamond over the cap's lower half cuts a V into it, so the
	-- snow reads as a cap, not a second diamond.
	box({
		Name = "CapCut",
		Size = UDim2.fromScale(h, h),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(m[1], capTop + cap * 0.7071 * 1.3 + h * 0.7071),
		Rotation = 45,
		BackgroundColor3 = Color3.fromRGB(104, 152, 214),
		ZIndex = Z.Mountain,
	})
end

-- Snowy hills that slide by behind the ball, so the whole screen moves.
local hills: { Frame } = {}
for i = 0, 7 do
	local d = 0.2 + (i % 3) * 0.07
	local hill = box({
		Name = "Hill",
		Size = UDim2.fromScale(d, d),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(i / 6, HORIZON + 0.02),
		BackgroundColor3 = Color3.fromRGB(226, 240, 255),
		ZIndex = Z.Hill,
	})
	round(hill)
	table.insert(hills, hill)
end

local ground = box({
	Name = "Ground",
	Size = UDim2.fromScale(1, 1 - HORIZON),
	Position = UDim2.fromScale(0, HORIZON),
	ZIndex = Z.Ground,
})
shade(ground, Color3.new(1, 1, 1), Color3.fromRGB(200, 226, 250))
-- The packed-snow path the ball leaves behind it.
local trail = box({
	Name = "Trail",
	Size = UDim2.new(0, 0, 0, 10),
	Position = UDim2.fromScale(0, HORIZON),
	BackgroundColor3 = Color3.fromRGB(176, 214, 245),
	ZIndex = Z.Trail,
})

-- Falling snow.
local snow = box({
	Name = "Snow",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	ZIndex = Z.Snow,
})
local alive = true
task.spawn(function()
	while alive do
		local px = math.random(4, 10)
		local flake = box({
			Size = UDim2.fromOffset(px, px),
			Position = UDim2.new(math.random(), 0, 0, -12),
			BackgroundTransparency = math.random(0, 40) / 100,
			ZIndex = Z.Snow,
			Parent = snow,
		})
		round(flake)
		local t = math.random(40, 80) / 10
		TweenService:Create(flake, TweenInfo.new(t, Enum.EasingStyle.Linear), {
			Position = flake.Position + UDim2.new((math.random() - 0.5) * 0.15, 0, 1, 24),
		}):Play()
		task.delay(t, function()
			flake:Destroy()
		end)
		task.wait(0.06)
	end
end)

-- Everything else sits in a 1280x720 design frame that scales with the screen.
local stage = Instance.new("Frame")
stage.Name = "Stage"
stage.Size = UDim2.fromOffset(1280, 720)
stage.AnchorPoint = Vector2.new(0.5, 0.5)
stage.Position = UDim2.fromScale(0.5, 0.5)
stage.BackgroundTransparency = 1
stage.ZIndex = Z.Ui
stage.Parent = bg
local stageScale = Instance.new("UIScale")
stageScale.Parent = stage
local function fit()
	local size = gui.AbsoluteSize
	if size.X > 2 and size.Y > 2 then
		stageScale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 720), 0.45, 1.6)
	end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

-- The images come from Config.Images; it may take a moment to replicate.
local Images: { [string]: string } = {}
local Sounds: { [string]: any } = {}
local Anims: { [string]: string } = {}
local shared = ReplicatedStorage:WaitForChild("Shared", 10)
local config = shared and shared:WaitForChild("Config", 10)
if config then
	local function load(name: string): any
		local m = config:WaitForChild(name, 10)
		if m and m:IsA("ModuleScript") then
			local ok, v = pcall(require, m)
			if ok then
				return v
			end
		end
		return {}
	end
	Images = load("Images")
	Sounds = load("Sounds")
	Anims = load("Anims")
end

-- The star: the snowball rolls left to right with the progress, growing as it goes.
local BALL_X0, BALL_X1 = 0.07, 0.93
local ball = Instance.new("ImageLabel")
ball.Name = "Ball"
ball.BackgroundTransparency = 1
ball.Image = Images.Icon_Snowball or ""
ball.AnchorPoint = Vector2.new(0.5, 1)
ball.ZIndex = Z.Ball
ball.Parent = bg
local shadow = box({
	Name = "Shadow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(120, 160, 205),
	BackgroundTransparency = 0.45,
	ZIndex = Z.Trail,
})
round(shadow)

-- Snow piles along the ground; the ball scoops each one up as it reaches it.
local piles: { { f: Frame, x: number, taken: boolean } } = {}
for i = 1, 9 do
	local x = BALL_X0 + (BALL_X1 - BALL_X0) * (i / 10)
	local pile = box({
		Name = "Pile",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.07 + (i % 3) * 0.015, 0.07 + (i % 3) * 0.015),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Position = UDim2.fromScale(x, HORIZON),
		ZIndex = Z.Pile,
	})
	round(pile)
	stroke(pile, 2, true).Color = Color3.fromRGB(160, 200, 240)
	table.insert(piles, { f = pile, x = x, taken = false })
end

local title = label({
	Name = "Title",
	Size = UDim2.fromOffset(1000, 110),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, -230),
	Text = "ROLL THE SNOWBALL",
}, 96)
local ts = title:FindFirstChildOfClass("UIStroke") :: UIStroke
ts.Thickness = 6
title.Parent = stage

-- The bar: dark well, black outline, blue fill with a lighter top and a darker lip.
local well = Instance.new("Frame")
well.Name = "Bar"
well.Size = UDim2.fromOffset(620, 40)
well.AnchorPoint = Vector2.new(0.5, 0.5)
well.Position = UDim2.new(0.5, 0, 0.5, 262)
well.BackgroundColor3 = Color3.fromRGB(46, 51, 62)
well.BorderSizePixel = 0
stroke(well, 4)
well.Parent = stage
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(0, 190, 255)
fill.BorderSizePixel = 0
local shine = Instance.new("UIGradient")
shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 198, 210))
shine.Rotation = 90
shine.Parent = fill
local lip = Instance.new("Frame")
lip.Size = UDim2.new(1, 0, 0, 7)
lip.AnchorPoint = Vector2.new(0, 1)
lip.Position = UDim2.fromScale(0, 1)
lip.BackgroundColor3 = Color3.fromRGB(0, 118, 158)
lip.BorderSizePixel = 0
lip.Parent = fill
fill.Parent = well
local percent = label({
	Name = "Percent",
	Size = UDim2.new(1, 0, 1, -6),
	Position = UDim2.fromOffset(0, 3),
	Text = "0%",
	ZIndex = 4,
}, 28)
percent.Parent = well

local skip = Instance.new("TextButton")
skip.Name = "Skip"
skip.Text = ""
skip.AutoButtonColor = true
skip.Size = UDim2.fromOffset(200, 60)
skip.AnchorPoint = Vector2.new(0, 0.5)
skip.Position = UDim2.new(0.5, 340, 0.5, 262)
skip.BackgroundColor3 = Color3.fromRGB(90, 215, 20)
skip.BorderSizePixel = 0
skip.Visible = false
stroke(skip, 3)
local skipShine = shine:Clone()
skipShine.Parent = skip
label({ Size = UDim2.new(1, -16, 1, -10), Position = UDim2.fromOffset(8, 5), Text = "PLAY", ZIndex = 2 }, 34).Parent =
	skip
skip.Parent = stage

for _, d in stage:GetDescendants() do
	if d:IsA("GuiObject") then
		d.ZIndex += Z.Ui
	end
end
gui.Parent = playerGui
fit()

-- What to preload: every id string in the configs + the server-made model folders.
local items: { any } = {}
local seen: { [string]: boolean } = {}
local function addId(id: any)
	if type(id) == "string" and string.find(id, "rbxassetid://") and not seen[id] then
		seen[id] = true
		table.insert(items, id)
	end
end
for _, id in Images do
	addId(id)
end
for _, s in Sounds do
	addId(if type(s) == "table" then s.Id else s)
end
for _, id in Anims do
	if type(id) == "string" and not seen[id] then
		seen[id] = true
		local a = Instance.new("Animation")
		a.AnimationId = id
		table.insert(items, a)
	end
end
for _, name in { "Assets", "EggModels" } do
	local folder = ReplicatedStorage:WaitForChild(name, 4)
	if folder then
		for _, d in folder:GetDescendants() do
			if d:IsA("MeshPart") or d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
				table.insert(items, d)
			end
		end
	end
end

local started = os.clock()
local done = 0
local skipped = false
skip.Activated:Connect(function()
	skipped = true
end)

local function show(p: number)
	p = math.clamp(p, 0, 1)
	fill.Size = UDim2.fromScale(p, 1)
	percent.Text = `{math.floor(p * 100 + 0.5)}%`
end

-- Preload in the background; the bar follows.
local finished = false
task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local i = 1
	while i <= #items and not skipped do
		local batch = table.move(items, i, math.min(i + BATCH - 1, #items), 1, {})
		pcall(function()
			ContentProvider:PreloadAsync(batch)
		end)
		done += #batch
		i += BATCH
	end
	finished = true
end)

-- Scene animation, one frame: dt seconds passed, p = shown progress (0..1).
local shownP = 0
local spin = 0
local bump = 0
local lastX: number? = nil
local puffClock = 0
-- Puffs are placed at (xs, HORIZON) in screen scale plus a pixel offset (x, y).
local function puff(xs: number, x: number, y: number, size: number, dx: number, dy: number, life: number)
	local f = box({
		Name = "Puff",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.new(xs, x, HORIZON, y),
		BackgroundTransparency = 0.1,
		ZIndex = Z.Puff,
	})
	round(f)
	TweenService:Create(f, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(xs, x + dx, HORIZON, y + dy),
		Size = UDim2.fromOffset(size * 0.3, size * 0.3),
		BackgroundTransparency = 1,
	}):Play()
	task.delay(life, function()
		f:Destroy()
	end)
end

local function frame(t: number, dt: number, target: number)
	local screen = gui.AbsoluteSize
	local k = stageScale.Scale
	-- Ease toward the real progress so the ball never jumps.
	shownP += (target - shownP) * math.min(1, dt * 6)
	-- Positions are screen scale (xs, HORIZON) plus pixels, so the ball always sits on
	-- the ground whatever the screen or safe-area size.
	local xs = BALL_X0 + (BALL_X1 - BALL_X0) * shownP
	local x = xs * screen.X
	bump = math.max(0, bump - dt * 3)
	local d = (70 + 170 * shownP) * k * (1 + bump * 0.18)
	-- Rolling: turn by the distance covered, plus a slow idle roll so it never stands still.
	local moved = if lastX then x - lastX else 0
	lastX = x
	spin += math.deg(moved / math.max(d / 2, 1)) + dt * 40
	local hop = math.abs(math.sin(t * 7)) * 3 * k
	ball.Size = UDim2.fromOffset(d, d * (1 - bump * 0.12))
	ball.Position = UDim2.new(xs, 0, HORIZON, d * 0.06 - hop)
	ball.Rotation = spin
	shadow.Size = UDim2.fromOffset(d * 0.9, d * 0.16)
	shadow.Position = UDim2.new(xs, 0, HORIZON, d * 0.03)
	trail.Position = UDim2.new(BALL_X0, 0, HORIZON, -2)
	trail.Size = UDim2.new(xs - BALL_X0, 0, 0, math.max(6, d * 0.12))
	-- Snow kicked up behind the ball.
	puffClock -= dt
	if puffClock <= 0 then
		puffClock = 0.07
		local s = (8 + math.random() * 10) * k
		puff(xs, -d * 0.35, -4, s, -(30 + math.random() * 40) * k, -(10 + math.random() * 30) * k, 0.6)
	end
	-- Scoop up piles the ball reaches: they fly into it and it squashes a little.
	for _, pile in piles do
		if not pile.taken and x + d * 0.4 >= pile.x * screen.X then
			pile.taken = true
			bump = 1
			TweenService:Create(pile.f, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Position = UDim2.new(xs, 0, HORIZON, -d / 2),
				Size = UDim2.fromScale(0, 0),
			}):Play()
			for i = 1, 7 do
				local a = math.rad(-160 + i * 20)
				puff(
					xs,
					d * 0.3,
					-d * 0.3,
					(10 + math.random() * 8) * k,
					math.cos(a) * 70 * k,
					math.sin(a) * 70 * k,
					0.5
				)
			end
		end
	end
	-- Hills slide left slowly and wrap; clouds drift.
	for i, hill in hills do
		local hx = ((i - 1) / 6 - t * 0.02) % (8 / 6) - 1 / 6
		hill.Position = UDim2.fromScale(hx, HORIZON + 0.02)
	end
	for _, c in clouds do
		local cx = c.f.Position.X.Scale - c.speed * dt
		if cx < -0.2 then
			cx = 1.05
		end
		c.f.Position = UDim2.fromScale(cx, c.f.Position.Y.Scale)
	end
	-- The title bobs and tilts.
	title.Rotation = math.sin(t * 1.6) * 2
	title.Position = UDim2.new(0.5, 0, 0.5, -230 + math.sin(t * 2.4) * 6)
end

local last = os.clock()
while true do
	local now = os.clock()
	local t = now - started
	local dt = math.min(now - last, 0.1)
	last = now
	-- The bar never runs ahead of the work, and fills smoothly at the end.
	local p = if #items > 0 then done / #items else 1
	local shown = if finished then math.min(1, t / MIN_SECONDS) else math.min(p, 0.97)
	show(shown)
	frame(t, dt, shown)
	if t > SKIP_AFTER and not finished then
		skip.Visible = true
	end
	if (finished and t >= MIN_SECONDS and shownP > 0.97) or skipped or t > MAX_SECONDS then
		break
	end
	task.wait()
end
show(1)
alive = false

-- Fade out.
local fade = TweenInfo.new(0.45)
TweenService:Create(bg, fade, { BackgroundTransparency = 1 }):Play()
for _, d in gui:GetDescendants() do
	if d:IsA("TextLabel") then
		TweenService:Create(d, fade, { TextTransparency = 1 }):Play()
	elseif d:IsA("ImageLabel") then
		TweenService:Create(d, fade, { ImageTransparency = 1 }):Play()
	elseif d:IsA("UIStroke") then
		TweenService:Create(d, fade, { Transparency = 1 }):Play()
	elseif d:IsA("Frame") or d:IsA("TextButton") then
		TweenService:Create(d, fade, { BackgroundTransparency = 1 }):Play()
	end
end
task.wait(0.5)
gui:Destroy()
