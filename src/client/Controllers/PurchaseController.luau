--!strict
-- "You got it" right after any Robux purchase (Steal an Egg's big yellow "Bought X!" stamp):
-- a big outlined stamp in the middle of the screen with the product's picture, a pop and a
-- sound. Gifts say who sent / got it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Ui = require(script.Parent.Parent.Ui)

local PurchaseController = {}

local stamp: Frame
local stampScale: UIScale
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
	title.Text = `{string.upper(def.Name)}!`
	sub.Text = if info and info.From
		then `Gift from {info.From}`
		elseif info and info.To then `Sent to {info.To}`
		else "BOUGHT!"
	stamp.Visible = true
	stampScale.Scale = 0.3
	TweenService:Create(stampScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Ui.sound("Pop")
	task.delay(2.2, function()
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
		Size = UDim2.fromOffset(520, 150),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		BackgroundTransparency = 1,
		Visible = false,
	})
	Ui.autoScale(stamp)
	local inner = Ui.frame({ Name = "Inner", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	stampScale = Instance.new("UIScale")
	stampScale.Parent = inner
	inner.Parent = stamp
	icon = Ui.icon("Gift", { Size = UDim2.fromOffset(130, 130), Position = UDim2.fromOffset(0, 10) })
	icon.Parent = inner
	title = Ui.label({
		Name = "Title",
		Size = UDim2.new(1, -140, 0, 80),
		Position = UDim2.fromOffset(136, 14),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 220, 60),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local st = title:FindFirstChildOfClass("UIStroke")
	if st then
		st.Thickness = 5
	end
	title.Parent = inner
	sub = Ui.label({
		Name = "Sub",
		Size = UDim2.new(1, -140, 0, 44),
		Position = UDim2.fromOffset(136, 94),
		Text = "",
		TextColor3 = Color3.fromRGB(140, 255, 150),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	sub.Parent = inner
	stamp.Parent = root
end

function PurchaseController:Start()
	Net.event("Purchased").OnClientEvent:Connect(show)
end

return PurchaseController
