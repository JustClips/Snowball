--!strict
-- UI kit: every element in the game is made here, so all screens share ONE look.
--
-- Style "snow stud" (UI polish pass 2026-11-20, from the two UI packs Dev sent: Essential
-- UI Pack + Ultra UI Pack; Dev: "we gonna do stud style", "rebuild all ui elements based
-- on those"):
--   * Montserrat Heavy everywhere (the packs use Gotham SSm = Montserrat), white text with
--     a thin black outline.
--   * square blocks: a bright fill with a lighter top (UIGradient), our stud overlay
--     (art/ui/Ui_Studs.png, see-through, so it works on any colour), a 3 px black outline
--     and a darker lip along the bottom edge.
--   * windows: a slate body with a black outline, a coloured stud header (icon + short
--     title on the left), a red X block filling the header's right end, a dim behind.
--   * HUD: stud tiles with the icon on top and ONE word inside; money as a big number.
--   * few words: icons first, one short word where a word is needed (kids don't read).
-- Screens should not pick their own fonts, strokes or corners; use these helpers.
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

-- Colour roles (bright like the packs). Old names are kept so every controller works.
Ui.Colors = {
	Ink = Color3.fromRGB(16, 18, 24), -- outlines, text on light
	Panel = Color3.fromRGB(86, 94, 108), -- window body (slate)
	PanelStud = Color3.fromRGB(96, 104, 118),
	PanelDark = Color3.fromRGB(46, 51, 62), -- wells, bars, slots
	Surface = Color3.fromRGB(240, 243, 248),
	Header = Color3.fromRGB(0, 170, 255), -- default window header (cyan)
	HeaderDark = Color3.fromRGB(0, 120, 220),
	Blue = Color3.fromRGB(0, 170, 255),
	Cyan = Color3.fromRGB(0, 205, 255),
	Orange = Color3.fromRGB(255, 140, 0),
	Snow = Color3.fromRGB(255, 255, 255), -- white text
	Sub = Color3.fromRGB(200, 207, 220), -- quiet text on the body
	Ice = Color3.fromRGB(120, 210, 255),
	Green = Color3.fromRGB(90, 215, 20), -- go / buy / claim / Robux buttons
	Lime = Color3.fromRGB(150, 235, 0),
	Yellow = Color3.fromRGB(255, 215, 0),
	Red = Color3.fromRGB(235, 30, 45), -- close, danger, can't afford
	Gold = Color3.fromRGB(255, 185, 0),
	Pink = Color3.fromRGB(255, 50, 145),
	Purple = Color3.fromRGB(160, 70, 255),
	Power = Color3.fromRGB(255, 120, 0),
	Robux = Color3.fromRGB(90, 215, 20),
	Gift = Color3.fromRGB(190, 70, 255),
	Muted = Color3.fromRGB(140, 146, 160), -- disabled / owned / claimed
	Dim = Color3.fromRGB(8, 10, 20),
}

local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"
local FONT = Font.new(MONTSERRAT, Enum.FontWeight.Bold)
local FONT_BLACK = Font.new(MONTSERRAT, Enum.FontWeight.Heavy)
local INK = Ui.Colors.Ink
Ui.Font = FONT
Ui.FontBlack = FONT_BLACK

-- The stud overlay (art/ui/Ui_Studs.png) and Sweep the World's white glow.
Ui.STUD = Images.Ui_Studs or "rbxassetid://117181516497135"
Ui.GLOW = "rbxassetid://139963628852518"

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

-- Dark outline around a panel or button.
function Ui.stroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 3
	s.Color = color or INK
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Miter
	s.Parent = parent
	return s
end

-- White text with a thin dark outline (Montserrat Heavy). TextScaled by default, never
-- bigger than 40 px so short words don't balloon in big boxes.
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
	stroke.Color = INK
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = l
	if l.TextScaled and not l:FindFirstChildOfClass("UITextSizeConstraint") then
		local c = Instance.new("UITextSizeConstraint")
		c.Name = "Fit"
		c.MaxTextSize = 40
		c.MinTextSize = 8
		c.Parent = l
	end
	return l
end

-- Caps a label's text size (the kit's labels fit their box up to this size).
function Ui.maxText(label: TextLabel, size: number)
	local c = label:FindFirstChildOfClass("UITextSizeConstraint")
	if not c then
		local n = Instance.new("UITextSizeConstraint")
		n.Name = "Fit"
		n.MinTextSize = 8
		n.Parent = label
		c = n
	end
	(c :: UITextSizeConstraint).MaxTextSize = size
end

-- Corners: the kit is square (Sweep). Kept for round things: badges, dots, glows.
function Ui.corner(parent: GuiObject, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 0)
	c.Parent = parent
	return c
end

-- A fully round shape (badges, dots).
function Ui.round(parent: GuiObject): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = parent
	return c
end

-- The stud overlay (see-through highlights and shades, so no tint is needed).
-- `tint` is kept for old callers and ignored; `transparency` fades the studs.
function Ui.studs(parent: GuiObject, _tint: Color3?, tile: number?, transparency: number?): ImageLabel
	local s = Instance.new("ImageLabel")
	s.Name = "Studs"
	s.BackgroundTransparency = 1
	s.Image = Ui.STUD
	s.ScaleType = Enum.ScaleType.Tile
	s.TileSize = UDim2.fromOffset(tile or 40, tile or 40)
	s.ImageTransparency = transparency or 0
	s.Size = UDim2.fromScale(1, 1)
	s.ZIndex = parent.ZIndex
	s.Parent = parent
	return s
end

-- Lighter top, slightly darker bottom. It multiplies the fill, so recolouring still works.
function Ui.gradient(parent: GuiObject, _color: Color3?): UIGradient
	local g = Instance.new("UIGradient")
	g.Name = "Shine"
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(232, 232, 236)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(196, 198, 210)),
	})
	g.Rotation = 90
	g.Parent = parent
	return g
