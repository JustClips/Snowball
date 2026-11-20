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

local ball = Instance.new("ImageLabel")
ball.Name = "Ball"
ball.BackgroundTransparency = 1
ball.Image = Images.Icon_Snowball or ""
ball.Size = UDim2.fromOffset(200, 200)
ball.AnchorPoint = Vector2.new(0.5, 0.5)
ball.Position = UDim2.new(0.5, 0, 0.5, -130)
ball.Parent = stage

local title = label({
	Name = "Title",
	Size = UDim2.fromOffset(1000, 110),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 40),
	Text = "ROLL THE SNOWBALL",
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
	ball.Rotation = t * 90
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
