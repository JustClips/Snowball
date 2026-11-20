--!strict
-- "You got it" right after any Robux purchase: a card slides in top left (not the
-- middle) with the product's picture and what you got ("+$424M"), then slides out. Gifts say who sent / got it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Ui = require(script.Parent.Parent.Ui)

local PurchaseController = {}

local stamp: Frame
local stampScale: UIScale
local inner: Frame
local icon: ImageLabel
local title: TextLabel
local sub: TextLabel
local serial = 0

local KIND_ICON: { [string]: string } = {
	StarterPack = "Chest",
	KeepRolling = "Icon_Snowball",
	RainbowPop = "Star",
	RobuxRoller = "Power",
	TrainTime = "Clock",
	PowerPack = "Power",
	Boost = "Bolt",
	LuckyRoll = "Luck",
	SuperLucky = "Luck",
	ServerLuck = "Luck",
	GoldenRuns = "Star",
	EggPack = "GoldenEgg",
	HugePet = "Pets",
	SkipHatch = "Clock",
	CashPack = "Cash",
	Avalanche = "Storm",
	SkipRebirth = "Rebirth",
	WheelSpins = "Wheel",
	DoubleOffline = "Cash",
}

-- The product's own Shop picture (art/icons_shop), when it has one.
local KEY_PIC: { [string]: string } = {
	Cash2x = "Pass2xCash",
	Train2x = "Pass2xPower",
	AutoTrain = "PassFastTrain",
	Lucky = "PassLucky",
	GoldenSnowball = "PassGoldBall",
	VIP = "PassVIP",
	Train2xBoost = "Pass2xPower",
	SuperLuckyRoll = "SuperLucky",
	StarterPack = "StarterRoller",
}
for i = 1, 4 do
	KEY_PIC["PowerPack" .. i] = "Power" .. i
	KEY_PIC["Cash" .. i] = "Cash" .. i
end
for _, n in { 3, 10, 35, 100 } do
	KEY_PIC["LuckyRoll" .. n] = "Lucky" .. n
end
for _, n in { 2, 4, 8, 16 } do
	KEY_PIC["ServerLuck" .. n] = "ServerLuck"
end

local function show(key: string, info: any)
	local def = Products.ProductByKey[key] or Products.PassByKey[key]
	if not def then
		return
	end
	if def.Kind == "KeepRolling" then
		return -- the ball itself is the feedback (BallController "KEEP ROLLING!")
	end
	serial += 1
	local mine = serial
	icon.Image = Ui.Images["Shop_" .. (KEY_PIC[key] or "")] or Ui.Images[KIND_ICON[def.Kind or ""] or "Gift"] or ""
	-- What you got, big ("+$424M", "+9.6K"); the product name small under it.
	local got = info and info.Got
	title.Text = if got then got else `{def.Name}!`
	title.TextColor3 = if def.Kind == "CashPack" then Ui.Colors.Green else Color3.fromRGB(255, 220, 60)
	sub.Text = if info and info.From
		then `Gift from {info.From}`
		elseif info and info.To then `Sent to {info.To}`
		elseif got then def.Name
		else "BOUGHT!"
	-- Off centre (Dev 2026-11-20): slides in top left, clear of the rails and the chips.
	stamp.Visible = true
	stampScale.Scale = 1
	inner.Position = UDim2.fromScale(-1.2, 0)
	TweenService:Create(inner, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0, 0) }):Play()
	Ui.sound("Cash")
	task.delay(2.6, function()
		if serial ~= mine then
			return
		end
		TweenService:Create(inner, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(-1.2, 0),
		}):Play()
		task.wait(0.27)
		if serial == mine then
			stamp.Visible = false
		end
	end)
end

function PurchaseController:Init(_controllers)
	local gui = Ui.screen("Purchase", 60)
	local root = Ui.root(gui)
	stamp = Ui.frame({
		Name = "Stamp",
		Size = UDim2.fromOffset(380, 110),
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 16, 0, 6),
		BackgroundTransparency = 1,
		Visible = false,
	})
	Ui.autoScale(stamp)
	inner = Ui.frame({
		Name = "Inner",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.Colors.Ink,
		BackgroundTransparency = 0.25,
	})
	Ui.stroke(inner, 3)
	stampScale = Instance.new("UIScale")
	stampScale.Parent = inner
	inner.Parent = stamp
	icon = Ui.icon("Gift", {
		Size = UDim2.fromOffset(96, 96),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
	})
	icon.Parent = inner
	title = Ui.label({
		Name = "Title",
		Size = UDim2.new(1, -118, 0, 58),
		Position = UDim2.fromOffset(108, 10),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 220, 60),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Ui.maxText(title, 54)
	local st = title:FindFirstChildOfClass("UIStroke")
	if st then
		st.Thickness = 3.5
	end
	title.Parent = inner
	sub = Ui.label({
		Name = "Sub",
		Size = UDim2.new(1, -118, 0, 30),
		Position = UDim2.fromOffset(108, 68),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Ui.maxText(sub, 24)
	sub.Parent = inner
	stamp.Parent = root
end

function PurchaseController:Start()
	Net.event("Purchased").OnClientEvent:Connect(show)
end

return PurchaseController