end

local function darker(c: Color3, k: number): Color3
	return Color3.new(c.R * k, c.G * k, c.B * k)
end
Ui.darker = darker

-- Turns a frame/button into a block: lighter top (gradient), black outline, a darker lip
-- along the bottom. No texture on it (Dev 2026-11-20: buttons must be clean, no boxes). Ui.tint recolours it (fill + lip).
function Ui.block(object: GuiObject, color: Color3?, stroke: number?, lip: number?)
	if color then
		object.BackgroundColor3 = color
	end
	Ui.stroke(object, stroke or 3)
	Ui.gradient(object)
	local h = lip or 5
	if h > 0 then
		local l = Instance.new("Frame")
		l.Name = "Lip"
		l.BorderSizePixel = 0
		l.BackgroundColor3 = darker(object.BackgroundColor3, 0.62)
		l.Size = UDim2.new(1, 0, 0, h)
		l.AnchorPoint = Vector2.new(0, 1)
		l.Position = UDim2.fromScale(0, 1)
		l.ZIndex = object.ZIndex
		l.Parent = object
	end
end

-- Recolours a block (fill + its lip).
function Ui.tint(object: GuiObject, color: Color3)
	object.BackgroundColor3 = color
	local l = object:FindFirstChild("Lip") :: Frame?
	if l then
		l.BackgroundColor3 = darker(color, 0.62)
	end
end

-- Press feel: squash on tap, a small grow on hover (PC), click sound.
local function press(b: GuiButton, onClick: (() -> ())?)
	local scale = Instance.new("UIScale")
	scale.Name = "Press"
	scale.Parent = b
	b.Activated:Connect(function()
		Ui.sound("Click")
		if not Ui.reducedMotion() then
			scale.Scale = 0.9
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		if onClick then
			onClick()
		end
	end)
	b.MouseEnter:Connect(function()
		if not Ui.reducedMotion() then
			TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 1.05 }):Play()
		end
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 1 }):Play()
	end)
end
Ui.press = press

-- A raised stud button with a child "Label". Colour comes from props.BackgroundColor3.
function Ui.button(props: { [string]: any }, text: string, onClick: (() -> ())?): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Ui.Colors.Blue
	for k, v in props do
		(b :: any)[k] = v
	end
	Ui.block(b)
	local l = Ui.label({
		Name = "Label",
		Size = UDim2.new(1, -12, 1, -8),
		Position = UDim2.fromOffset(6, 4),
		Text = text,
		ZIndex = b.ZIndex + 1,
	})
	Ui.maxText(l, 30)
	l.Parent = b
	press(b, onClick)
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

-- The red X (same everywhere). Sits inside a header on the right.
function Ui.closeButton(onClick: () -> (), size: number?): TextButton
	local s = size or 52
	local b = Ui.button({
		Name = "Close",
		Size = UDim2.fromOffset(s + 4, s),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Ui.Colors.Red,
		ZIndex = 30,
	}, "X", onClick)
	Ui.maxText(b:FindFirstChild("Label") :: TextLabel, math.floor(s * 0.6))
	return b
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

