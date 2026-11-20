--!strict
-- Snow Pops on screen (GAME_PLAN §5.3): draws the server's pop at its screen spot (0-1),
-- drifting, melting after its life time. Tap = ClaimPop(id). The Rainbow Pop always shows
-- its Robux price. Placeholder look per tier until the ForgeUI pop art is in.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Pops = require(Shared.Config.Pops)
local Ui = require(script.Parent.Parent.Ui)

local PopController = {}

local gui: ScreenGui
local live: { [number]: TextButton } = {}
local bigText: TextLabel

local function shout(text: string, color: Color3)
	bigText.Text = text
	bigText.TextColor3 = color
	bigText.Visible = true
	bigText.TextTransparency = 0
	local scale = bigText:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.4
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	local stroke = bigText:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	-- Fade text AND outline, then hide (the outline used to stay on screen forever).
	task.delay(1.2, function()
		if bigText.Text ~= text then
			return
		end
		TweenService:Create(bigText, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
		task.delay(0.45, function()
			if bigText.Text == text then
				bigText.Visible = false
			end
		end)
	end)
end

local function remove(id: number, popped: boolean)
	local b = live[id]
	live[id] = nil
	if not b then
		return
	end
	local scale = b:FindFirstChildOfClass("UIScale") :: UIScale
	if popped then
		TweenService:Create(scale, TweenInfo.new(0.15), { Scale = 1.4 }):Play()
	end
	TweenService:Create(b, TweenInfo.new(if popped then 0.15 else 0.4), { BackgroundTransparency = 1 }):Play()
	local label = b:FindFirstChild("Label") :: TextLabel
	TweenService:Create(label, TweenInfo.new(0.15), { TextTransparency = 1 }):Play()
	task.delay(0.45, function()
		b:Destroy()
	end)
end

local function show(id: number, tierId: string, x: number, y: number, seconds: number, price: number?)
	local tier = Pops.ById[tierId]
	if not tier then
		return
	end
	local rainbow = tier.Kind == "Rainbow"
	local text
	if rainbow then
		text = `x{tier.Mult}\n{Ui.ROBUX}{price or "?"}`
	elseif tier.Kind == "Train" then
		text = "" -- a Power icon instead (it pays Power now, bigger pops pay more)
	elseif tier.Kind == "Coin" then
		text = "$$$"
	elseif tier.Kind == "Luck" then
		text = "LUCK"
	else
		text = "GIFT"
	end
	local size = if rainbow then 130 elseif tier.Kind == "Train" then 92 + tier.Mult * 3 else 104
	-- A round bubble (Dev 2026-11-20: pops are circles): outline, light top, the word inside.
	local b = Instance.new("TextButton")
	b.Name = "Pop" .. id
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(size, size)
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromScale(x, y)
	b.BackgroundColor3 = tier.Color
	Ui.round(b)
	Ui.stroke(b, 4)
	Ui.gradient(b)
	Ui.maxText(
		Ui.label({
			Name = "Label",
			Size = UDim2.new(0.8, 0, 0.6, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Text = text,
			ZIndex = 2,
			Parent = b,
		}),
		40
	)
	if tier.Kind == "Train" then
		Ui.icon("Power", {
			Size = UDim2.fromScale(0.62, 0.62),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 2,
		}).Parent =
			b
	end
	local popScale = Instance.new("UIScale")
	popScale.Parent = b
	b.Activated:Connect(function()
		Net.event("ClaimPop"):FireServer(id)
		Ui.sound("Pop", 1.2)
		if not rainbow then
			remove(id, true)
		end
	end)
	local label = b:FindFirstChild("Label") :: TextLabel
	label.TextColor3 = if tier.Id == "Snowflake" then Ui.Colors.Ink else Ui.Colors.Snow
	if rainbow then
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 210, 60)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 230, 120)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 170, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 100, 255)),
		})
		gradient.Rotation = 35
		gradient.Parent = b
	end
	b.Parent = gui
	live[id] = b
	-- Pop in, then drift up a little for its life.
	local inner = b:FindFirstChildOfClass("UIScale") :: UIScale
	inner.Scale = 0.2
	TweenService:Create(inner, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(
		b,
		TweenInfo.new(seconds, Enum.EasingStyle.Sine),
		{ Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.08, y - 0.07), Rotation = math.random(-12, 12) }
	):Play()
	Ui.sound("Pop")
	task.delay(seconds + 0.3, function()
		if live[id] == b then
			remove(id, false)
		end
	end)
end

function PopController:Init()
	gui = Ui.screen("Pops", 12)
	bigText = Ui.label({
		Name = "Shout",
		Size = UDim2.fromOffset(600, 70),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Text = "",
		Visible = false,
	})
	local s = Instance.new("UIScale")
	s.Parent = bigText
	bigText.Parent = gui
end

function PopController:Start()
	Net.event("PopShown").OnClientEvent:Connect(show)
	Net.event("PopGone").OnClientEvent:Connect(function(id: number, claimed: boolean, reward: string?)
		remove(id, claimed)
		if claimed and reward and reward ~= "" then
			shout(reward, Ui.Colors.Yellow)
		end
	end)
end

return PopController
