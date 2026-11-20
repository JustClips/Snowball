--!strict
-- The Upgrades window (GAME_PLAN §5.8, §7 item 10): the next Snow Roller, the next Robux
-- roller, Snowball Core, Egg Slots, Pet Slots and Pack Zone, one card each with a big BUY.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Rollers = require(Shared.Config.Rollers)
local Upgrades = require(Shared.Config.Upgrades)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local UpgradesController = {}

local window: Frame
local cards: { [string]: { title: TextLabel, info: TextLabel, buy: TextButton } } = {}

local ICONS = {
	Roller = "Power",
	RobuxRoller = "Robux",
	Core = "Gem",
	EggSlots = "Egg",
	PetSlots = "Pets",
	PackZone = "Target",
}

-- One upgrade: big icon, short name, what it gives as icon + number, a big price button.
local function card(parent: Frame, id: string, order: number, onBuy: () -> ())
	local f = Ui.frame({
		Name = id,
		Size = UDim2.new(1, -8, 0, 92),
		BackgroundColor3 = Ui.Colors.PanelDark,
		LayoutOrder = order,
	})
	-- The Ultra pack's upgrade row: dark row, the picture in a darker square, name + what
	-- it gives, a big price button on the right.
	Ui.stroke(f, 3)
	local well = Ui.frame({
		Name = "Well",
		Size = UDim2.fromOffset(76, 76),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Ui.Colors.Ink,
		BackgroundTransparency = 0.3,
	})
	well.Parent = f
	Ui.icon(ICONS[id] or "Upgrade", {
		Size = UDim2.fromOffset(66, 66),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	}).Parent =
		well
	local title = Ui.label({
		Name = "Title",
		Size = UDim2.new(1, -270, 0, 38),
		Position = UDim2.fromOffset(96, 10),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = id,
	})
	title.Parent = f
	local info = Ui.label({
		Name = "Info",
		Size = UDim2.new(1, -270, 0, 28),
		Position = UDim2.fromOffset(96, 52),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		TextColor3 = Ui.Colors.Green,
	})
	info.Parent = f
	local buy = Ui.button({
		Name = "Buy",
		Size = UDim2.fromOffset(160, 70),
		Position = UDim2.new(1, -170, 0, 11),
		BackgroundColor3 = Ui.Colors.Green,
	}, "BUY", onBuy)
	buy.Parent = f
	f.Parent = parent
	cards[id] = { title = title, info = info, buy = buy }
end

local function invoke(name: string, ...: any)
	local ok, why = Net.func(name):InvokeServer(...)
	if not ok and why then
		Ui.toast(why, "Bad")
	end
end

local function render(data)
	local nextRoller = Rollers.get(data.Roller + 1)
	local c = cards.Roller
	if nextRoller then
		local free = nextRoller.Index == Rollers.FreeInTutorial and not data.Flags.TutorialDone
		c.title.Text = nextRoller.Name
		c.info.Text = `+{Format.big(nextRoller.Power)}`
		Ui.setText(c.buy, if free then "FREE" else Format.cash(nextRoller.Price))
		c.buy.Visible = true
	else
		c.title.Text = "Best roller owned"
		c.info.Text = ""
		c.buy.Visible = false
	end
	local robux = Rollers.nextRobux(data.RobuxRollers)
	local product = robux and Products.ProductByKey[robux.Product]
	c = cards.RobuxRoller
	if robux and product then
		c.title.Text = robux.Name
		c.info.Text = `x{robux.Mult}`
		Ui.setText(c.buy, `{Ui.ROBUX}{product.Price}`)
		Ui.tint(c.buy, Ui.Colors.Purple) -- Robux buys are purple (Ultra pack)
		c.buy.Visible = product.Id ~= 0
	else
		c.title.Text = "All Robux rollers owned"
		c.info.Text = ""
		c.buy.Visible = false
	end
	local core = Upgrades.Cores[data.Core + 1]
	c = cards.Core
	c.title.Text = if core then core.Name else "Best core owned"
	c.info.Text = if core then `x{core.Luck}` else ""
	local rows = {
		{ "Core", Upgrades.nextPrice("Core", data) },
		{ "EggSlots", Upgrades.nextPrice("EggSlots", data) },
		{ "PetSlots", Upgrades.nextPrice("PetSlots", data) },
		{ "PackZone", Upgrades.nextPrice("PackZone", data) },
	}
	cards.EggSlots.title.Text = `Eggs {data.EggSlots}`
	cards.EggSlots.info.Text = "+1"
	cards.PetSlots.title.Text = `Pets {data.PetSlots}`
	cards.PetSlots.info.Text = "+1"
	cards.PackZone.title.Text = `Aim Lv {data.PackZone}`
	cards.PackZone.info.Text = "+1"
	for _, row in rows do
		local price = row[2]
		local cc = cards[row[1]]
		Ui.setText(cc.buy, if price then Format.cash(price) else "MAX")
		cc.buy.Visible = price ~= nil
	end
end

function UpgradesController:Toggle()
	if window.Visible then
		Ui.closeWindow(window)
	else
		Ui.openWindow(window)
		Net.event("Analytics"):FireServer("Open", "Upgrades")
	end
end

function UpgradesController:Init()
	local gui = Ui.screen("Upgrades", 20)
	local body
	window, body = Ui.window(gui, "Window", "UPGRADES", Vector2.new(560, 560), {
		Icon = "Upgrade",
		Color = Ui.Colors.Green,
	})
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	list.Parent = body
	card(list :: any, "Roller", 1, function()
		invoke("BuyRoller")
	end)
	card(list :: any, "RobuxRoller", 2, function()
		local robux = State.data and Rollers.nextRobux(State.data.RobuxRollers)
		if robux then
			invoke("PromptPurchase", robux.Product)
		end
	end)
	card(list :: any, "Core", 3, function()
		invoke("BuyUpgrade", "Core")
	end)
	card(list :: any, "EggSlots", 4, function()
		invoke("BuyUpgrade", "EggSlots")
	end)
	card(list :: any, "PetSlots", 5, function()
		invoke("BuyUpgrade", "PetSlots")
	end)
	card(list :: any, "PackZone", 6, function()
		invoke("BuyUpgrade", "PackZone")
	end)
end

function UpgradesController:Start()
	State.observe(render)
end

return UpgradesController
