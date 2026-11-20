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

-- Background: sky gradient.
local bg = Instance.new("Frame")
bg.Name = "Background"
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.new(1, 1, 1)
bg.BorderSizePixel = 0
local sky = Instance.new("UIGradient")
sky.Color = ColorSequence.new(Color3.fromRGB(40, 140, 255), Color3.fromRGB(175, 225, 255))
sky.Rotation = 90
sky.Parent = bg
bg.Parent = gui

-- Falling snow.
local snow = Instance.new("Frame")
snow.Name = "Snow"
snow.Size = UDim2.fromScale(1, 1)
snow.BackgroundTransparency = 1
snow.ClipsDescendants = true
snow.Parent = bg
local alive = true
task.spawn(function()
	while alive do
		local flake = Instance.new("Frame")
		local px = math.random(4, 10)
		flake.Size = UDim2.fromOffset(px, px)
		flake.Position = UDim2.new(math.random(), 0, 0, -12)
		flake.BackgroundColor3 = Color3.new(1, 1, 1)
		flake.BackgroundTransparency = math.random(0, 40) / 100
		flake.BorderSizePixel = 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = flake
		flake.Parent = snow
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

-- The hero (Dev 2026-11-20: "why does the loading screen snowball just rotate"): a snowy
-- hill across the screen, and the snowball rolls down it, growing as it goes, hopping
-- over two bumps and kicking up snow puffs, then rolls off and comes round again.
local SLOPE_A = Vector2.new(-160, 70) -- hill top edge, stage pixels
local SLOPE_B = Vector2.new(1440, 330)
local slopeDir = (SLOPE_B - SLOPE_A).Unit
local slopeAngle = math.deg(math.atan2(slopeDir.Y, slopeDir.X))
local function hillY(x: number): number
	return SLOPE_A.Y + (x - SLOPE_A.X) * (SLOPE_B.Y - SLOPE_A.Y) / (SLOPE_B.X - SLOPE_A.X)
end
local hill = Instance.new("Frame")
hill.Name = "Hill"
hill.Size = UDim2.fromOffset(2400, 1400)
hill.AnchorPoint = Vector2.new(0.5, 0)
local mid = (SLOPE_A + SLOPE_B) / 2
hill.Position = UDim2.fromOffset(mid.X, mid.Y)
hill.Rotation = slopeAngle
hill.BackgroundColor3 = Color3.new(1, 1, 1)
hill.BorderSizePixel = 0
local hillShade = Instance.new("UIGradient")
hillShade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 222, 250))
hillShade.Rotation = 90
hillShade.Parent = hill
local edge = Instance.new("UIStroke")
edge.Thickness = 5
edge.Color = Color3.fromRGB(120, 175, 225)
edge.Parent = hill
hill.Parent = stage
-- Two little snow bumps on the hill the ball hops over.
local BUMPS = { 430, 880 }
for _, bx in BUMPS do
	local bump = Instance.new("Frame")
	bump.Size = UDim2.fromOffset(150, 60)
	bump.AnchorPoint = Vector2.new(0.5, 0.75)
	bump.Position = UDim2.fromOffset(bx, hillY(bx) + 6)
	bump.Rotation = slopeAngle
	bump.BackgroundColor3 = Color3.new(1, 1, 1)
	bump.BorderSizePixel = 0
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = bump
	bump.Parent = stage
end

local ball = Instance.new("ImageLabel")
ball.Name = "Ball"
ball.BackgroundTransparency = 1
ball.Image = Images.Icon_Snowball or ""
ball.Size = UDim2.fromOffset(80, 80)
ball.AnchorPoint = Vector2.new(0.5, 0.5)
ball.ZIndex = 5
ball.Parent = stage
local shadow = Instance.new("Frame")
shadow.Name = "Shadow"
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.BackgroundColor3 = Color3.fromRGB(120, 160, 210)
shadow.BackgroundTransparency = 0.5
shadow.BorderSizePixel = 0
shadow.Rotation = slopeAngle
shadow.ZIndex = 4
local sc = Instance.new("UICorner")
sc.CornerRadius = UDim.new(0.5, 0)
sc.Parent = shadow
shadow.Parent = stage

local hero = { x = SLOPE_A.X, spin = 0, puff = 0, wait = 0 }
local function puff(at: Vector2, size: number)
	local p = Instance.new("Frame")
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Size = UDim2.fromOffset(size, size)
	p.Position = UDim2.fromOffset(at.X, at.Y)
	p.BackgroundColor3 = Color3.new(1, 1, 1)
	p.BorderSizePixel = 0
	p.ZIndex = 4
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = p
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = Color3.fromRGB(170, 205, 240)
	st.Parent = p
	p.Parent = stage
	local drift = UDim2.fromOffset(at.X - math.random(20, 60), at.Y - math.random(25, 60))
	local t = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService
		:Create(p, t, { Position = drift, Size = UDim2.fromOffset(size * 1.8, size * 1.8), BackgroundTransparency = 1 })
		:Play()
	TweenService:Create(st, t, { Transparency = 1 }):Play()
	task.delay(0.75, function()
		p:Destroy()
	end)
