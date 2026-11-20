--!strict
-- The PACK meter + PUSH (GAME_PLAN §5.5, §7 item 7). On the launch deck a big ROLL button
-- starts packing; the needle swings on the server's clock and a tap (anywhere, or PUSH)
-- stops it. Green = Perfect, yellow = Good, red = Weak.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local RollMath = require(Shared.RollMath)
local World = require(Shared.Config.World)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local PackController = {}

local gui: ScreenGui
local startButton: TextButton
local meter: Frame
local needle: Frame
local green: Frame
local yellow: Frame
local packing: { start: number, green: number, yellow: number }? = nil
local tapped = false

local function nearDeck(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local d = root.Position - World.Deck.Center
	local half = World.Deck.Size / 2
	return math.abs(d.X) <= half.X + 10 and math.abs(d.Z) <= half.Z + 10 and math.abs(d.Y) < 12
end

local function push()
	if not packing or tapped then
		return
	end
	tapped = true
	Net.event("PackTap"):FireServer(Workspace:GetServerTimeNow())
	Ui.sound("Smash")
end

function PackController:IsPacking(): boolean
	return packing ~= nil
end

function PackController:Init()
	gui = Ui.screen("Pack", 9)
	local root = Ui.root(gui)
	startButton = Ui.button(
		{
			Name = "Start",
			Size = UDim2.fromOffset(260, 80),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -40),
			BackgroundColor3 = Ui.Colors.Green,
			Visible = false,
		},
		"ROLL!",
		function()
			local ok, why = Net.func("StartPack"):InvokeServer()
			if not ok and why then
				Ui.toast(why, "Bad")
			end
		end
	)
	startButton.Parent = root

	meter = Ui.frame({
		Name = "Meter",
		Size = UDim2.fromOffset(560, 120),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		BackgroundTransparency = 1,
		Visible = false,
	})
	Ui.autoScale(meter)
	meter.Parent = root
	local bar = Ui.frame({ Name = "Bar", Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Ui.Colors.Red })
	Ui.stroke(bar, 4)
	bar.Parent = meter
	yellow = Ui.frame({
		Name = "Yellow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.4, 1),
		BackgroundColor3 = Ui.Colors.Yellow,
	})
	yellow.Parent = bar
	green = Ui.frame({
		Name = "Green",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.14, 1),
		BackgroundColor3 = Ui.Colors.Green,
	})
	green.Parent = bar
	needle = Ui.frame({
		Name = "Needle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 8, 1, 18),
		BackgroundColor3 = Ui.Colors.Snow,
	})
	Ui.stroke(needle, 2)
	needle.Parent = bar
	local pushButton = Ui.button(
		{
			Name = "Push",
			Size = UDim2.fromOffset(240, 66),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 52),
			BackgroundColor3 = Ui.Colors.Power,
		},
		"PUSH!",
		push
	)
	pushButton.Parent = meter
	Ui.label({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, -36),
		Text = "PACK IT! TAP IN THE GREEN",
	}).Parent =
		meter
end

function PackController:Start()
	Net.event("PackStart").OnClientEvent
		:Connect(function(start: number, _period: number, greenWidth: number, yellowWidth: number)
			packing = { start = start, green = greenWidth, yellow = yellowWidth }
			tapped = false
			green.Size = UDim2.fromScale(greenWidth, 1)
			yellow.Size = UDim2.fromScale(greenWidth + yellowWidth * 2, 1)
			meter.Visible = true
		end)
	Net.event("RunStarted").OnClientEvent:Connect(function(userId: number, info)
		if userId == player.UserId then
			packing = nil
			meter.Visible = false
			Ui.toast(`{string.upper(info.Quality)}!`, if info.Quality == "Weak" then "Bad" else "Good")
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not packing then
			return
		end
		local t = input.UserInputType
		if
			t == Enum.UserInputType.Touch
			or t == Enum.UserInputType.MouseButton1
			or input.KeyCode == Enum.KeyCode.Space
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			push()
		end
	end)
	RunService.RenderStepped:Connect(function()
		local phase = player:GetAttribute("RollPhase")
		if packing then
			if phase ~= "Packing" and phase ~= nil then
				packing = nil
				meter.Visible = false
			else
				local t = Workspace:GetServerTimeNow() - packing.start
				needle.Position = UDim2.fromScale(RollMath.needle(math.max(0, t)), 0.5)
			end
		end
		startButton.Visible = phase == nil and packing == nil and nearDeck()
	end)
end

return PackController
