--!strict
-- UI helpers. Every element is made here so the whole game shares one look, copied from
-- Steal an Egg / Throw Food For Animals (Dev 2026-11-20, reference-study.md): a round
-- cartoon font with thick dark outlines, rounded gradient tiles with the word UNDER the
-- tile, numbers with no panel, windows with a bright gradient header and a red X.
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
	Ink = Color3.fromRGB(22, 20, 38),
	Panel = Color3.fromRGB(30, 38, 78),
	PanelDark = Color3.fromRGB(20, 24, 54),
	Header = Color3.fromRGB(196, 60, 230),
	HeaderDark = Color3.fromRGB(120, 50, 220),
	Blue = Color3.fromRGB(60, 170, 255),
	Orange = Color3.fromRGB(255, 150, 40),
	Snow = Color3.fromRGB(240, 247, 255),
	Ice = Color3.fromRGB(110, 200, 255),
	Green = Color3.fromRGB(70, 205, 95),
	Yellow = Color3.fromRGB(255, 205, 60),
	Red = Color3.fromRGB(235, 70, 70),
	Gold = Color3.fromRGB(255, 200, 40),
	Power = Color3.fromRGB(255, 120, 60),
	Robux = Color3.fromRGB(40, 190, 90),
}

local FONT = Font.fromEnum(Enum.Font.FredokaOne)
local FONT_BLACK = Font.fromEnum(Enum.Font.FredokaOne)
local OUTLINE = Color3.fromRGB(22, 20, 38)
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
	stroke.Thickness = 2.5
	stroke.Color = OUTLINE
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = l
	return l
end

-- Rounded corners (px).
function Ui.corner(parent: GuiObject, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
	return c
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
	Ui.corner(b, 12)
	Ui.gradient(b, b.BackgroundColor3)
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

-- One small toast pill near the top (Steal an Egg's green success toast). A new toast
-- replaces the old one (Dev 2026-11-20: stacked toasts covered the windows).
local toastGui: ScreenGui? = nil
local toastSerial = 0
function Ui.toast(text: string, kind: string?)
	local gui = toastGui or Ui.screen("Toasts", 50)
	toastGui = gui
	local color = if kind == "Bad" then Ui.Colors.Red elseif kind == "Info" then Ui.Colors.Blue else Ui.Colors.Green
	local item = gui:FindFirstChild("Toast") :: Frame?
	if not item then
		local f = Ui.frame({
			Name = "Toast",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 40),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 78),
			Visible = false,
		})
		Ui.corner(f, 20)
		Ui.stroke(f, 3)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 18)
		pad.PaddingRight = UDim.new(0, 18)
		pad.Parent = f
		local l = Ui.label({
			Name = "Text",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 30),
			Position = UDim2.fromOffset(0, 5),
			TextScaled = false,
			TextSize = 24,
			Text = "",
		})
		l.Parent = f
		Ui.autoScale(f)
		f.Parent = gui
		item = f
	end
	local toast = item :: Frame
	toast.BackgroundColor3 = color
	local grad = toast:FindFirstChildOfClass("UIGradient")
	if not grad then
		Ui.gradient(toast, color)
	end
	local label = toast:FindFirstChild("Text") :: TextLabel
	label.Text = text
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