-- One small toast near the top: a dark plate with a coloured edge and one short line.
-- A new toast replaces the old one (Dev 2026-11-20: stacked toasts covered the windows).
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
			BackgroundColor3 = Ui.Colors.PanelDark,
			BackgroundTransparency = 0.1,
			Visible = false,
		})
		Ui.stroke(f, 2)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 22)
		pad.PaddingRight = UDim.new(0, 16)
		pad.Parent = f
		local edge = Ui.frame({
			Name = "Edge",
			Size = UDim2.new(0, 6, 1, 0),
			Position = UDim2.fromOffset(-22, 0),
			BackgroundColor3 = color,
		})
		edge.Parent = f
		local l = Ui.label({
			Name = "Text",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 40),
			TextScaled = false,
			TextSize = 20,
			Text = "",
		})
		l.Parent = f
		local sc = Instance.new("UIScale")
		sc.Name = "Pop"
		sc.Parent = f
		Ui.autoScale(f)
		f.Parent = gui
		item = f
	end
	local toast = item :: Frame
	local edge = toast:FindFirstChild("Edge") :: Frame
	edge.BackgroundColor3 = color
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

-- ONE big word in the upper middle (PERFECT!, SMASH! x3...). A new word replaces the old
-- one; it pops in, holds, then fades out completely and hides.
local wordLabel: TextLabel? = nil
local wordScale: UIScale? = nil
local wordSerial = 0
function Ui.word(text: string, color: Color3, hold: number?, size: number?)
	if not wordLabel then
		local gui = Ui.screen("Words", 12)
		local holder = Ui.frame({
			Name = "Holder",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(640, 90),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.32),
		})
		Ui.autoScale(holder)
		holder.Parent = gui
		local l = Ui.label({
			Name = "Word",
			Size = UDim2.fromScale(1, 1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Text = "",
			Visible = false,
		})
		Ui.maxText(l, 72)
		local st = l:FindFirstChildOfClass("UIStroke")
		if st then
			st.Thickness = 3.5
		end
		local sc = Instance.new("UIScale")
		sc.Parent = l
		l.Parent = holder
		wordLabel = l
		wordScale = sc
	end
	local label = wordLabel :: TextLabel
	local scale = wordScale :: UIScale
	local stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
	wordSerial += 1
	local mine = wordSerial
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	stroke.Transparency = 0
	label.Visible = true
	label.Size = UDim2.fromScale(size or 1, size or 1)
	scale.Scale = 0.5
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(hold or 0.6, function()
		if wordSerial ~= mine then
			return
		end
		local info = TweenInfo.new(0.2)
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		TweenService:Create(scale, info, { Scale = 1.15 }):Play()
		task.delay(0.25, function()
			if wordSerial == mine then
				label.Visible = false
			end
		end)
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

-- A full-screen root frame (layouts are made for a 1280x720 screen; clusters scale).
function Ui.root(gui: ScreenGui): Frame
	local existing = gui:FindFirstChild("Root") :: Frame?
	if existing then
		return existing
	end
	local root = Ui.frame({ Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	root.Parent = gui
	return root
end

-- The screen scale: design pixels (1280x720) to real pixels, at least 0.62 on phones.
function Ui.scale(): number
	local cam = Workspace.CurrentCamera
	if not cam then
		return 1
	end
	local v = cam.ViewportSize
	local s = math.clamp(math.min(v.X / 1280, v.Y / 720) * 1.05, 0.55, 1.25)
	if Ui.isPhone() then
		s = math.max(s, 0.62)
	end
	return s
end

local scales: { UIScale } = {}
local fits: { { scale: UIScale, size: Vector2 } } = {}
local function rescale()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local s = Ui.scale()
	for _, scale in scales do
		scale.Scale = s
	end
	-- Windows also shrink to fit the screen (phones in landscape are short).
	local v = cam.ViewportSize
	for _, f in fits do
		local fit = math.min((v.X - 40) / f.size.X, (v.Y - 50) / f.size.Y)
		f.scale.Scale = math.min(s, fit)
	end
end

-- Adds a UIScale that follows the screen to a cluster (HUD corner, popup...).
function Ui.autoScale(object: GuiObject)
	local scale = Instance.new("UIScale")
	scale.Name = "AutoScale"
	scale.Parent = object
	table.insert(scales, scale)
	rescale()
end

-- Like autoScale, but never bigger than the screen allows (windows).
function Ui.fitScale(object: GuiObject, size: Vector2)
	local scale = Instance.new("UIScale")
	scale.Name = "AutoScale"
	scale.Parent = object
	table.insert(fits, { scale = scale, size = size })
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

-- Closes whatever window is open (the hatch show needs the screen).
function Ui.closeOpenWindow()
	if openWindow then
		openWindow.Visible = false
		openWindow = nil
	end
end

function Ui.closeWindow(window: GuiObject)
	window.Visible = false
	if openWindow == window then
		openWindow = nil
	end
end

-- A dim behind a window that follows the window's Visible and closes it when tapped.
function Ui.dim(gui: Instance, window: GuiObject, onTap: (() -> ())?): TextButton
	local dim = Instance.new("TextButton")
	dim.Name = window.Name .. "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BorderSizePixel = 0
	dim.BackgroundColor3 = Ui.Colors.Dim
	dim.BackgroundTransparency = 0.55
	-- Oversized and centred so it also covers the top bar and the notch.
	dim.Size = UDim2.new(1, 400, 1, 400)
	dim.AnchorPoint = Vector2.new(0.5, 0.5)
	dim.Position = UDim2.fromScale(0.5, 0.5)
	dim.ZIndex = math.max(1, window.ZIndex - 1)
	dim.Visible = window.Visible
	dim.Activated:Connect(function()
		if onTap then
			onTap()
		else
			Ui.closeWindow(window)
		end
	end)
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		dim.Visible = window.Visible
	end)
	dim.Parent = gui
	return dim
end

-- Recolours a window's header (role colour per window: blue, gold, red...).
function Ui.setHeader(window: GuiObject, color: Color3)
	local header = window:FindFirstChild("Header") :: Frame?
	if header then
		Ui.tint(header, color)
	end
end

-- The window chrome (the packs' windows): a slate body with a black outline, a coloured
-- stud header (icon + short title on the left) with the red X block at its right end, a
-- dim behind (tap it to close). Returns the window and its Body frame (content goes there; the body
-- starts under the header and has 14 px of room on each side).
-- opts: Icon (Config/Images name), Color (header colour), NoClose, NoDim, OnClose (X and
-- dim call it instead of just closing).
function Ui.window(gui: ScreenGui, name: string, title: string, size: Vector2, opts: { [string]: any }?): (Frame, Frame)
	local o = opts or {}
	local HEADER = 64
	local window = Ui.frame({
		Name = name,
		Size = UDim2.fromOffset(size.X, size.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Ui.Colors.Panel,
		Visible = false,
		ZIndex = 20,
	})
	Ui.stroke(window, 3)
	Ui.fitScale(window, size + Vector2.new(0, 10))
	local header = Ui.frame({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, HEADER),
		BackgroundColor3 = o.Color or Ui.Colors.Header,
		ZIndex = 21,
	})
	Ui.block(header, nil, 3, 6)
	header.Parent = window
	local left = 16
	if o.Icon then
		Ui.icon(o.Icon, {
			Size = UDim2.fromOffset(60, 60),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, -2),
			ZIndex = 23,
		}).Parent =
			header
		left = 72
	end
	local t = Ui.label({
		Name = "Title",
		Size = UDim2.new(1, -left - HEADER - 12, 1, -18),
		Position = UDim2.fromOffset(left, 7),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
	})
	Ui.maxText(t, 38)
	local ts = t:FindFirstChildOfClass("UIStroke")
	if ts then
		ts.Thickness = 2.5
	end
	t.Parent = header
	if not o.NoClose then
		-- The red X block fills the header's right end (Ultra UI Pack).
		local close = Ui.closeButton(function()
			if o.OnClose then
				o.OnClose()
			else
				Ui.closeWindow(window)
			end
		end, HEADER)
		close.Size = UDim2.fromOffset(HEADER + 6, HEADER)
		close.AnchorPoint = Vector2.new(1, 0)
		close.Position = UDim2.new(1, 0, 0, 0)
		close.ZIndex = 24
		for _, d in close:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = math.max(d.ZIndex, 24)
			end
		end
		close.Parent = header
	end
	local body = Ui.frame({
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -28, 1, -HEADER - 24),
		Position = UDim2.fromOffset(14, HEADER + 12),
		ZIndex = 21,
	})
	body.Parent = window
	window.Parent = gui
	if not o.NoDim then
		Ui.dim(gui, window, o.OnClose)
	end
	-- Pop in when opened: the content slides up into place.
	local holder = window
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if holder.Visible and not Ui.reducedMotion() then
			local b = body
			b.Position = UDim2.fromOffset(14, HEADER + 22)
			TweenService
				:Create(b, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Position = UDim2.fromOffset(14, HEADER + 12) })
				:Play()
		end
	end)
	return window, body
