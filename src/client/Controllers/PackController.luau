--!strict
-- The launch, like Throw Food For Animals (Dev 2026-11-20, reference-study.md): stepping onto
-- your lane pad starts it (RollService, no GO button). A vertical capsule meter stands BESIDE
-- the player: red ends, yellow, a green middle with a star; a white slider runs up and down
-- on the server's clock. "TAP!" under it and a pointing hand for the first rolls. A tap
-- anywhere (or Space / A) stops it. Then a big PERFECT! / GOOD! / WEAK! word pops.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local L = require(Shared.Config.HudLayout)
local Net = require(Shared.Net)
local RollMath = require(Shared.RollMath)
local State = require(script.Parent.Parent.State)
local Fx = require(script.Parent.Parent.Fx)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local PackController = {}

local gui: ScreenGui
local meter: Frame
local slider: Frame
local green: Frame
local yellow: Frame
local tapWord: TextLabel
local tapScale: UIScale
local hand: ImageLabel
local greenShine: UIGradient
local labels: { [string]: TextLabel } = {}
local zones = { green = 0.14, yellow = 0.13 }
local quality: TextLabel
local qualityScale: UIScale
local packing: { start: number }? = nil
local tapped = false

local function push()
	if not packing or tapped then
		return
	end
	tapped = true
	Net.event("PackTap"):FireServer(Workspace:GetServerTimeNow())
	Ui.sound("Tap")
end

function PackController:IsPacking(): boolean
	return packing ~= nil
end

local function hide()
	packing = nil
	meter.Visible = false
end

function PackController:Init()
	gui = Ui.screen("Pack", 9)
	local root = Ui.root(gui)
	meter = Ui.frame({ Name = "Meter", BackgroundTransparency = 1, Visible = false })
	meter.AnchorPoint = L.Meter.Anchor
	meter.Position = L.Meter.Pos
	meter.Size = UDim2.fromOffset(L.Meter.Size.X, L.Meter.Size.Y)
	Ui.autoScale(meter)
	meter.Parent = root
	-- The meter (Dev 2026-11-20: "boring... show luck values on each zone"): a square dark
	-- tube with a black outline, zones red / yellow / green / yellow / red, and each zone's
	-- luck on its right (x1, x1.2, x1.5 from Economy.PackLuck) with a clover by the best one.
	-- A white pointer with an arrow rides up and down; the zone it is in lights up.
	local w = 64
	local h = L.Meter.Size.Y - 70
	local tube = Ui.frame({
		Name = "Tube",
		Size = UDim2.fromOffset(w, h),
		Position = UDim2.fromOffset(28, 0),
		BackgroundColor3 = Ui.Colors.Red,
	})
	Ui.stroke(tube, 4)
	Ui.gradient(tube)
	tube.Parent = meter
	yellow = Ui.frame({
		Name = "Yellow",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1, 0.4),
		BackgroundColor3 = Ui.Colors.Yellow,
		ZIndex = 2,
	})
	yellow.Parent = tube
	green = Ui.frame({
		Name = "Green",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1, 0.14),
		BackgroundColor3 = Ui.Colors.Green,
		ZIndex = 3,
	})
	Ui.stroke(green, 2)
	greenShine = Instance.new("UIGradient")
	greenShine.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(190, 190, 190)),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 190, 190)),
	})
	greenShine.Parent = green
	green.Parent = tube
	-- Zone luck labels (placed on PackStart, when the zone sizes are known).
	local function zoneLabel(name: string, value: number, color: Color3): TextLabel
		local l = Ui.label({
			Name = name,
			Size = UDim2.fromOffset(84, 34),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(28 + w + 8, 0),
			Text = `x{value}`,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		Ui.maxText(l, 30)
		local st = l:FindFirstChildOfClass("UIStroke")
		if st then
			st.Thickness = 3
		end
		l.Parent = meter
		return l
	end
	local luck = Economy.PackLuck
	labels = {
		Green = zoneLabel("LuckGreen", luck.Perfect, Ui.Colors.Lime),
		YellowTop = zoneLabel("LuckYellowTop", luck.Good, Ui.Colors.Yellow),
		YellowBottom = zoneLabel("LuckYellowBottom", luck.Good, Ui.Colors.Yellow),
		RedTop = zoneLabel("LuckRedTop", luck.Weak, Color3.fromRGB(255, 110, 110)),
		RedBottom = zoneLabel("LuckRedBottom", luck.Weak, Color3.fromRGB(255, 110, 110)),
	}
	labels.Green.Size = UDim2.fromOffset(84, 42)
	Ui.maxText(labels.Green, 38)
	Ui.icon("Luck", {
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 70, 0.5, 0),
		ZIndex = 5,
	}).Parent =
		labels.Green
	-- The pointer: a white bar across the tube with an arrow on its left.
	slider = Ui.frame({
		Name = "Slider",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 28 - 8, 0, h),
		Size = UDim2.fromOffset(w + 16, 12),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 6,
	})
	Ui.stroke(slider, 3)
	local arrow = Ui.label({
		Name = "Arrow",
		Size = UDim2.fromOffset(34, 40),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Text = "\u{25B6}",
		ZIndex = 7,
	})
	Ui.maxText(arrow, 34)
	arrow.Parent = slider
	slider.Parent = meter
	tapWord = Ui.label({
		Name = "Tap",
		Size = UDim2.fromOffset(140, 52),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0, 28 + w / 2, 0, h + 12),
		Text = "TAP!",
		TextColor3 = Ui.Colors.Yellow,
	})
	tapScale = Instance.new("UIScale")
	tapScale.Parent = tapWord
	tapWord.Parent = meter
	hand = Ui.icon("Tap", {
		Name = "Hand",
		Size = UDim2.fromOffset(84, 84),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0, 28 + w / 2 + 96, 0, h + 30),
		ZIndex = 5,
	})
	hand.Parent = meter

	quality = Ui.label({
		Name = "Quality",
		Size = UDim2.fromOffset(600, 96),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Text = "",
		Visible = false,
	})
	local qs = quality:FindFirstChildOfClass("UIStroke")
	if qs then
		qs.Thickness = 4
	end
	qualityScale = Instance.new("UIScale")
	qualityScale.Parent = quality
	quality.Parent = root
