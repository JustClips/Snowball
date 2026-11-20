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
	local w = 66
	local h = L.Meter.Size.Y - 70
	-- The capsule: white outline tube, red at both ends, yellow, green in the middle.
	local tube = Ui.frame({
		Name = "Tube",
		Size = UDim2.fromOffset(w, h),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundColor3 = Ui.Colors.Red,
		ClipsDescendants = true,
	})
	Ui.corner(tube, w // 2)
	local outline = Ui.stroke(tube, 5, Color3.new(1, 1, 1))
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tube.Parent = meter
	local shade = Instance.new("UIGradient")
	shade.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 200, 210)),
		ColorSequenceKeypoint.new(0.35, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 170, 185)),
	})
	shade.Parent = tube
	yellow = Ui.frame({
		Name = "Yellow",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1, 0.4),
		BackgroundColor3 = Ui.Colors.Yellow,
	})
	yellow.Parent = tube
	green = Ui.frame({
		Name = "Green",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1, 0.14),
		BackgroundColor3 = Ui.Colors.Green,
	})
	green.Parent = tube
	-- Star beside the green band (outside the clipped tube so it is not cut).
	local starHolder = Ui.frame({
		Name = "StarHolder",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(52, 52),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, w / 2 + 6, 0, h / 2),
	})
	Ui.icon("Star", { Size = UDim2.fromScale(1, 1) }).Parent = starHolder
	starHolder.Parent = meter
	-- The slider: a white bar wider than the tube with a dark outline.
	slider = Ui.frame({
		Name = "Slider",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, h),
		Size = UDim2.fromOffset(w + 26, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 4,
	})
	Ui.corner(slider, 7)
	Ui.stroke(slider, 3)
	slider.Parent = meter
	tapWord = Ui.label({
		Name = "Tap",
		Size = UDim2.new(1, 40, 0, 52),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, h + 12),
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
		Position = UDim2.new(0.5, 96, 0, h + 30),
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
		slider.Position = UDim2.new(0.5, 0, 0, h * (1 - RollMath.needle(math.max(0, t))))
		local pulse = 1 + 0.08 * math.abs(math.sin(os.clock() * 6))
		tapScale.Scale = if tapped then 0.9 else pulse
		hand.Position = UDim2.new(0.5, 96, 0, h + 30 - 10 * math.abs(math.sin(os.clock() * 6)))
	end)
end

return PackController
