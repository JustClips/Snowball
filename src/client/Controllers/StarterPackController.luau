--!strict
-- The Starter Pack (DIRECTION.md: a tiny first purchase, early). Pops a few seconds after
-- the tutorial ends (OfferService sends ShowOffer "StarterPack"), then once per session on
-- later joins while it's still for sale. A chest tile on the HUD's right rail shows the
-- real countdown (it leaves 2 h after the first join or at the Ice Cave) and reopens it.
-- Pictures, not sentences: four item tiles with one short caption each, a "-92%" pill
-- worked out from what the items cost on their own, and one big green Robux button.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Buy = require(script.Parent.Parent.Buy)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local StarterPackController = {}

local C: any
local window: Frame
local timerText: TextLabel
local buy: TextButton
local buyScale: UIScale
local tile: TextButton? = nil
local tileWord: TextLabel? = nil
local live = false
local serial = 0

local GOLD = Color3.fromRGB(255, 210, 60)

-- What the pack's items cost when bought on their own (Shop prices), for the -x% pill.
local function worth(): number
	local pack = Economy.StarterPack
	local byKey = Products.ProductByKey
	local total = 0
	if byKey.LuckyRoll3 then
		total += byKey.LuckyRoll3.Price * pack.LuckyRolls / 3
	end
	if byKey.Train2xBoost then
		total += byKey.Train2xBoost.Price * pack.Train2xMinutes / byKey.Train2xBoost.Minutes
	end
	if byKey.FrozenEgg1 then
		total += byKey.FrozenEgg1.Price
	end
	return math.floor(total)
end

local function itemTile(order: number, icon: string, caption: string, color: Color3): Frame
	local cell = Ui.frame({ Name = "Item" .. order, LayoutOrder = order, BackgroundTransparency = 1 })
	local box = Ui.frame({
		Name = "Box",
		Size = UDim2.new(1, 0, 1, -34),
		BackgroundColor3 = color,
	})
	Ui.corner(box, 18)
	Ui.gradient(box)
	Ui.stroke(box, 3)
	box.Parent = cell
	-- Soft light behind the picture.
	local glow = Ui.frame({
		Name = "Glow",
		Size = UDim2.fromScale(0.8, 0.8),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.75,
	})
	Ui.corner(glow, 60)
	glow.Parent = box
	Ui.icon(icon, {
		Size = UDim2.new(1, -16, 1, -16),
		Position = UDim2.fromOffset(8, 8),
		ZIndex = 2,
	}).Parent =
		box
	Ui.label({
		Name = "Caption",
		Size = UDim2.new(1, 10, 0, 32),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Text = caption,
		ZIndex = 3,
	}).Parent =
		cell
	return cell
end

local function close()
	serial += 1
	Ui.closeWindow(window)
end

local function onBuy()
	task.spawn(Buy.prompt, "StarterPack", nil, window)
end