end

function PackController:Start()
	Net.event("PackStart").OnClientEvent
		:Connect(function(start: number, _period: number, greenWidth: number, yellowWidth: number)
			packing = { start = start }
			tapped = false
			green.Size = UDim2.fromScale(1, greenWidth)
			yellow.Size = UDim2.fromScale(1, greenWidth + yellowWidth * 2)
			zones.green, zones.yellow = greenWidth, yellowWidth
			local h = L.Meter.Size.Y - 70
			local function at(label: TextLabel, f: number)
				label.Position = UDim2.new(label.Position.X.Scale, label.Position.X.Offset, 0, h * f)
			end
			local half = greenWidth / 2
			at(labels.Green, 0.5)
			at(labels.YellowTop, 0.5 - half - yellowWidth / 2)
			at(labels.YellowBottom, 0.5 + half + yellowWidth / 2)
			local redEdge = half + yellowWidth
			at(labels.RedTop, (0.5 - redEdge) / 2)
			at(labels.RedBottom, 1 - (0.5 - redEdge) / 2)
			local runs = State.data and State.data.Stats and State.data.Stats.Runs or 0
			hand.Visible = runs < 3
			meter.Visible = true
		end)
	Net.event("RunStarted").OnClientEvent:Connect(function(userId: number, info)
		if userId ~= player.UserId then
			return
		end
		hide()
		quality.Text = `{string.upper(info.Quality)}!`
		Ui.sound(if info.Quality == "Perfect" then "Perfect" elseif info.Quality == "Good" then "Good" else "Weak")
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			Fx.burst("Puff", hrp.Position + hrp.CFrame.LookVector * 4, 1.4)
			Fx.burst("Ring", hrp.Position - Vector3.yAxis * 2.5, 1)
			if info.Quality == "Perfect" then
				Fx.burst("Sparkle", hrp.Position, 2)
			end
		end
		Ui.word(
			quality.Text,
			if info.Quality == "Perfect"
				then Ui.Colors.Green
				elseif info.Quality == "Good" then Ui.Colors.Yellow
				else Ui.Colors.Red,
			0.8
		)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not packing then
			return
		end
		local t = input.UserInputType
		-- Any tap counts while the meter is up (a tap on a HUD button too: nothing else
		-- is on screen then).
		if
			t == Enum.UserInputType.Touch
			or t == Enum.UserInputType.MouseButton1
			or (not processed and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA))
		then
			push()
		end
	end)
	RunService.RenderStepped:Connect(function()
		if not packing then
			return
		end
		local phase = player:GetAttribute("RollPhase")
		if phase ~= "Packing" and phase ~= nil then
			hide()
			return
		end
		local t = Workspace:GetServerTimeNow() - packing.start
		local h = L.Meter.Size.Y - 70
		local v = RollMath.needle(math.max(0, t))
		slider.Position = UDim2.new(0, slider.Position.X.Offset, 0, h * (1 - v))
		-- The zone under the pointer grows a little; the green one always shimmers.
		local d = math.abs(v - 0.5)
		local inGreen = d <= zones.green / 2
		local inYellow = not inGreen and d <= zones.green / 2 + zones.yellow
		local function size(label: TextLabel?, on: boolean)
			if label then
				local sc = label:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", label)
				sc.Scale = if on then 1.25 else 1
			end
		end
		size(labels.Green, inGreen)
		size(labels.YellowTop, inYellow and v > 0.5)
		size(labels.YellowBottom, inYellow and v < 0.5)
		size(labels.RedTop, not inGreen and not inYellow and v > 0.5)
		size(labels.RedBottom, not inGreen and not inYellow and v < 0.5)
		greenShine.Offset = Vector2.new(0, math.sin(os.clock() * 5) * 0.5)
		greenShine.Rotation = 90
		local pulse = 1 + 0.08 * math.abs(math.sin(os.clock() * 6))
		tapScale.Scale = if tapped then 0.9 else pulse
		hand.Position = UDim2.new(0, 28 + 64 / 2 + 96, 0, h + 30 - 10 * math.abs(math.sin(os.clock() * 6)))
	end)
end

return PackController
