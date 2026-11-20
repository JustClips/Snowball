--!strict
-- KEEP ROLLING? (DIRECTION.md, the near miss). When your ball stops just short of the next
-- zone (or your best distance) the server pauses the roll (RollService "Stopped") and this
-- popup shows (UI polish 2026-11-20, stud style from Dev's UI packs, almost no words):
--   header: snowball icon + "KEEP ROLLING?" + red X
--   a track from here to the next zone: your snowball sits where it stopped, a lime part
--   shows how far one more push gets you, the zone's pin + name at the end
--   one big green Robux button that pulses, a yellow bar under it drains with the timer.
-- X / the dim / the timer / closing Roblox's buy box cracks the ball.
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
local fill: Frame
local ghost: Frame
local ball: ImageLabel
local goal: TextLabel
local goalIcon: ImageLabel
local buy: TextButton
local buyScale: UIScale
local timerBar: Frame
local current: any = nil
local serial = 0
local buying = false

function ContinueController:Hide()
	serial += 1
	current = nil
	buying = false
	Ui.closeWindow(card)
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
	local at = math.clamp((info.Distance - from) / span, 0.06, 0.94)
	local reach = math.clamp((info.Reach - from) / span, at, 1)
	fill.Size = UDim2.fromScale(at, 1)
	ghost.Size = UDim2.fromScale(at, 1)
	ball.Position = UDim2.fromScale(at, 0.5)
	if nextZone then
		goal.Text = nextZone.Name
		goalIcon.Image = Ui.Images.Pin or ""
	else
		goal.Text = "BEST"
		goalIcon.Image = Ui.Images.Trophy or ""
	end
	Ui.setText(buy, `{Ui.ROBUX} {info.Price}`)
	Ui.openWindow(card)
	-- The lime "one more push" part grows after the popup lands.
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
	local body
	card, body = Ui.window(gui, "Card", "KEEP ROLLING?", Vector2.new(460, 300), {
		Icon = "Icon_Snowball",
		Color = Ui.Colors.Cyan,
		OnClose = function()
			Ui.sound("Click")
			decline()
		end,
	})

	-- Track: dark well, blue fill to where you stopped, lime "one more push" part, your
	-- snowball on the fill's end, the next zone's pin + name at the far end.
	local track = Ui.frame({
		Name = "Track",
		Size = UDim2.new(1, -110, 0, 26),
		Position = UDim2.fromOffset(18, 38),
		BackgroundColor3 = Ui.Colors.PanelDark,
		ZIndex = 22,
	})
	Ui.stroke(track, 3)
	track.Parent = body
	ghost = Ui.frame({
		Name = "Push",
		Size = UDim2.fromScale(0.5, 1),
		BackgroundColor3 = Ui.Colors.Lime,
		ZIndex = 22,
	})
	Ui.studs(ghost, nil, 26, 0.2)
	ghost.Parent = track
	fill = Ui.frame({
		Name = "Fill",
		Size = UDim2.fromScale(0.4, 1),
		BackgroundColor3 = Ui.Colors.Cyan,
		ZIndex = 23,
	})
	Ui.gradient(fill)
	Ui.studs(fill, nil, 26, 0.2)
	fill.Parent = track
	ball = Ui.icon("Icon_Snowball", {
		Name = "Ball",
		Size = UDim2.fromOffset(54, 54),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.4, 0.5),
		ZIndex = 25,
	})
	ball.Parent = track
	local flag = Ui.frame({
		Name = "Goal",
		Size = UDim2.fromOffset(110, 92),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -6),
		BackgroundTransparency = 1,
		ZIndex = 22,
	})
	flag.Parent = body
	goalIcon = Ui.icon("Pin", {
		Size = UDim2.fromOffset(54, 54),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		ZIndex = 24,
	})
	goalIcon.Parent = flag
	goal = Ui.label({
		Name = "Name",
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 56),
		Text = "",
		ZIndex = 24,
	})
	Ui.maxText(goal, 20)
	goal.Parent = flag

	-- The big green button (in a holder: the button's own UIScale is its press bounce, the
	-- holder's is the pulse), and the timer bar right under it.
	local holder = Ui.frame({
		Name = "BuyHolder",
		Size = UDim2.fromOffset(300, 78),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -26),
		BackgroundTransparency = 1,
		ZIndex = 22,
	})
	buyScale = Instance.new("UIScale")
	buyScale.Parent = holder
	holder.Parent = body
	buy = Ui.bigButton("Buy", nil, "", Ui.Colors.Green, onBuy, Vector2.new(300, 78))
	buy.ZIndex = 23
	buy.Parent = holder
	local timer = Ui.frame({
		Name = "Timer",
		Size = UDim2.fromOffset(300, 12),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		BackgroundColor3 = Ui.Colors.PanelDark,
		ZIndex = 22,
	})
	Ui.stroke(timer, 2)
	timer.Parent = body
	timerBar =
		Ui.frame({ Name = "Bar", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.Colors.Yellow, ZIndex = 23 })
	timerBar.Parent = timer
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