function StarterPackController:Open()
	if not live then
		return
	end
	serial += 1
	local mine = serial
	Ui.openWindow(window)
	Net.event("Analytics"):FireServer("Open", "StarterPack")
	Ui.sound("Pop")
	task.spawn(function()
		while serial == mine and window.Visible do
			TweenService:Create(buyScale, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { Scale = 1.07 }):Play()
			task.wait(0.4)
			TweenService:Create(buyScale, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
			task.wait(0.5)
		end
	end)
end

function StarterPackController:IsLive(): boolean
	return live
end

local function refresh()
	local data = State.data
	if not data then
		return
	end
	local now = State.now()
	live = Economy.starterPackLive(data, now)
	local left = if live then data.Flags.StarterPackEnds - now else 0
	if tile then
		(tile.Parent :: Frame).Visible = live
	end
	if tileWord then
		tileWord.Text = Format.countdown(left)
	end
	timerText.Text = Format.countdown(left)
	if not live and window.Visible then
		close()
	end
end

function StarterPackController:Init(controllers)
	C = controllers
	local gui = Ui.screen("StarterPack", 26)
	local body
	window, body = Ui.window(gui, "Window", "STARTER PACK", Vector2.new(640, 430))
	-- Swap the window's plain header colour for the offer red/orange.
	local header = window:FindFirstChild("Header") :: Frame
	for _, g in header:GetDescendants() do
		if g:IsA("UIGradient") then
			g.Color = ColorSequence.new(Color3.fromRGB(255, 90, 70), Color3.fromRGB(255, 150, 40))
		end
	end
	local hg = header:FindFirstChildOfClass("UIGradient")
	if hg then
		hg.Color = ColorSequence.new(Color3.fromRGB(255, 90, 70), Color3.fromRGB(255, 150, 40))
	end

	-- Top row: a tilted ONCE! tag and the timer pill.
	local tag = Ui.label({
		Name = "Once",
		Size = UDim2.fromOffset(120, 40),
		Position = UDim2.fromOffset(4, 4),
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.Colors.Red,
		Text = "ONCE!",
	})
	Ui.corner(tag, 10)
	tag.Parent = body
	local pill = Ui.frame({
		Name = "TimerPill",
		Size = UDim2.fromOffset(200, 40),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		BackgroundColor3 = Color3.fromRGB(12, 14, 34),
	})
	Ui.corner(pill, 20)
	Ui.stroke(pill, 3)
	Ui.icon("Clock", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(2, 0), ZIndex = 2 }).Parent = pill
	timerText = Ui.label({
		Name = "Timer",
		Size = UDim2.new(1, -54, 1, -8),
		Position = UDim2.fromOffset(46, 4),
		Text = "",
		TextColor3 = GOLD,
		ZIndex = 2,
	})
	timerText.Parent = pill
	pill.Parent = body

	-- What's inside: four big pictures, one short caption each.
	local pack = Economy.StarterPack
	local items = Ui.frame({
		Name = "Items",
		Size = UDim2.new(1, 0, 0, 172),
		Position = UDim2.fromOffset(0, 56),
		BackgroundTransparency = 1,
	})
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(138, 172)
	grid.CellPadding = UDim2.fromOffset(12, 0)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = items
	itemTile(1, "Shop_StarterRoller", "ROLLER", Color3.fromRGB(150, 160, 180)).Parent = items
	itemTile(2, "Shop_EpicEgg", string.upper(pack.EggRarity), Color3.fromRGB(170, 90, 255)).Parent = items
	itemTile(3, "Shop_Lucky3", `x{pack.LuckyRolls}`, Color3.fromRGB(70, 200, 90)).Parent = items
	itemTile(4, "Shop_Pass2xPower", `2x {pack.Train2xMinutes}m`, Color3.fromRGB(255, 160, 40)).Parent = items
	items.Parent = body

	-- Buy: a -x% pill and the big green button.
	local price = Products.ProductByKey.StarterPack.Price
	local value = worth()
	local holder = Ui.frame({
		Name = "BuyHolder",
		Size = UDim2.fromOffset(300, 84),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		BackgroundTransparency = 1,
	})
	buyScale = Instance.new("UIScale")
	buyScale.Parent = holder
	buy = Ui.bigButton("Buy", nil, `{Ui.ROBUX}{price}`, Ui.Colors.Green, onBuy, Vector2.new(300, 84))
	buy.Parent = holder
	if value > price then
		local save = Ui.label({
			Name = "Save",
			Size = UDim2.fromOffset(96, 38),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, 0, 0, 2),
			BackgroundTransparency = 0,
			BackgroundColor3 = Ui.Colors.Red,
			Text = `-{math.floor((1 - price / value) * 100)}%`,
			ZIndex = 5,
		})
		Ui.corner(save, 10)
		Ui.stroke(save, 3)
		save.Parent = holder
	end
	holder.Parent = body

	-- HUD tile (right rail): chest + the countdown as its word.
	local t = C.HudController:AddTile("Starter", "Chest", "", Color3.fromRGB(255, 110, 60), 9, function()
		StarterPackController:Open()
	end)
	tile = t;
	(t.Parent :: Frame).Visible = false
	tileWord = t:FindFirstChild("Label") :: TextLabel?
	if tileWord then
		tileWord.TextColor3 = GOLD
	end
end

function StarterPackController:Start()
	State.observe(function()
		refresh()
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)
	Net.event("Purchased").OnClientEvent:Connect(function(key)
		if key == "StarterPack" then
			close()
		end
	end)
end

return StarterPackController