end

-------------------------------------------------------------------------- icon-first kit
-- Kids don't read (Dev, 2026-11-20; Tizzy playbook): buttons are big icons from the
-- Free Icon Pack (Config/Images), with at most one short word.

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

-- Round red badge with a white ring and a count (hidden at 0).
function Ui.badge(parent: GuiObject, count: number)
	local b = parent:FindFirstChild("Badge") :: TextLabel?
	if not b then
		local nb = Ui.label({
			Name = "Badge",
			Size = UDim2.fromOffset(26, 26),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -3, 0, 3),
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(214, 22, 52),
			Text = "",
			ZIndex = 8,
		})
		Ui.maxText(nb, 17)
		Ui.round(nb)
		local ring = Instance.new("UIStroke")
		ring.Name = "Ring"
		ring.Color = Color3.new(1, 1, 1)
		ring.Thickness = 2.5
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = nb
		nb.Parent = parent
		b = nb
	end
	local bb = b :: TextLabel
	bb.Visible = count > 0
	bb.Text = if count > 9 then "9+" else tostring(count)
end

-- A HUD tile (Sweep rail): a square stud button, the icon in the upper part and ONE word
-- inside the tile along the bottom edge (Dev: words hanging under tiles looked off).
function Ui.tile(name: string, icon: string, word: string, color: Color3, onClick: () -> (), size: number?): TextButton
	local s = size or 72
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = color
	b.Size = UDim2.fromOffset(s, s)
	Ui.block(b)
	local hasWord = word ~= ""
	Ui.icon(icon, {
		Size = UDim2.fromOffset(
			math.floor(s * (if hasWord then 0.66 else 0.8)),
			math.floor(s * (if hasWord then 0.66 else 0.8))
		),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, if hasWord then 0.4 else 0.5, 0),
		ZIndex = 3,
	}).Parent =
		b
	local l = Ui.label({
		Name = "Label",
		Size = UDim2.new(1, -4, 0, math.floor(s * 0.24)),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Text = word,
		ZIndex = 4,
	})
	Ui.maxText(l, math.floor(s * 0.2))
	l.Parent = b
	press(b, onClick)
	return b
