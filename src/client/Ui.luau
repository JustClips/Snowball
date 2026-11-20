--!strict
-- UI helpers. Every placeholder element is made here so the look follows the project UI
-- rules (Montserrat, solid button backgrounds, NO rounded corners, mobile first) and so the
-- ForgeUI art can replace it in one place later (controllers find elements by name).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Images = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Images"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local Ui = {}

Ui.ROBUX = utf8.char(0xE002)
Ui.Colors = {
	Ink = Color3.fromRGB(20, 32, 58),
	Panel = Color3.fromRGB(28, 46, 84),
	PanelDark = Color3.fromRGB(16, 27, 52),
	Snow = Color3.fromRGB(240, 247, 255),
	Ice = Color3.fromRGB(110, 200, 255),
	Green = Color3.fromRGB(70, 205, 95),
	Yellow = Color3.fromRGB(255, 205, 60),
	Red = Color3.fromRGB(235, 70, 70),
	Gold = Color3.fromRGB(255, 200, 40),
	Power = Color3.fromRGB(255, 120, 60),
	Robux = Color3.fromRGB(40, 190, 90),
}

local FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
local FONT_BLACK = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
Ui.Font = FONT
Ui.FontBlack = FONT_BLACK

-- A ScreenGui in PlayerGui (made once, kept across respawns).
function Ui.screen(name: string, order: number?): ScreenGui
	local gui = playerGui:FindFirstChild(name) :: ScreenGui?
	if gui then
		return gui
	end
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	g.DisplayOrder = order or 0
	g.Parent = playerGui
	return g
end

function Ui.frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Ui.Colors.Panel
	for k, v in props do
		(f :: any)[k] = v
	end
	return f
end

function Ui.stroke(parent: Instance, thickness: number?, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 3
	s.Color = color or Ui.Colors.Ink
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Ui.label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = FONT_BLACK
	l.TextColor3 = Ui.Colors.Snow
	l.TextScaled = true
	l.BorderSizePixel = 0
	for k, v in props do
		(l :: any)[k] = v
	end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Ui.Colors.Ink
	stroke.Parent = l
	return l
end

-- A solid button with a child "Label" (text) and a dark outline. No rounded corners.
function Ui.button(props: { [string]: any }, text: string, onClick: (() -> ())?): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.Text = ""
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Ui.Colors.Ice
	for k, v in props do
		(b :: any)[k] = v
	end
	Ui.stroke(b, 3)
	local l =
		Ui.label({ Name = "Label", Size = UDim2.new(1, -10, 1, -8), Position = UDim2.fromOffset(5, 4), Text = text })
	l.Parent = b
	local scale = Instance.new("UIScale")
	scale.Parent = b
	if onClick then
		b.Activated:Connect(function()
			Ui.sound("Click")
			scale.Scale = 0.92
			TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			onClick()
		end)
	end
	return b
end

function Ui.setText(button: Instance, text: string)
	local l = button:FindFirstChild("Label")
	if l and l:IsA("TextLabel") then
		l.Text = text
	elseif button:IsA("TextLabel") or button:IsA("TextButton") then
		button.Text = text
	end
end

-- Sound effects (Config/Sounds). Ui.sound plays a one-shot; Ui.loop starts/stops a loop.
local SFX = require(ReplicatedStorage:WaitForChild("Shared").Config.Sounds)
local cache: { [string]: Sound } = {}
local loops: { [string]: Sound } = {}
function Ui.loop(name: string, on: boolean, speed: number?)
	local def = SFX[name]
	if not def then
		return
	end
	local snd = loops[name]
	if not snd then
		snd = Instance.new("Sound")
		snd.SoundId = def.Id
		snd.Volume = def.Volume
		snd.Looped = true
		snd.Parent = SoundService
		loops[name] = snd
	end
	local sound = snd :: Sound
	sound.PlaybackSpeed = speed or 1
	if on and not sound.IsPlaying then
		sound:Play()
	elseif not on and sound.IsPlaying then
		sound:Stop()
	end
end

function Ui.sound(name: string, speed: number?)
	local def = SFX[name]
	if not def then
		return
	end
	local s = cache[name]
	if not s then
		local snd = Instance.new("Sound")
		snd.SoundId = def.Id
		snd.Volume = def.Volume
		snd.Parent = SoundService
		cache[name] = snd
		s = snd
	end
	local sound = s :: Sound
	sound.PlaybackSpeed = speed or 1
	SoundService:PlayLocalSound(sound)
end

-- Short toast at the top of the screen.
local toastGui: ScreenGui? = nil
local toastSerial = 0
function Ui.toast(text: string, kind: string?)
	-- ONE small toast pill under the top status bar. A new toast replaces the old one
	-- (Dev 2026-11-20: stacked toasts covered the windows).
	local gui = toastGui or Ui.screen("Toasts", 50)
	toastGui = gui
	local color = if kind == "Bad" then Ui.Colors.Red elseif kind == "Info" then Ui.Colors.Ice else Ui.Colors.Green
	local item = gui:FindFirstChild("Toast") :: Frame?
	if not item then
		local f = Ui.frame({
			Name = "Toast",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 34),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 96),
			BackgroundColor3 = Ui.Colors.PanelDark,
			Visible = false,
		})
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 14)
		pad.PaddingRight = UDim.new(0, 14)
		pad.Parent = f
		Ui.stroke(f, 3, color)
		local l = Ui.label({
			Name = "Text",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 26),
			Position = UDim2.fromOffset(0, 4),
			TextScaled = false,
			TextSize = 20,
			Text = "",
		})
		l.Parent = f
		Ui.autoScale(f)
		f.Parent = gui
		item = f
	end
	local toast = item :: Frame
	local stroke = toast:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end
	local label = toast:FindFirstChild("Text") :: TextLabel
	label.Text = text
	label.TextColor3 = if kind == "Bad" then Color3.fromRGB(255, 150, 150) else Ui.Colors.Snow
	toast.Visible = true
	toastSerial += 1
	local mine = toastSerial
	task.delay(1.8, function()
		if toastSerial == mine then
			toast.Visible = false
		end
	end)