-- A centred window sized to its content (Steal an Egg chrome): a bright magenta/purple
-- gradient header with the white title on the left, a red rounded X, a dark navy body.
function Ui.window(gui: ScreenGui, name: string, title: string, size: Vector2): (Frame, Frame)
	local window = Ui.frame({
		Name = name,
		Size = UDim2.fromOffset(size.X, size.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Ui.Colors.PanelDark,
		Visible = false,
		ZIndex = 20,
	})
	Ui.corner(window, 16)
	Ui.stroke(window, 4)
	Ui.autoScale(window)
	local header = Ui.frame({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 21,
	})
	Ui.corner(header, 16)
	local hg = Instance.new("UIGradient")
	hg.Color = ColorSequence.new(Ui.Colors.Header, Ui.Colors.HeaderDark)
	hg.Parent = header
	-- Square off the header's bottom corners.
	local foot = Ui.frame({
		Name = "Foot",
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -16),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 21,
	})
	local fg = hg:Clone()
	fg.Parent = foot
	foot.Parent = header
	-- Diagonal sheen stripes.
	for k = 0, 3 do
		local stripe = Ui.frame({
			Name = "Sheen" .. k,
			Size = UDim2.fromOffset(18, 90),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.55 + k * 0.09, 0, 0.5, 0),
			Rotation = 30,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.88,
			ZIndex = 22,
		})
		stripe.Parent = header
	end
	header.ClipsDescendants = true
	header.Parent = window
	local t = Ui.label({
		Name = "Title",
		Size = UDim2.new(1, -90, 1, -14),
		Position = UDim2.fromOffset(18, 7),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
	})
	t.Parent = header
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = ""
	close.AutoButtonColor = true
	close.BorderSizePixel = 0
	close.BackgroundColor3 = Ui.Colors.Red
	close.Size = UDim2.fromOffset(46, 46)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.ZIndex = 24
	Ui.corner(close, 10)
	Ui.gradient(close, Ui.Colors.Red)
	Ui.stroke(close, 3)
	Ui.label({
		Name = "Label",
		Size = UDim2.new(1, -12, 1, -12),
		Position = UDim2.fromOffset(6, 6),
		Text = "X",
		ZIndex = 25,
	}).Parent =
		close
	close.Activated:Connect(function()
		Ui.sound("Click")
		Ui.closeWindow(window)
	end)
	close.Parent = window
	local body = Ui.frame({
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 1, -68),
		Position = UDim2.fromOffset(12, 62),
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

-- A vertical gradient: full colour on top, darker at the bottom (the chunky toy look).
-- It multiplies the background, so changing BackgroundColor3 later keeps working.
function Ui.gradient(parent: GuiObject, _color: Color3?)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(175, 175, 185))
	g.Rotation = 90
	g.Parent = parent
	return g
end

-- Round red badge with a count (hidden at 0).
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
		Ui.corner(nb, 13)
		Ui.stroke(nb, 2)
		nb.Parent = parent
		b = nb
	end
	local bb = b :: TextLabel
	bb.Visible = count > 0
	bb.Text = if count > 9 then "9+" else tostring(count)
end

local function press(b: GuiButton, onClick: () -> ())
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
end

-- A rounded icon tile (Steal an Egg rail): the icon fills the tile, one short outlined word
-- sits UNDER the tile (outside it), so a grid cell is size wide and size + 20 tall.
function Ui.tile(name: string, icon: string, word: string, color: Color3, onClick: () -> (), size: number?): TextButton
	local s = size or 64
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = color
	b.Size = UDim2.fromOffset(s, s)
	Ui.corner(b, math.floor(s * 0.22))
	Ui.gradient(b, color)
	Ui.stroke(b, 3)
	Ui.icon(icon, {
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		ZIndex = 2,
	}).Parent = b
	local l = Ui.label({
		Name = "Label",
		Size = UDim2.new(1, 24, 0, math.max(18, math.floor(s * 0.3))),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -6),
		Text = word,
		ZIndex = 3,
	})
	l.Parent = b
	press(b, onClick)
	return b
end

-- A number with no panel (bottom-left Power / cash): icon, then a big outlined number.
function Ui.stat(name: string, icon: string, color: Color3, width: number?): (Frame, TextLabel)
	local f = Ui.frame({ Name = name, Size = UDim2.fromOffset(width or 240, 50), BackgroundTransparency = 1 })
	Ui.icon(icon, { Size = UDim2.fromOffset(50, 50), ZIndex = 2 }).Parent = f
	local value = Ui.label({
		Name = "Value",
		Size = UDim2.new(1, -58, 0, 42),
		Position = UDim2.fromOffset(56, 4),
		Text = "0",
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	local st = value:FindFirstChildOfClass("UIStroke")
	if st then
		st.Thickness = 3
	end
	value.Parent = f
	return f, value
end

-- A big rounded pill button (bottom centre ROLL / STOP): icon on the left, one word.
function Ui.bigButton(
	name: string,
	icon: string?,
	word: string,
	color: Color3,
	onClick: () -> (),
	size: Vector2?
): TextButton
	local sz = size or Vector2.new(230, 78)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = color
	b.Size = UDim2.fromOffset(sz.X, sz.Y)
	Ui.corner(b, math.floor(sz.Y / 2))
	Ui.gradient(b, color)
	Ui.stroke(b, 4)
	local iconSize = sz.Y + 14
	if icon then
		Ui.icon(icon, {
			Size = UDim2.fromOffset(iconSize, iconSize),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, sz.Y * 0.42, 0.5, -4),
			ZIndex = 3,
		}).Parent =
			b
	end
	local left = if icon then math.floor(sz.Y * 0.95) else 14
	Ui.label({
		Name = "Label",
		Size = UDim2.new(1, -left - 14, 0, sz.Y * 0.62),
		Position = UDim2.new(0, left, 0.5, -sz.Y * 0.31),
		Text = word,
		ZIndex = 3,
	}).Parent =
		b
	press(b, onClick)
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
