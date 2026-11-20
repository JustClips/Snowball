--!strict
-- Steering input (GAME_PLAN §5.5): drag left/right on touch, mouse position or A/D/arrows
-- on PC, the left stick on gamepad. Sends Steer at most 10/s; BallController reads Value
-- every frame for the local prediction, so steering answers within a frame.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local State = require(script.Parent.Parent.State)

local SteerController = {
	Value = 0,
	Active = false,
}

local SEND_EVERY = 0.1
local DRAG_FULL = 0.18 -- share of the screen width a drag needs for full steer

local touchStart: Vector2? = nil
local touchNow: Vector2? = nil
local stick = 0
local lastSent = 0
local sentValue = 0

local function keyboard(): number
	local v = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		v -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		v += 1
	end
	return v
end

local function compute(): number
	local sens = 1
	local data = State.data
	if data and data.Settings and type(data.Settings.Steer) == "number" then
		sens = data.Settings.Steer
	end
	local k = keyboard()
	if k ~= 0 then
		return k
	end
	if math.abs(stick) > 0.15 then
		return math.clamp(stick * sens, -1, 1)
	end
	local cam = Workspace.CurrentCamera
	local width = if cam then cam.ViewportSize.X else 1000
	if touchStart and touchNow then
		return math.clamp((touchNow.X - touchStart.X) / (width * DRAG_FULL) * sens, -1, 1)
	end
	if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		local m = UserInputService:GetMouseLocation()
		return math.clamp((m.X - width / 2) / (width * 0.3) * sens, -1, 1)
	end
	return 0
end

function SteerController:SetActive(on: boolean)
	SteerController.Active = on
	SteerController.Value = 0
	touchStart, touchNow = nil, nil
end

function SteerController:Start()
	UserInputService.TouchStarted:Connect(function(input, processed)
		if not processed and SteerController.Active then
			touchStart = Vector2.new(input.Position.X, input.Position.Y)
			touchNow = touchStart
		end
	end)
	UserInputService.TouchMoved:Connect(function(input)
		if touchStart then
			touchNow = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.TouchEnded:Connect(function()
		touchStart, touchNow = nil, nil
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			stick = input.Position.X
		end
	end)
	RunService.RenderStepped:Connect(function()
		if not SteerController.Active then
			return
		end
		local v = compute()
		SteerController.Value = v
		local now = os.clock()
		if now - lastSent >= SEND_EVERY and math.abs(v - sentValue) > 0.02 then
			lastSent = now
			sentValue = v
			Net.event("Steer"):FireServer(v)
		end
	end)
end

return SteerController
