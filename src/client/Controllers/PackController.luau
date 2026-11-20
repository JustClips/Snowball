--!strict
-- The launch (GAME_PLAN §5.5; Dev 2026-11-20: show it like Throw Food For Animals). On the
-- deck a giant GO tile starts packing; a tall power bar's needle runs up and down on the
-- server's clock and a tap (anywhere, or PUSH) stops it. Green + star = Perfect, yellow =
-- Good, red = Weak. A big PERFECT!/GOOD!/WEAK! banner pops, then the camera follows the ball.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local RollMath = require(Shared.RollMath)
local World = require(Shared.Config.World)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local PackController = {}

local C: any
local gui: ScreenGui
local startButton: TextButton
local quality: TextLabel
local qualityScale: UIScale
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

function PackController:Init(controllers)
	C = controllers
	gui = Ui.screen("Pack", 9)
	local root = Ui.root(gui)
	-- On the deck the HUD's ROLL tile turns into a giant GO tile right here.
	startButton = Ui.tile("Start", "Roll", "GO!", Ui.Colors.Green, function()
		local ok, why = Net.func("StartPack"):InvokeServer()
		if not ok and why then
			Ui.toast(why, "Bad")
		end
	end, 140)
	startButton.AnchorPoint = Vector2.new(0.5, 1)
	startButton.Position = UDim2.new(0.5, 0, 1, -16)
	startButton.Visible = false
	Ui.autoScale(startButton)
	startButton.Parent = root

	-- The power meter (Throw Food style): a tall bar, the needle runs up and down, the
	-- target zone glows in the middle. Tap anywhere or the big PUSH tile.
	meter = Ui.frame({
		Name = "Meter",
		Size = UDim2.fromOffset(420, 360),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		BackgroundTransparency = 1,
		Visible = false,
	})
	Ui.autoScale(meter)
	meter.Parent = root
	local bar = Ui.frame({
		Name = "Bar",
		Size = UDim2.fromOffset(70, 340),
		Position = UDim2.fromOffset(40, 0),
		BackgroundColor3 = Ui.Colors.Red,
	})
	Ui.gradient(bar, Ui.Colors.Red)
	Ui.stroke(bar, 4)
	bar.Parent = meter
	yellow = Ui.frame({
		Name = "Yellow",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1, 0.4),
		BackgroundColor3 = Ui.Colors.Yellow,
	})
	yellow.Parent = bar
	green = Ui.frame({
		Name = "Green",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1, 0.14),
		BackgroundColor3 = Ui.Colors.Green,
	})
	Ui.gradient(green, Ui.Colors.Green)
	green.Parent = bar
	Ui.icon("Star", { Size = UDim2.fromOffset(54, 54), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(1, 6, 0.5, 0) }).Parent =
		green
	needle = Ui.frame({
		Name = "Needle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 26, 0, 10),
		BackgroundColor3 = Ui.Colors.Snow,
	})
	Ui.stroke(needle, 3)
	needle.Parent = bar
	local pushTile = Ui.tile("Push", "Roll", "PUSH!", Ui.Colors.Power, push, 150)
	pushTile.AnchorPoint = Vector2.new(1, 1)
	pushTile.Position = UDim2.new(1, -10, 1, 0)
	pushTile.Parent = meter

	-- PERFECT! / GOOD! / WEAK! banner.
	quality = Ui.label({
		Name = "Quality",
		Size = UDim2.fromOffset(600, 90),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Text = "",
		Visible = false,
	})
	qualityScale = Instance.new("UIScale")
	qualityScale.Parent = quality
	quality.Parent = root
end

function PackController:Start()
	Net.event("PackStart").OnClientEvent
		:Connect(function(start: number, _period: number, greenWidth: number, yellowWidth: number)
			packing = { start = start, green = greenWidth, yellow = yellowWidth }
			tapped = false
			green.Size = UDim2.fromScale(1, greenWidth)
			yellow.Size = UDim2.fromScale(1, greenWidth + yellowWidth * 2)
			meter.Visible = true
		end)
	Net.event("RunStarted").OnClientEvent:Connect(function(userId: number, info)
		if userId == player.UserId then
			packing = nil
			meter.Visible = false
			quality.Text = `{string.upper(info.Quality)}!`
			quality.TextColor3 = if info.Quality == "Perfect"
				then Ui.Colors.Green
				elseif info.Quality == "Good" then Ui.Colors.Yellow
				else Ui.Colors.Red
			quality.TextTransparency = 0
			quality.Visible = true
			qualityScale.Scale = 0.4
			TweenService:Create(qualityScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1.15 }):Play()
			task.delay(1, function()
				TweenService:Create(quality, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			end)
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
				needle.Position = UDim2.fromScale(0.5, 1 - RollMath.needle(math.max(0, t)))
			end
		end
		local atDeck = phase == nil and packing == nil and nearDeck()
		startButton.Visible = atDeck
		local hudRoll = C.HudController:Tile("Roll")
		if hudRoll then
			hudRoll.Visible = not atDeck and phase == nil
		end
	end)
end

return PackController
