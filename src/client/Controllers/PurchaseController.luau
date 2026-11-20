--!strict
-- "You got it" right after any Robux purchase: a card slides down at the top centre with
-- the product's picture and what you GOT ("+$424M CASH", "+9.6K POWER") when the server
-- says, else the product's name, then BOUGHT! / gift line. Not in the middle of the screen
-- (Dev 2026-11-20).
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

-- Where the card sits: top centre, just under the top bar, out of the way of the ball and the
-- buttons (Dev 2026-11-20: "make the you bought thing appear somewhere not on center").
local SHOWN = UDim2.new(0.5, 0, 0, 8)
local HIDDEN = UDim2.new(0.5, 0, 0, -160)

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
	-- What you GOT when the server says ("+$424M CASH"), else the product's name.
	local gotText = info and info.Got
	title.Text = if type(gotText) == "string" then gotText else `{string.upper(def.Name)}!`
	title.TextColor3 = if type(gotText) == "string" then Color3.fromRGB(120, 255, 120) else Color3.fromRGB(255, 220, 60)
	sub.Text = if info and info.From
		then `GIFT FROM {string.upper(info.From)}!`
		elseif info and info.To then `SENT TO {string.upper(info.To)}!`
		else "BOUGHT!"
	stamp.Position = HIDDEN
	stamp.Visible = true
	stampScale.Scale = 1
	TweenService
		:Create(stamp, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = SHOWN })
		:Play()
	icon.Rotation = -12
	TweenService:Create(icon, TweenInfo.new(0.5, Enum.EasingStyle.Elastic), { Rotation = 0 }):Play()
	Ui.sound("Pop")
	task.delay(2.6, function()
		if serial ~= mine then
			return
		end
		local t = TweenService:Create(stamp, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = HIDDEN,
		})
		t:Play()
		t.Completed:Wait()
		if serial == mine then
			stamp.Visible = false
		end
	end)
end

function PurchaseController:Init(_controllers)
	local gui = Ui.screen("Purchase", 60)
	local root = Ui.root(gui)
	-- A stud block card sliding down from the top: picture left, what you got, BOUGHT!.
	stamp = Ui.frame({
		Name = "Stamp",
		Size = UDim2.fromOffset(460, 112),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = HIDDEN,
		Visible = false,
	})
	Ui.block(stamp, Color3.fromRGB(46, 51, 62))
	Ui.autoScale(stamp)
	local inner = Ui.frame({ Name = "Inner", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 })
	stampScale = Instance.new("UIScale")
	stampScale.Parent = inner
	inner.Parent = stamp
	local shine = Ui.icon("Rays", {
		Size = UDim2.fromOffset(150, 150),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 62, 0.5, 0),
		ImageTransparency = 0.55,
		ZIndex = 3,
	})
	shine.Parent = inner
	icon = Ui.icon("Gift", {
		Size = UDim2.fromOffset(96, 96),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 62, 0.5, 0),
		ZIndex = 4,
	})
	icon.Parent = inner
	title = Ui.label({
		Name = "Title",
		Size = UDim2.new(1, -136, 0, 56),
		Position = UDim2.fromOffset(122, 10),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 220, 60),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local st = title:FindFirstChildOfClass("UIStroke")
	if st then
		st.Thickness = 4
	end
	title.Parent = inner
	sub = Ui.label({
		Name = "Sub",
		Size = UDim2.new(1, -136, 0, 32),
		Position = UDim2.fromOffset(122, 68),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	sub.Parent = inner
	stamp.Parent = root
	-- Slow spin on the rays while it's up.
	game:GetService("RunService").RenderStepped:Connect(function(dt)
		if stamp.Visible then
			shine.Rotation = (shine.Rotation + dt * 40) % 360
		end
	end)
end

function PurchaseController:Start()
	Net.event("Purchased").OnClientEvent:Connect(show)
end

return PurchaseController
