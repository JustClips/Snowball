--!strict
-- Training on your Snow Roller (GAME_PLAN §5.1). Step onto the roller's deck and training
-- runs by itself (Dev, 2026-11-20): you are locked in place pushing the ball, every prompt
-- is off, and the HUD's bottom-centre button turns into a red STOP. A "+N" pops over your
-- head on every rep (Steal an Egg's training floaters). Every owner's ball spins.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Anims = require(Shared.Config.Anims)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local State = require(script.Parent.Parent.State)
local Fx = require(script.Parent.Parent.Fx)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local TrainController = {}

local POOL_SIZE = 24

local gui: ScreenGui
local readout: Frame
local readoutText: TextLabel
local hint: TextLabel
local pool: { TextLabel } = {}
local poolIndex = 0

local function training(): boolean
	return player:GetAttribute("Training") == true
end

local headBoard: BillboardGui? = nil
local function board(): BillboardGui?
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not head then
		return nil
	end
	if headBoard and headBoard.Adornee == head and headBoard.Parent then
		return headBoard
	end
	local b = Instance.new("BillboardGui")
	b.Name = "RepFloaters"
	b.Size = UDim2.fromOffset(260, 220)
	b.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
	b.AlwaysOnTop = true
	b.LightInfluence = 0
	b.Adornee = head
	b.Parent = gui
	for _, label in pool do
		label.Parent = b
	end
	headBoard = b
	return b
end

-- "+N" rising from above your head.
local function floater(text: string, color: Color3?)
	if not board() then
		return
	end
	poolIndex = poolIndex % POOL_SIZE + 1
	local label = pool[poolIndex]
	label.Text = text
	label.TextColor3 = color or Color3.fromRGB(120, 210, 255)
	local x = 130 + math.random(-30, 30)
	label.Position = UDim2.fromOffset(x, 190)
	label.TextTransparency = 0
	label.Visible = true
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
		TweenService:Create(stroke, TweenInfo.new(0.9), { Transparency = 1 }):Play()
	end
	local scale = label:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.5
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	TweenService:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(x, 40),
		TextTransparency = 1,
	}):Play()
end

-- Locked in place while training: no walking, no jumping, no prompts.
local saved: { speed: number, jump: number, usePower: boolean, power: number }? = nil
local function lock(on: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if on and not saved then
		saved = {
			speed = humanoid.WalkSpeed,
			jump = humanoid.JumpHeight,
			usePower = humanoid.UseJumpPower,
			power = humanoid.JumpPower,
		}
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	elseif not on and saved then
		humanoid.WalkSpeed = saved.speed
		humanoid.JumpHeight = saved.jump
		humanoid.JumpPower = saved.power
		saved = nil
	end
end

-- The push animation (art/anim/push.py): standing still at your roller you walk up behind
-- the ball and push it; moving stops the clip (training itself is radius based, server side).
local pushTrack: AnimationTrack? = nil
local pushing = false

local function myRollerPad(): BasePart?
	local index = player:GetAttribute("BaseIndex")
	local mountain = Workspace:FindFirstChild("Mountain")
	local summit = mountain and mountain:FindFirstChild("Summit")
	local bases = summit and summit:FindFirstChild("Bases")
	local base = bases and bases:FindFirstChild("Base" .. tostring(index))
	return base and base:FindFirstChild("RollerPad") :: BasePart?
end

local function stopPush()
	pushing = false
	if pushTrack then
		pushTrack:Stop(0.25)
	end
end

local function updatePush()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (training() and humanoid and root and humanoid.Health > 0) then
		if pushing then
			stopPush()
		end
		return
	end
	if not pushing and Anims.Player_Push then
		local pad = myRollerPad()
		if not pad then
			return
		end
		-- Behind the ball (roller-local -Z), facing it (+Z), on the 0.6-stud deck.
		local height = pad.Size.Y / 2 + 0.6 + humanoid.HipHeight + root.Size.Y / 2
		local spot = pad.CFrame * CFrame.new(0, height, -2.3)
		local pos = spot.Position
		character:PivotTo(CFrame.lookAt(pos, pos - spot.LookVector))
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			return
		end
		if not pushTrack or pushTrack.Parent == nil then
			local anim = Instance.new("Animation")
			anim.AnimationId = Anims.Player_Push
			pushTrack = animator:LoadAnimation(anim)
			pushTrack.Priority = Enum.AnimationPriority.Action
			pushTrack.Looped = true
		end
		local rate = Economy.TrainRepsPerSecond
		if State.data and State.data.Gamepasses and State.data.Gamepasses.AutoTrain then
			rate *= Economy.FastTrainMult
		end
		local track = pushTrack :: AnimationTrack
		track:Play(0.25)
		track:AdjustSpeed(rate / 0.8)
		pushing = true
	end
end

-- No reading while training (Dev): the spinning ball and the big "+N" pops say it all.
local function updateReadout()
	readout.Visible = false
	hint.Visible = false
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
		local found = roller and roller:FindFirstChild("Ball")
		local ball = if found and found:IsA("BasePart") then found else nil
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
			Size = UDim2.fromOffset(220, 52),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Text = "",
			Visible = false,
		})
		Instance.new("UIScale").Parent = l
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
		Text = "AUTO TRAINING! TAP THE SNOW POPS",
		TextColor3 = Ui.Colors.Yellow,
		Visible = false,
	})
	hint.Parent = root
end

function TrainController:Start()
	Net.event("PowerGained").OnClientEvent:Connect(function(amount: number, _reps: number)
		Ui.sound("Rep", 0.9 + math.random() * 0.2)
		-- A snow puff where the ball meets the deck on every rep.
		local pad = myRollerPad()
		local roller = pad and pad.Parent and pad.Parent:FindFirstChild("Roller")
		local found = roller and roller:FindFirstChild("Ball")
		local ball = if found and found:IsA("BasePart") then found else nil
		if ball then
			Fx.burst("Puff", ball.Position - Vector3.yAxis * (ball.Size.Y / 2 - 0.8), 0.8)
			if (State.data and State.data.PopMult or 1) > 1 then
				Fx.burst("Sparkle", ball.Position, 1)
			end
		end
		local popMult = State.data and State.data.PopMult or 1
		floater(
			"+" .. Format.big(amount),
			if popMult >= 25 then Color3.fromRGB(255, 130, 220) elseif popMult > 1 then Ui.Colors.Gold else nil
		)
	end)
	player:GetAttributeChangedSignal("Training"):Connect(function()
		updateReadout()
		lock(training())
	end)
	State.observe(updateReadout)
	RunService.RenderStepped:Connect(spinRollers)
	RunService.Heartbeat:Connect(updatePush)
	player.CharacterAdded:Connect(function()
		pushTrack = nil
		pushing = false
		saved = nil
		headBoard = nil
		task.defer(lock, training())
	end)
end

return TrainController