end

-- Phones get bigger touch targets.
function Ui.isPhone(): boolean
	local cam = Workspace.CurrentCamera
	return cam ~= nil and math.min(cam.ViewportSize.X, cam.ViewportSize.Y) < 500
end

function Ui.reducedMotion(): boolean
	return GuiService.ReducedMotionEnabled
end

-- A full-screen root frame with a UIScale that follows the screen size, so layouts made
-- for a 1280x720 screen fit phones (min 0.55) and big monitors (max 1.25).
function Ui.root(gui: ScreenGui): Frame
	local existing = gui:FindFirstChild("Root") :: Frame?
	if existing then
		return existing
	end
	local root = Ui.frame({ Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	root.Parent = gui
	return root
end

local scales: { UIScale } = {}
local function rescale()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local v = cam.ViewportSize
	local s = math.clamp(math.min(v.X / 1280, v.Y / 720) * 1.05, 0.55, 1.25)
	if Ui.isPhone() then
		s = math.max(s, 0.62)
	end
	for _, scale in scales do
		scale.Scale = s
	end
end

-- Adds a UIScale that follows the screen to a cluster (HUD corner, window...).
function Ui.autoScale(object: GuiObject)
	local scale = Instance.new("UIScale")
	scale.Parent = object
	table.insert(scales, scale)
	rescale()
end

task.spawn(function()
	local cam = Workspace.CurrentCamera
	while not cam do
		task.wait()
		cam = Workspace.CurrentCamera
	end
	(cam :: Camera):GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()
end)

-- One modal window open at a time.
local openWindow: GuiObject? = nil
function Ui.openWindow(window: GuiObject)
	if openWindow and openWindow ~= window then
		openWindow.Visible = false
	end
	openWindow = window
	window.Visible = true
end

function Ui.closeWindow(window: GuiObject)
	window.Visible = false
	if openWindow == window then
		openWindow = nil
	end
end

-- A centred window sized to its content: header with a title and a close button.
function Ui.window(gui: ScreenGui, name: string, title: string, size: Vector2): (Frame, Frame)
	local window = Ui.frame({
		Name = name,
		Size = UDim2.fromOffset(size.X, size.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Ui.Colors.Panel,
		Visible = false,
		ZIndex = 20,
	})
	Ui.stroke(window, 4)
	Ui.autoScale(window)
	local header = Ui.frame({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = Ui.Colors.PanelDark,
		ZIndex = 21,
	})
	header.Parent = window
	local t = Ui.label({
		Name = "Title",
		Size = UDim2.new(1, -80, 1, -12),
		Position = UDim2.fromOffset(14, 6),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
	})
	t.Parent = header
	local close = Ui.button(
		{
			Name = "Close",
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.new(1, -48, 0, 4),
			BackgroundColor3 = Ui.Colors.Red,
			ZIndex = 22,
		},
		"X",
		function()
			Ui.closeWindow(window)
		end
	)
	close.Parent = header
	local body = Ui.frame({
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 1, -64),
		Position = UDim2.fromOffset(12, 58),
		ZIndex = 21,
	})
	body.Parent = window
	window.Parent = gui
	return window, body
end

-------------------------------------------------------------------------- icon-first kit
-- Kids don't read (Dev, 2026-11-20; Tizzy playbook): buttons are big icons from the
-- Free Icon Pack (Config/Images), with at most one short word under them.

Ui.Images = Images

-- An icon image (name from Config/Images).
function Ui.icon(name: string, props: { [string]: any }?): ImageLabel
	local i = Instance.new("ImageLabel")
	i.Name = "Icon"
	i.BackgroundTransparency = 1
	i.Image = Images[name] or ""
	i.ScaleType = Enum.ScaleType.Fit
	for k, v in props or {} do
		(i :: any)[k] = v
	end
	return i
end

-- A vertical two-tone gradient: lighter top, base colour bottom (the chunky toy look).
function Ui.gradient(parent: GuiObject, color: Color3)
	local g = Instance.new("UIGradient")
	local h, sat, v = color:ToHSV()
	g.Color = ColorSequence.new(Color3.fromHSV(h, sat * 0.75, math.min(1, v * 1.18)), Color3.fromHSV(h, sat, v * 0.82))
	g.Rotation = 90
	g.Parent = parent
	return g
end

-- Red square badge with a count (hidden at 0).
function Ui.badge(parent: GuiObject, count: number)
	local b = parent:FindFirstChild("Badge") :: TextLabel?
	if not b then
		local nb = Ui.label({
			Name = "Badge",
			Size = UDim2.fromOffset(26, 26),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -4, 0, 4),
			BackgroundTransparency = 0,
			BackgroundColor3 = Ui.Colors.Red,
			Text = "",
			ZIndex = 8,
		})
		Ui.stroke(nb, 2)
		nb.Parent = parent
		b = nb
	end
	local bb = b :: TextLabel
	bb.Visible = count > 0
	bb.Text = if count > 9 then "9+" else tostring(count)
end

-- A square icon tile (left rail): big icon, one short word under it, solid gradient body.
function Ui.tile(name: string, icon: string, word: string, color: Color3, onClick: () -> (), size: number?): TextButton
	local s = size or 78
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = color
	b.Size = UDim2.fromOffset(s, s)
	Ui.gradient(b, color)
	Ui.stroke(b, 3)
	Ui.icon(icon, {
		Size = UDim2.new(1, -10, 1, -24),
		Position = UDim2.fromOffset(5, 3),
		ZIndex = 2,
	}).Parent =
		b
	local l = Ui.label({
		Name = "Label",
		Size = UDim2.new(1, -4, 0, 20),
		Position = UDim2.new(0, 2, 1, -22),
		Text = word,
		ZIndex = 3,
	})
	l.Parent = b
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.Activated:Connect(function()
		Ui.sound("Click")
		scale.Scale = 0.88
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		onClick()
	end)
	b.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.06 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	return b
end

-- A currency pill: icon hanging off the left, big outlined number, optional "+" button.
function Ui.pill(name: string, icon: string, color: Color3, width: number, onPlus: (() -> ())?): (Frame, TextLabel)
	local f = Ui.frame({ Name = name, Size = UDim2.fromOffset(width, 46), BackgroundColor3 = Ui.Colors.PanelDark })
	Ui.stroke(f, 3)
	local bar = Ui.frame({
		Name = "Bar",
		Size = UDim2.new(1, 0, 0, 6),
		Position = UDim2.new(0, 0, 1, -6),
		BackgroundColor3 = color,
	})
	bar.Parent = f
	Ui.icon(icon, {
		Size = UDim2.fromOffset(60, 60),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		ZIndex = 3,
	}).Parent =
		f
	local value = Ui.label({
		Name = "Value",
		Size = UDim2.new(1, if onPlus then -84 else -44, 1, -10),
		Position = UDim2.fromOffset(38, 4),
		Text = "0",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	value.Parent = f
	if onPlus then
		local plus = Instance.new("ImageButton")
		plus.Name = "Plus"
		plus.BackgroundColor3 = Ui.Colors.Green
		plus.BorderSizePixel = 0
		plus.Size = UDim2.fromOffset(38, 38)
		plus.Position = UDim2.new(1, -42, 0, 4)
		plus.Image = Images.Plus or ""
		Ui.stroke(plus, 2)
		plus.Activated:Connect(function()
			Ui.sound("Click")
			onPlus()
		end)
		plus.Parent = f
	end
	return f, value
end

return Ui
