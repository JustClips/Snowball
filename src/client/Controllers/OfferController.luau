--!strict
-- The offer popup (GAME_PLAN §7 item 19): one template for every contextual offer the
-- server sends (OfferService). BUY opens the product prompt; a nudge offer (Open) opens
-- a window instead. Closes itself after 12 s.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Ui = require(script.Parent.Parent.Ui)

local OfferController = {}

local C: any
local popup: Frame
local title: TextLabel
local text: TextLabel
local buy: TextButton
local current: any = nil
local shownAt = 0

local function hide()
	popup.Visible = false
	current = nil
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
	local ok, why = Net.func("PromptPurchase"):InvokeServer(offer.Product)
	if not ok and why then
		Ui.toast(why, "Bad")
	end
end

function OfferController:Init(controllers)
	C = controllers
	local gui = Ui.screen("Offer", 25)
	popup = Ui.frame({
		Name = "Popup",
		Size = UDim2.fromOffset(420, 220),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		BackgroundColor3 = Ui.Colors.Panel,
		Visible = false,
	})
	Ui.stroke(popup, 4, Ui.Colors.Gold)
	Ui.autoScale(popup)
	title = Ui.label({
		Name = "Title",
		Size = UDim2.new(1, -70, 0, 44),
		Position = UDim2.fromOffset(12, 8),
		Text = "",
		TextColor3 = Ui.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	title.Parent = popup
	text = Ui.label({
		Name = "Text",
		Size = UDim2.new(1, -24, 0, 70),
		Position = UDim2.fromOffset(12, 56),
		Text = "",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	text.Parent = popup
	buy = Ui.button({
		Name = "Buy",
		Size = UDim2.fromOffset(240, 64),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		BackgroundColor3 = Ui.Colors.Robux,
	}, "BUY", onBuy)
	buy.Parent = popup
	Ui.button({
		Name = "Close",
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.new(1, -52, 0, 8),
		BackgroundColor3 = Ui.Colors.Red,
	}, "X", hide).Parent =
		popup
	popup.Parent = Ui.root(gui)
end

function OfferController:Start()
	Net.event("ShowOffer").OnClientEvent:Connect(function(offer)
		current = offer
		title.Text = offer.Title
		text.Text = offer.Text
		if offer.Open then
			Ui.setText(buy, "OPEN")
			buy.BackgroundColor3 = Ui.Colors.Green
		else
			Ui.setText(buy, `BUY {Ui.ROBUX}{offer.Price or "?"}`)
			buy.BackgroundColor3 = Ui.Colors.Robux
		end
		popup.Visible = true
		Ui.sound("Pop")
		local at = os.clock()
		shownAt = at
		task.delay(12, function()
			if shownAt == at and current == offer then
				hide()
			end
		end)
	end)
end

return OfferController
