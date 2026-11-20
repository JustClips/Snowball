--!strict
-- The launch (GAME_PLAN §5.5; Dev 2026-11-20: show it like Throw Food For Animals). On the
-- deck the HUD's ROLL tile turns into GO! (same spot, HudController:SetDeck). While packing
-- the HUD buttons hide, a tall power bar stands at the right with its needle running on the
-- server's clock, and a big pulsing PUSH! tile sits bottom-centre; a tap anywhere also counts.
-- Green + star = Perfect, yellow = Good, red = Weak. Then a big PERFECT!/GOOD!/WEAK! banner.
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
local Fx = require(script.Parent.Parent.Fx)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local PackController = {}

local C: any
local gui: ScreenGui
local pushTile: TextButton
local pushScale: UIScale
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
	Ui.sound("Tap")
end

function PackController:IsPacking(): boolean
	return packing ~= nil
end

function PackController:Init(controllers)
	C = controllers
	gui = Ui.screen("Pack", 9)
	local root = Ui.root(gui)
	-- The power meter (Throw Food style): a tall bar, the needle runs up and down, the
	-- target zone glows in the middle. Tap anywhere or the big PUSH tile.
	meter = Ui.frame({
		Name = "Meter",
		Size = UDim2.fromOffset(170, 360),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.5, 20),
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
	Ui.icon(
		"Star",
		{ Size = UDim2.fromOffset(54, 54), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(1, 6, 0.5, 0) }
	).Parent =
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
	-- Big PUSH! tile where the ROLL/GO tile was, so the thumb is already there.
	local pushHolder = Ui.frame({
		Name = "PushHolder",
		Size = UDim2.fromOffset(160, 160),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		BackgroundTransparency = 1,
		Visible = false,
	})
	Ui.autoScale(pushHolder)
	pushHolder.Parent = root
	pushTile = Ui.tile("Push", "Tap", "PUSH!", Ui.Colors.Power, push, 160)
	pushTile.Parent = pushHolder
	pushScale = Instance.new("UIScale")
	pushScale.Parent = pushHolder

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
			pushTile.Parent.Visible = true
			C.HudController:SetPacking(true)
		end)
	Net.event("RunStarted").OnClientEvent:Connect(function(userId: number, info)
		if userId == player.UserId then
			packing = nil
			meter.Visible = false
			pushTile.Parent.Visible = false
			quality.Text = `{string.upper(info.Quality)}!`
			Ui.sound(if info.Quality == "Perfect" then "Perfect" elseif info.Quality == "Good" then "Good" else "Weak")
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				Fx.burst("Puff", root.Position + root.CFrame.LookVector * 4, 1.4)
				Fx.burst("Ring", root.Position - Vector3.yAxis * 2.5, 1)
				if info.Quality == "Perfect" then
					Fx.burst("Sparkle", root.Position, 2)
				end
			end
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
				pushTile.Parent.Visible = false
			else
				local t = Workspace:GetServerTimeNow() - packing.start
				needle.Position = UDim2.fromScale(0.5, 1 - RollMath.needle(math.max(0, t)))
				pushScale.Scale = if tapped then 0.9 else 1 + 0.06 * math.sin(os.clock() * 10)
			end
		end
		-- The HUD buttons come back once the pack is over (BallController hides them while rolling).
		if packing == nil then
			C.HudController:SetPacking(false)
		end
		C.HudController:SetDeck(phase == nil and packing == nil and nearDeck())
	end)
end

return PackController
