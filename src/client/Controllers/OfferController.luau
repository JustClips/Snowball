--!strict
-- The offer card (GAME_PLAN §7 item 19): one template for every contextual offer the
-- server sends (OfferService decides WHEN: after a rare hatch, after rolls without a new
-- best, when the next roller takes long, a while into the session...). Redone 2026-11-20
-- (Dev: "start improving monetization like where packs and stuff start to appear on
-- screen"): a block card slides down at the top centre like the top games' pop-up deals,
-- with the product's picture on spinning rays, a yellow title, one short line, a big green
-- Robux button and a shrinking timer bar. A nudge offer (Open) opens a window instead.
-- Leaves by itself after 12 s; never covers the ROLL button or the hotbar.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Buy = require(script.Parent.Parent.Buy)
local Ui = require(script.Parent.Parent.Ui)

local OfferController = {}

local SECONDS = 12
local SHOWN = UDim2.new(0.5, 0, 0, 8) -- just under the top bar, well above ROLL
local HIDDEN = UDim2.new(0.5, 0, 0, -220)
local CARD = Color3.fromRGB(150, 70, 230)

local C: any
local card: Frame
local picture: ImageLabel
local rays: ImageLabel
local title: TextLabel
local text: TextLabel
local buy: TextButton
local bar: Frame
local current: any = nil
local serial = 0

local function hide()
	serial += 1
	local mine = serial
	current = nil
	local t = TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = HIDDEN,
	})
	t:Play()
	t.Completed:Connect(function()
		if serial == mine then
			card.Visible = false
		end
	end)
end

local function onBuy()
	local offer = current
	if not offer then
		return
	end
	hide()
	Net.event("Analytics"):FireServer("Open", "Offer_" .. offer.Key)
	if offer.Open then
		local controller = C[offer.Open .. "Controller"]
		if controller and controller.Toggle then
			controller:Toggle()
		end
		return
	end
	task.spawn(Buy.prompt, offer.Product, nil, nil)
end

function OfferController:Init(controllers)
	C = controllers
	local gui = Ui.screen("Offer", 25)
	card = Ui.frame({
		Name = "Card",
		Size = UDim2.fromOffset(500, 172),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = HIDDEN,
		Visible = false,
	})
	Ui.block(card, CARD, 4, 6)
	Ui.autoScale(card)
	rays = Ui.icon("Rays", {
		Size = UDim2.fromOffset(190, 190),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 78, 0.5, -2),
		ImageTransparency = 0.45,
		ZIndex = 2,
	})
	rays.Parent = card
	picture = Ui.icon("Gift", {
		Name = "Picture",
		Size = UDim2.fromOffset(118, 118),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 78, 0.5, -2),
		ZIndex = 3,
	})
	picture.Parent = card
	title = Ui.label({
		Name = "Title",
		Size = UDim2.new(1, -220, 0, 40),
		Position = UDim2.fromOffset(150, 12),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 227, 77),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	title.Parent = card
	text = Ui.label({
		Name = "Text",
		Size = UDim2.new(1, -170, 0, 26),
		Position = UDim2.fromOffset(150, 54),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	text.Parent = card
	buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.Text = ""
	buy.AutoButtonColor = true
	buy.BorderSizePixel = 0
	buy.Size = UDim2.fromOffset(220, 56)
	buy.AnchorPoint = Vector2.new(0, 1)
	buy.Position = UDim2.new(0, 150, 1, -24)
	buy.ZIndex = 3
	Ui.block(buy, Color3.fromRGB(76, 209, 55), 3, 5)
	local label = Ui.label({
		Name = "Label",
		Size = UDim2.new(1, -12, 1, -10),
		Position = UDim2.fromOffset(6, 3),
		Text = "",
		ZIndex = 4,
	})
	label.Parent = buy
	buy.Activated:Connect(function()
		Ui.sound("Click")
		onBuy()
	end)
	buy.Parent = card
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = ""
	close.BorderSizePixel = 0
	close.Size = UDim2.fromOffset(42, 42)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 10)
	close.ZIndex = 4
	Ui.block(close, Ui.Colors.Red or Color3.fromRGB(235, 60, 60), 3, 4)
	Ui.label({
		Name = "Label",
		Size = UDim2.new(1, -10, 1, -10),
		Position = UDim2.fromOffset(5, 3),
		Text = "X",
		ZIndex = 5,
	}).Parent =
		close
	close.Activated:Connect(function()
		Ui.sound("Click")
		hide()
	end)
	close.Parent = card
	-- The time left, shrinking along the bottom.
	local track = Ui.frame({
		Name = "Timer",
		Size = UDim2.new(1, -24, 0, 8),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -9),
		BackgroundColor3 = Color3.fromRGB(40, 20, 70),
		ZIndex = 3,
	})
	bar = Ui.frame({
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 227, 77),
		ZIndex = 4,
	})
	bar.Parent = track
	track.Parent = card
	card.Parent = Ui.root(gui)
	RunService.RenderStepped:Connect(function(dt)
		if card.Visible then
			rays.Rotation = (rays.Rotation + dt * 35) % 360
		end
	end)
end

function OfferController:Start()
	Net.event("ShowOffer").OnClientEvent:Connect(function(offer)
		if offer.Key == "StarterPack" then
			C.StarterPackController:Open() -- its own big window
			return
		end
		serial += 1
		local mine = serial
		current = offer
		title.Text = offer.Title
		text.Text = offer.Text
		picture.Image = (offer.Pic and Ui.Images[offer.Pic]) or Ui.Images.Gift or ""
		if offer.Open then
			Ui.setText(buy, "OPEN")
			Ui.tint(buy, Color3.fromRGB(0, 170, 255))
		else
			Ui.setText(buy, `{Ui.ROBUX} {offer.Price or "?"}`)
			Ui.tint(buy, Color3.fromRGB(76, 209, 55))
		end
		card.Position = HIDDEN
		card.Visible = true
		TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = SHOWN,
		}):Play()
		picture.Rotation = -15
		TweenService:Create(picture, TweenInfo.new(0.6, Enum.EasingStyle.Elastic), { Rotation = 0 }):Play()
		bar.Size = UDim2.fromScale(1, 1)
		TweenService:Create(bar, TweenInfo.new(SECONDS, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) })
			:Play()
		Ui.sound("Pop")
		task.delay(SECONDS, function()
			if serial == mine then
				hide()
			end
		end)
	end)
end

return OfferController
