--!strict
-- "Buy the missing amount" (Dev 2026-11-20): on the 3rd "not enough cash" in a session the
-- server picks the smallest cash pack that covers what you're short (ShopService:OfferCashFor)
-- and this card offers it right there: how much you need in red, the pack's picture, what it
-- gives in green, one Robux button. Closes itself after 10 s.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Buy = require(script.Parent.Parent.Buy)
local Ui = require(script.Parent.Parent.Ui)

local CashShortController = {}

local card: Frame
local scale: UIScale
local needLabel: TextLabel
local picture: ImageLabel
local gives: TextLabel
local buy: TextButton
local current: any = nil
local serial = 0

local function hide()
	serial += 1
	card.Visible = false
	current = nil
end

local function show(info)
	serial += 1
	local mine = serial
	current = info
	needLabel.Text = `NEED {Format.cash(info.Need)}`
	local n = string.match(info.Product, "%d+") or "1"
	picture.Image = Ui.Images["Shop_Cash" .. n] or Ui.Images.Cash or ""
	gives.Text = "+" .. Format.cash(info.Amount)
	Ui.setText(buy, `{Ui.ROBUX}{info.Price}`)
	card.Visible = true
	scale.Scale = 0.4
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Ui.sound("Pop")
	task.delay(10, function()
		if serial == mine and not Buy.isBusy() then
			hide()
		end
	end)
end

function CashShortController:Init(_controllers)
	local gui = Ui.screen("CashShort", 27)
	local root = Ui.root(gui)
	card = Ui.frame({
		Name = "Card",
		Size = UDim2.fromOffset(360, 330),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Ui.Colors.PanelDark,
		Visible = false,
	})
	Ui.corner(card, 18)
	Ui.stroke(card, 4)
	Ui.autoScale(card)
	scale = Instance.new("UIScale")
	local inner = Ui.frame({ Name = "Inner", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	scale.Parent = inner
	inner.Parent = card
	needLabel = Ui.label({
		Name = "Need",
		Size = UDim2.new(1, -70, 0, 46),
		Position = UDim2.fromOffset(14, 10),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 90, 90),
	})
	needLabel.Parent = inner
	local close = Ui.button({
		Name = "Close",
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		BackgroundColor3 = Ui.Colors.Red,
	}, "X", hide)
	close.Parent = inner
	local glow = Ui.frame({
		Size = UDim2.fromOffset(140, 140),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		BackgroundColor3 = Color3.fromRGB(120, 255, 140),
		BackgroundTransparency = 0.8,
	})
	Ui.corner(glow, 70)
	glow.Parent = inner
	picture = Ui.icon("Cash", {
		Name = "Picture",
		Size = UDim2.fromOffset(130, 130),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66),
		ZIndex = 2,
	})
	picture.Parent = inner
	gives = Ui.label({
		Name = "Gives",
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 200),
		Text = "",
		TextColor3 = Color3.fromRGB(110, 240, 120),
	})
	gives.Parent = inner
	buy = Ui.button(
		{
			Name = "Buy",
			Size = UDim2.fromOffset(240, 66),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			BackgroundColor3 = Color3.fromRGB(70, 205, 95),
		},
		"",
		function()
			local info = current
			if info then
				task.spawn(function()
					Buy.prompt(info.Product, nil, card)
					hide()
				end)
			end
		end
	)
	buy.Parent = inner
	card.Parent = root
end

function CashShortController:Start()
	Net.event("CashShort").OnClientEvent:Connect(show)
end

return CashShortController
