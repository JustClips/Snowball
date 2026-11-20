--!strict
-- KEEP ROLLING? (DIRECTION.md, the near miss). When your ball stops just short of the next
-- zone (or your best distance) the server pauses the roll (RollService "Stopped") and this
-- card pops: a bar from the zone you're in to the next one, filled to where you stopped,
-- with a lighter part showing where one more push gets you, a big green Robux button with
-- a pulse, and a countdown. X / the timer / closing Roblox's buy box cracks the ball.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Zones = require(Shared.Config.Zones)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local ContinueController = {}

local card: Frame
local cardScale: UIScale
local fill: Frame
local ghost: Frame
local goal: TextLabel
local goalIcon: ImageLabel
local buy: TextButton
local buyScale: UIScale
local timerBar: Frame
local timerText: TextLabel
local current: any = nil
local serial = 0
local buying = false

local GOLD = Color3.fromRGB(255, 210, 60)

function ContinueController:Hide()
	serial += 1
	current = nil
	buying = false
	card.Visible = false
end

local function decline()
	if not current then
		return
	end
	ContinueController:Hide()
	Net.event("DeclineContinue"):FireServer()
end

local function onBuy()
	local info = current
	if not info or buying then
		return
	end
	buying = true
	Ui.setText(buy, "...")
	local ok, why = Net.func("PromptPurchase"):InvokeServer(info.Product)
	if not ok then
		if why then
			Ui.toast(why, "Bad")
		end
		decline()
	end
end

