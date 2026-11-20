--!strict
-- Training on your Snow Roller (GAME_PLAN §5.1): tap anywhere that isn't a button (or
-- click, gamepad A, space) while standing on your roller. Holding trains at 3/s on the
-- server. "+N" floaters are pooled. Every roller's ball spins while its owner trains.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local TrainController = {}

local HOLD_AFTER = 0.35 -- seconds of holding before it counts as "holding"
local POOL_SIZE = 24

local gui: ScreenGui
local readout: Frame
local readoutText: TextLabel
local hint: TextLabel
local pool: { TextLabel } = {}
local poolIndex = 0
local lastTapPos = Vector2.new(0, 0)
local holdingSent = false
local pressStarted: number? = nil

local function training(): boolean
	return player:GetAttribute("Training") == true
end

local function floater(text: string, at: Vector2, color: Color3?)
	poolIndex = poolIndex % POOL_SIZE + 1
	local label = pool[poolIndex]
	label.Text = text
	label.TextColor3 = color or Ui.Colors.Snow
	local jitter = Vector2.new(math.random(-40, 40), math.random(-20, 10))
	local start = at + jitter
	label.Position = UDim2.fromOffset(start.X, start.Y)
	label.TextTransparency = 0
	label.Visible = true
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
		TweenService:Create(stroke, TweenInfo.new(0.8), { Transparency = 1 }):Play()
	end
	TweenService:Create(label, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(start.X, start.Y - 90),
		TextTransparency = 1,
	}):Play()
end

local function tap(pos: Vector2)
	if not training() then
		return
	end
	lastTapPos = pos
	Net.event("Tap"):FireServer()
	Ui.sound("Tap", 0.9 + math.random() * 0.2)
end

local function isTapInput(input: InputObject): boolean
	local t = input.UserInputType
	return t == Enum.UserInputType.Touch
		or t == Enum.UserInputType.MouseButton1
		or (t == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonA)
		or (t == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Space)
end

local function screenCenter(): Vector2
	local cam = Workspace.CurrentCamera
	return if cam then cam.ViewportSize / 2 else Vector2.new(400, 300)
end

local function setHolding(on: boolean)
	if holdingSent ~= on then
		holdingSent = on
		Net.event("SetHolding"):FireServer(on)
	end
end

local function updateReadout()
	local data = State.data
	local on = training()
	readout.Visible = on
	hint.Visible = on
	if data and on then
		readoutText.Text =
			`+{Format.big(data.PowerPerTap)} per tap  ·  x{Format.number(math.floor(data.TrainMult * 10) / 10)}`
	end
end

-- Spin the ball of every roller whose owner is training.
local function spinRollers(dt: number)
	local mountain = Workspace:FindFirstChild("Mountain")
	local bases = mountain and mountain:FindFirstChild("Summit") and (mountain :: any).Summit:FindFirstChild("Bases")
	if not bases then
		return
	end
	for _, base in bases:GetChildren() do
		local roller = base:FindFirstChild("Roller")
		local ball = roller and roller:FindFirstChild("Ball") :: BasePart?
		if roller and ball then
			local owner = Players:GetPlayerByUserId(roller:GetAttribute("Owner") or 0)
			if owner and owner:GetAttribute("Training") then
				local speed = 4
				ball.CFrame = ball.CFrame * CFrame.Angles(speed * dt, 0, 0)
			end
		end
	end
end

function TrainController:Init()
	gui = Ui.screen("Train", 8)
	local root = Ui.root(gui)
	for i = 1, POOL_SIZE do
		local l = Ui.label({
			Name = "Float" .. i,
			Size = UDim2.fromOffset(200, 44),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Text = "",
			Visible = false,
		})
		l.Parent = root
		pool[i] = l
	end
	readout = Ui.frame({
		Name = "Readout",
		Size = UDim2.fromOffset(420, 40),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		BackgroundColor3 = Ui.Colors.Panel,
		Visible = false,
	})
	Ui.stroke(readout, 3)
	Ui.autoScale(readout)
	readoutText = Ui.label({ Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), Text = "" })
	readoutText.Parent = readout
	readout.Parent = root
	hint = Ui.label({
		Name = "Hint",
		Size = UDim2.fromOffset(420, 46),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -160),
		Text = "TAP TO TRAIN!",
		TextColor3 = Ui.Colors.Yellow,
		Visible = false,
	})
	hint.Parent = root
end

function TrainController:Start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not isTapInput(input) then
			return
		end
		local pos = if input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then Vector2.new(input.Position.X, input.Position.Y)
			else screenCenter()
		tap(pos)
		pressStarted = os.clock()
	end)
	UserInputService.InputEnded:Connect(function(input)
		if isTapInput(input) then
			pressStarted = nil
			setHolding(false)
		end
	end)
	Net.event("PowerGained").OnClientEvent:Connect(function(amount: number, taps: number)
		local at = if taps > 1 or (pressStarted and os.clock() - pressStarted > HOLD_AFTER)
			then screenCenter() + Vector2.new(0, 40)
			else lastTapPos
		local popMult = State.data and State.data.PopMult or 1
		floater(
			"+" .. Format.big(amount),
			at,
			if popMult >= 25 then Color3.fromRGB(255, 130, 220) elseif popMult > 1 then Ui.Colors.Ice else nil
		)
	end)
	player:GetAttributeChangedSignal("Training"):Connect(function()
		if not training() then
			setHolding(false)
		end
		updateReadout()
	end)
	State.observe(updateReadout)
	RunService.RenderStepped:Connect(function(dt)
		if pressStarted and training() and os.clock() - pressStarted > HOLD_AFTER then
			setHolding(true)
		end
		spinRollers(dt)
	end)
end

return TrainController