end

-- A big number with its icon and no panel (both packs): bottom-left money and Power.
function Ui.stat(name: string, icon: string, color: Color3, width: number?): (Frame, TextLabel)
	local f = Ui.frame({
		Name = name,
		Size = UDim2.fromOffset(width or 240, 52),
		BackgroundTransparency = 1,
	})
	Ui.icon(icon, {
		Size = UDim2.fromOffset(52, 52),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		ZIndex = 2,
	}).Parent =
		f
	local value = Ui.label({
		Name = "Value",
		Size = UDim2.new(1, -60, 0, 44),
		Position = UDim2.fromOffset(58, 4),
		Text = "0",
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	Ui.maxText(value, 42)
	local st = value:FindFirstChildOfClass("UIStroke")
	if st then
		st.Thickness = 3
	end
	value.Parent = f
	return f, value
end

-- A big action button (ROLL / STOP / Buy): a stud block, optional icon on the left, one word.
function Ui.bigButton(
	name: string,
	icon: string?,
	word: string,
	color: Color3,
	onClick: () -> (),
	size: Vector2?
): TextButton
	local sz = size or Vector2.new(230, 76)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = color
	b.Size = UDim2.fromOffset(sz.X, sz.Y)
	Ui.block(b, nil, 3, math.max(5, math.floor(sz.Y * 0.09)))
	local iconSize = math.floor(sz.Y * 0.78)
	if icon then
		Ui.icon(icon, {
			Size = UDim2.fromOffset(iconSize, iconSize),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			ZIndex = 3,
		}).Parent =
			b
	end
	local left = if icon then iconSize + 16 else 12
	local l = Ui.label({
		Name = "Label",
		Size = UDim2.new(1, -left - 12, 0, math.floor(sz.Y * 0.56)),
		Position = UDim2.new(0, left, 0.5, -math.floor(sz.Y * 0.28)),
		Text = word,
		ZIndex = 3,
	})
	Ui.maxText(l, math.floor(sz.Y * 0.5))
	local st = l:FindFirstChildOfClass("UIStroke")
	if st then
		st.Thickness = 2.5
	end
	l.Parent = b
	press(b, onClick)
	return b
end

-- A currency number with an optional green "+" block right after it.
function Ui.pill(name: string, icon: string, color: Color3, width: number, onPlus: (() -> ())?): (Frame, TextLabel)
	local f, value = Ui.stat(name, icon, color, width)
	if onPlus then
		value.Size = UDim2.new(1, -110, 0, 44)
		local plus = Ui.button({
			Name = "Plus",
			Size = UDim2.fromOffset(40, 40),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			BackgroundColor3 = Ui.Colors.Green,
			ZIndex = 3,
		}, "+", onPlus)
		plus.Parent = f
	end
	return f, value
end

return Ui