local function pulse(mine: number)
	task.spawn(function()
		while serial == mine do
			TweenService:Create(buyScale, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { Scale = 1.08 }):Play()
			task.wait(0.4)
			TweenService:Create(buyScale, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
			task.wait(0.45)
		end
	end)
end

local function show(info)
	serial += 1
	local mine = serial
	current = info
	buying = false
	local zone = Zones.List[info.Zone] or Zones.List[1]
	local nextZone = info.NextZone and Zones.List[info.NextZone]
	local from = info.ZoneStart or zone.Start
	local target = if nextZone then nextZone.Start else (info.Best or info.Reach)
	local span = math.max(1, target - from)
	local at = math.clamp((info.Distance - from) / span, 0.04, 0.97)
	local reach = math.clamp((info.Reach - from) / span, at, 1)
	fill.Size = UDim2.fromScale(at, 1)
	ghost.Size = UDim2.fromScale(at, 1)
	if nextZone then
		goal.Text = nextZone.Name
		goal.TextColor3 = nextZone.Color
		goalIcon.Image = Ui.Images.Pin or ""
	else
		goal.Text = "BEST"
		goal.TextColor3 = GOLD
		goalIcon.Image = Ui.Images.Trophy or ""
	end
	Ui.setText(buy, `{Ui.ROBUX}{info.Price}`)
	card.Visible = true
	cardScale.Scale = 0.4
	TweenService:Create(cardScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	-- The lighter "one more push" part grows after the card lands.
	task.delay(0.25, function()
		if serial == mine then
			TweenService:Create(ghost, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(reach, 1) })
				:Play()
		end
	end)
	Ui.sound("Pop")
	pulse(mine)
	-- Countdown (the server keeps the real clock; this one only shows it).
	local seconds = info.Seconds or 8
	local started = os.clock()
	timerBar.Size = UDim2.fromScale(1, 1)
	task.spawn(function()
		while serial == mine do
			local left = seconds - (os.clock() - started)
			if not buying then
				timerBar.Size = UDim2.fromScale(math.clamp(left / seconds, 0, 1), 1)
				timerText.Text = tostring(math.max(0, math.ceil(left)))
				if left <= 0 then
					ContinueController:Hide()
					return
				end
			end
			task.wait(0.05)
		end
	end)
end

function ContinueController:Init(_controllers)
	local gui = Ui.screen("Continue", 30)
	local root = Ui.root(gui)
	card = Ui.frame({
		Name = "Card",
		Size = UDim2.fromOffset(470, 290),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.62, 0),
		BackgroundColor3 = Ui.Colors.PanelDark,
		Visible = false,
	})
	Ui.corner(card, 20)
	Ui.stroke(card, 4)
	Ui.autoScale(card)
	cardScale = Instance.new("UIScale")
	cardScale.Parent = card

	local title = Ui.label({
		Name = "Title",
		Size = UDim2.new(1, -90, 0, 58),
		Position = UDim2.fromOffset(20, 10),
		Text = "KEEP ROLLING?",
		TextColor3 = GOLD,
	})
	local tg = Instance.new("UIGradient")
	tg.Color = ColorSequence.new(Color3.new(1, 1, 1), GOLD)
	tg.Rotation = 90
	tg.Parent = title
	local ts = title:FindFirstChildOfClass("UIStroke")
	if ts then
		ts.Thickness = 4
	end
	title.Parent = card

	-- Close (no thanks).
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = ""
	close.BorderSizePixel = 0
	close.BackgroundColor3 = Ui.Colors.Red
	close.Size = UDim2.fromOffset(46, 46)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.ZIndex = 5
	Ui.corner(close, 10)
	Ui.gradient(close)
	Ui.stroke(close, 3)
	Ui.label({ Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6), Text = "X", ZIndex = 6 }).Parent =
		close
	close.Activated:Connect(function()
		Ui.sound("Click")
		decline()
	end)
	close.Parent = card

	-- Progress: snowball | bar (filled, lighter "push" part) | goal flag.
	local row = Ui.frame({
		Name = "Progress",
		Size = UDim2.new(1, -36, 0, 64),
		Position = UDim2.fromOffset(18, 76),
		BackgroundTransparency = 1,
	})
	row.Parent = card
	Ui.icon("Icon_Snowball", { Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(0, 2), ZIndex = 4 }).Parent =
		row
	local track = Ui.frame({
		Name = "Track",
		Size = UDim2.new(1, -200, 0, 30),
		Position = UDim2.new(0, 48, 0.5, -15),
		BackgroundColor3 = Color3.fromRGB(12, 14, 34),
		ClipsDescendants = true,
		ZIndex = 2,
	})
	Ui.corner(track, 15)
	Ui.stroke(track, 3)
	track.Parent = row
	ghost = Ui.frame({
		Name = "Push",
		Size = UDim2.fromScale(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(140, 255, 150),
		BackgroundTransparency = 0.45,
		ZIndex = 2,
	})
	Ui.corner(ghost, 15)
	ghost.Parent = track
	fill = Ui.frame({
		Name = "Fill",
		Size = UDim2.fromScale(0.4, 1),
		BackgroundColor3 = Ui.Colors.Ice,
		ZIndex = 3,
	})
	Ui.corner(fill, 15)
	Ui.gradient(fill)
	fill.Parent = track
	local flag = Ui.frame({
		Name = "Goal",
		Size = UDim2.fromOffset(150, 64),
		Position = UDim2.new(1, -150, 0, 0),
		BackgroundTransparency = 1,
	})
	flag.Parent = row
	goalIcon = Ui.icon("Pin", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(4, 0), ZIndex = 4 })
	goalIcon.Parent = flag
	goal = Ui.label({
		Name = "Name",
		Size = UDim2.new(1, -4, 0, 28),
		Position = UDim2.fromOffset(0, 36),
		Text = "",
		ZIndex = 4,
	})
	goal.Parent = flag

	-- The big green button.
	-- (in a holder: the button's own UIScale is its press bounce, the holder's is the pulse)
	local holder = Ui.frame({
		Name = "BuyHolder",
		Size = UDim2.fromOffset(280, 80),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 152),
		BackgroundTransparency = 1,
	})
	buyScale = Instance.new("UIScale")
	buyScale.Parent = holder
	holder.Parent = card
	buy = Ui.bigButton("Buy", "Icon_Snowball", "", Ui.Colors.Green, onBuy, Vector2.new(280, 80))
	buy.Parent = holder

	-- Countdown under the button.
	local timer = Ui.frame({
		Name = "Timer",
		Size = UDim2.new(1, -110, 0, 16),
		Position = UDim2.new(0, 30, 1, -32),
		BackgroundColor3 = Color3.fromRGB(12, 14, 34),
	})
	Ui.corner(timer, 8)
	Ui.stroke(timer, 2)
	timer.Parent = card
	timerBar = Ui.frame({ Name = "Bar", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.Colors.Yellow })
	Ui.corner(timerBar, 8)
	timerBar.Parent = timer
	timerText = Ui.label({
		Name = "Seconds",
		Size = UDim2.fromOffset(44, 36),
		Position = UDim2.new(1, -66, 1, -42),
		Text = "8",
	})
	timerText.Parent = card

	card.Parent = root
end

function ContinueController:Start()
	Net.event("RunStopped").OnClientEvent:Connect(show)
	Net.event("RunContinued").OnClientEvent:Connect(function(userId)
		if userId == player.UserId then
			ContinueController:Hide()
		end
	end)
	Net.event("RunEnded").OnClientEvent:Connect(function(userId)
		if userId == player.UserId then
			ContinueController:Hide()
		end
	end)
end

return ContinueController