end

local function stepHero(dt: number)
	if hero.wait > 0 then
		hero.wait -= dt
		ball.Visible = false
		shadow.Visible = false
		return
	end
	ball.Visible = true
	shadow.Visible = true
	local span = SLOPE_B.X - SLOPE_A.X
	local k = math.clamp((hero.x - SLOPE_A.X) / span, 0, 1)
	local r = 34 + 96 * k -- grows as it rolls
	local speed = 260 + 420 * k -- and speeds up
	hero.x += speed * dt
	hero.spin += speed * dt / r * 57.3
	-- Hop over the bumps.
	local hop = 0
	for _, bx in BUMPS do
		local u = (hero.x - (bx - 70)) / 190
		if u > 0 and u < 1 then
			hop = math.max(hop, math.sin(u * math.pi) * 70)
		end
	end
	local ground = hillY(hero.x)
	local squash = if hop < 4 then 1 + 0.06 * math.abs(math.sin(hero.spin / 57.3 * 2)) else 1
	ball.Size = UDim2.fromOffset(r * 2 * squash, r * 2 / squash)
	ball.Position = UDim2.fromOffset(hero.x, ground - r / squash - hop)
	ball.Rotation = hero.spin
	shadow.Size = UDim2.fromOffset(r * 1.6 * (1 - hop / 200), r * 0.35)
	shadow.Position = UDim2.fromOffset(hero.x, ground + 2)
	-- Snow kicked up behind it while it touches the ground.
	hero.puff -= dt
	if hop < 6 and hero.puff <= 0 then
		hero.puff = 0.05
		puff(Vector2.new(hero.x - r * 0.7, ground - r * 0.25), r * (0.35 + math.random() * 0.25))
	end
	if hero.x - r > 1300 then
		hero.x = SLOPE_A.X
		hero.spin = 0
		hero.wait = 0.5
	end
end

local title = label({
	Name = "Title",
	Size = UDim2.fromOffset(1000, 110),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 70),
	Text = "ROLL THE SNOWBALL",
	ZIndex = 6,
}, 96)
local ts = title:FindFirstChildOfClass("UIStroke") :: UIStroke
ts.Thickness = 6
title.Parent = stage

-- The bar: dark well, black outline, blue fill with a lighter top and a darker lip, the
-- snowball riding the end of the fill.
local well = Instance.new("Frame")
well.Name = "Bar"
well.Size = UDim2.fromOffset(620, 40)
well.AnchorPoint = Vector2.new(0.5, 0.5)
well.Position = UDim2.new(0.5, 0, 0.5, 160)
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
local rider = Instance.new("ImageLabel")
rider.Name = "Rider"
rider.BackgroundTransparency = 1
rider.Image = Images.Icon_Snowball or ""
rider.Size = UDim2.fromOffset(64, 64)
rider.AnchorPoint = Vector2.new(0.5, 0.5)
rider.Position = UDim2.fromScale(0, 0.5)
rider.ZIndex = 3
rider.Parent = well
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
skip.AnchorPoint = Vector2.new(0.5, 0)
skip.Position = UDim2.new(0.5, 0, 0.5, 210)
skip.BackgroundColor3 = Color3.fromRGB(90, 215, 20)
skip.BorderSizePixel = 0
skip.Visible = false
stroke(skip, 3)
local skipShine = shine:Clone()
skipShine.Parent = skip
label({ Size = UDim2.new(1, -16, 1, -10), Position = UDim2.fromOffset(8, 5), Text = "PLAY", ZIndex = 2 }, 34).Parent =
	skip
skip.Parent = stage

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
local lastFrame: number? = nil
local done = 0
local skipped = false
skip.Activated:Connect(function()
	skipped = true
end)

local function show(p: number)
	p = math.clamp(p, 0, 1)
	fill.Size = UDim2.fromScale(p, 1)
	rider.Position = UDim2.fromScale(p, 0.5)
	rider.Rotation = p * 1080
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

while true do
	local t = os.clock() - started
	stepHero(math.min(0.1, os.clock() - (lastFrame or os.clock())))
	lastFrame = os.clock()
	-- The bar never runs ahead of the work, and fills smoothly at the end.
	local p = if #items > 0 then done / #items else 1
	show(if finished then math.min(1, t / MIN_SECONDS) else math.min(p, 0.97))
	if t > SKIP_AFTER and not finished then
		skip.Visible = true
	end
	if (finished and t >= MIN_SECONDS) or skipped or t > MAX_SECONDS then
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
