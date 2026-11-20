--!strict
-- After a roll (Dev 2026-11-20: like Throw Food For Animals): a result card at the bottom
-- centre (zone reached big in its colour, +cash, the eggs you found) and, for rare finds, a
-- tiered luck banner at the top: LUCKY! > SUPER LUCKY! > INSANE LUCK! > GODLY LUCK!! >
-- IMPOSSIBLE!!!. "tap to continue" closes it. Also the big flash words during a roll.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local L = require(Shared.Config.HudLayout)
local Zones = require(Shared.Config.Zones)
local Ui = require(script.Parent.Parent.Ui)

local ResultsController = {}

local gui: ScreenGui
local card: TextButton
local cardScale: UIScale
local tag: TextLabel
local zoneLabel: TextLabel
local cashLabel: TextLabel
local eggsRow: Frame
local banner: TextLabel
local bannerScale: UIScale
local flash: TextLabel
local flashScale: UIScale
local serial = 0

local TIERS = {
	{ Order = 3, Text = "LUCKY!", Color = Color3.fromRGB(255, 80, 80) },
	{ Order = 4, Text = "SUPER LUCKY!", Color = Color3.fromRGB(255, 110, 210) },
	{ Order = 5, Text = "INSANE LUCK!", Color = Color3.fromRGB(110, 235, 90) },
	{ Order = 6, Text = "GODLY LUCK!!", Color = Color3.fromRGB(255, 210, 50) },
	{ Order = 7, Text = "IMPOSSIBLE!!!", Color = Color3.fromRGB(190, 120, 255) },
}

function ResultsController:Flash(text: string, color: Color3)
	Ui.word(text, color)
end

local function close()
	card.Visible = false
	banner.Visible = false
end

function ResultsController:Close()
	serial += 1
	close()
end

function ResultsController:IsOpen(): boolean
	return card ~= nil and card.Visible
end

function ResultsController:Show(result)
	if not result then
		return
	end
	serial += 1
	local mine = serial
	local zone = Zones.List[result.Zone] or Zones.List[1]
	tag.Text = if result.Village then "VILLAGE!" elseif result.Record then "NEW BEST!" else ""
	tag.Visible = tag.Text ~= ""
	zoneLabel.Text = zone.Name
	zoneLabel.TextColor3 = zone.Color
	cashLabel.Text = "+" .. Format.cash(result.Cash)
	for _, c in eggsRow:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local best = 0
	for i, rarity in result.Eggs do
		local def = Eggs.ByName[rarity]
		best = math.max(best, def and def.Order or 0)
		if i <= 6 then
			local egg = Ui.icon(if def and def.Order >= 5 then "GoldenEgg" else "Egg", {
				Size = UDim2.fromOffset(52, 52),
				ImageColor3 = if def then Color3.new(1, 1, 1):Lerp(def.Color, 0.45) else Color3.new(1, 1, 1),
				LayoutOrder = i,
			})
			egg.Parent = eggsRow
		end
	end
	eggsRow.Visible = #result.Eggs > 0
	local tier = nil
	for _, t in TIERS do
		if best >= t.Order then
			tier = t
		end
	end
	task.delay(0.6, function()
		if serial ~= mine then
			return
		end
		card.Visible = true
		cardScale.Scale = 0.6
		TweenService:Create(cardScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		Ui.sound("Winner")
		Ui.sound("Cash")
		if tier then
			banner.Text = tier.Text
			banner.TextColor3 = tier.Color
			banner.Visible = true
			bannerScale.Scale = 0.3
			TweenService:Create(bannerScale, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		task.delay(6, function()
			if serial == mine then
				close()
			end
		end)
	end)
end

function ResultsController:Init()
	gui = Ui.screen("Results", 15)
	local root = Ui.root(gui)
	flash = Ui.label({
		Name = "Flash",
		Size = UDim2.fromOffset(600, 70),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Text = "",
		Visible = false,
	})
	flashScale = Instance.new("UIScale")
	flashScale.Parent = flash
	flash.Parent = root

	banner = Ui.label({
		Name = "Banner",
		Size = UDim2.fromOffset(700, 100),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 30),
		Text = "",
		Visible = false,
		ZIndex = 5,
	})
	local bs = banner:FindFirstChildOfClass("UIStroke")
	if bs then
		bs.Thickness = 5
	end
	bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner
	-- Screen-size scale on a holder (one UIScale per object), the pop scale on the banner.
	local bannerHolder = Ui.frame({
		Name = "BannerHolder",
		Size = UDim2.fromOffset(700, 100),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		BackgroundTransparency = 1,
	})
	Ui.autoScale(bannerHolder)
	bannerHolder.Parent = root
	banner.AnchorPoint = Vector2.new(0, 0)
	banner.Position = UDim2.fromOffset(0, 0)
	banner.Parent = bannerHolder

	-- The result card: a button, so a tap anywhere on it closes it.
	card = Instance.new("TextButton")
	card.Name = "Card"
	card.Text = ""
	card.AutoButtonColor = false
	card.BorderSizePixel = 0
	card.BackgroundColor3 = Ui.Colors.PanelDark
	local holder = Ui.frame({ Name = "CardHolder", BackgroundTransparency = 1 })
	holder.AnchorPoint = L.Result.Anchor
	holder.Position = L.Result.Pos
	holder.Size = UDim2.fromOffset(L.Result.Size.X, L.Result.Size.Y)
	Ui.autoScale(holder)
	holder.Parent = root
	card.Size = UDim2.fromScale(1, 1)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Visible = false
	Ui.corner(card, 18)
	Ui.stroke(card, 4)
	cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	card.Activated:Connect(function()
		Ui.sound("Click")
		close()
	end)
	card.Parent = holder
	tag = Ui.label({
		Name = "Tag",
		Size = UDim2.fromOffset(170, 44),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -40, 0, 4),
		Rotation = 12,
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.Colors.Yellow,
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 4,
	})
	Ui.corner(tag, 10)
	Ui.stroke(tag, 3)
	tag.Parent = card
	zoneLabel = Ui.label({
		Name = "Zone",
		Size = UDim2.new(1, -30, 0, 60),
		Position = UDim2.fromOffset(15, 16),
		Text = "",
	})
	zoneLabel.Parent = card
	local cashRow = Ui.frame({
		Name = "CashRow",
		Size = UDim2.fromOffset(300, 56),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		BackgroundTransparency = 1,
	})
	Ui.icon("Cash", { Size = UDim2.fromOffset(56, 56) }).Parent = cashRow
	cashLabel = Ui.label({
		Name = "Value",
		Size = UDim2.new(1, -64, 1, -6),
		Position = UDim2.fromOffset(64, 3),
		Text = "",
		TextColor3 = Color3.fromRGB(110, 235, 90),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	cashLabel.Parent = cashRow
	cashRow.Parent = card
	eggsRow = Ui.frame({
		Name = "Eggs",
		Size = UDim2.new(1, -30, 0, 56),
		Position = UDim2.fromOffset(15, 142),
		BackgroundTransparency = 1,
	})
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.Parent = eggsRow
	eggsRow.Parent = card
	Ui.label({
		Name = "Continue",
		Size = UDim2.new(1, -30, 0, 26),
		Position = UDim2.new(0, 15, 1, -36),
		Text = "tap to continue",
		TextColor3 = Color3.fromRGB(190, 200, 230),
	}).Parent =
		card
end

return ResultsController
