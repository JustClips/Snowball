--!strict
-- Your bag, like Sweep the World / Steal an Egg: eggs and pets that aren't out in your
-- base live here. Two parts:
--   Hotbar (bottom right, HudLayout.Hotbar): your best egg stacks and pets as big 3D
--     slots, 4 on PC / 3 on phones, keys 1-4. Tap one to carry it (tap again to put it
--     away), then click or tap a spot in your base to put it down (PlacementController).
--     The last slot opens the bag.
--   Bag window (the Bag slot, the Pets tile on the left rail, B or `): every egg stack and
--     pet in a grid of 3D tiles, name in its rarity colour, weight / count under it. Tap a
--     tile to carry it. BEST lets your best pets out; the top shows pets out / room.
-- Pets in your base aren't in the bag: walk up to one and press Pick Up to carry it again.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggLook = require(Shared.EggLook)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local L = require(Shared.Config.HudLayout)
local Net = require(Shared.Net)
local PetLook = require(Shared.PetLook)
local PetStats = require(Shared.PetStats)
local World = require(Shared.Config.World)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local InventoryController = {}

local C: any
local gui: ScreenGui
local hotbar: Frame
local bagButton: TextButton
local window: Frame
local grid: ScrollingFrame
local petsCount: TextLabel
local eggsCount: TextLabel
local empty: TextLabel

export type Item = {
	key: string, -- "Egg:<Rarity>" or "Pet:<uid>"
	kind: string, -- "Egg" | "Pet"
	id: string, -- rarity or uid
	count: number,
	order: number, -- rarity order (bigger = rarer)
	value: number, -- pets: $/s, eggs: rarity
	pet: any?,
}

local slots: { TextButton } = {}
local slotItems: { Item? } = {}
local shownKeys = ""
local bagKeys = ""
local seen: { [string]: boolean } = {} -- items you've seen in the bag (new = badge)
local seenReady = false

local function rarityColor(name: string): Color3
	local r = Eggs.ByName[name]
	return if r then r.Color else Color3.new(1, 1, 1)
end

-- Secret is near-black: its text gets a rainbow instead.
local function colorText(label: TextLabel, rarity: string)
	local old = label:FindFirstChild("Rainbow")
	if old then
		old:Destroy()
	end
	if rarity == "Secret" then
		label.TextColor3 = Color3.new(1, 1, 1)
		local g = Instance.new("UIGradient")
		g.Name = "Rainbow"
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 90, 255)),
		})
		g.Parent = label
	else
		label.TextColor3 = rarityColor(rarity)
	end
end
InventoryController.colorText = colorText

-- Everything in the bag, best first: egg stacks (rarest first), then pets by $/s.
function InventoryController:Items(): { Item }
	local data = State.data
	local list: { Item } = {}
	if not data then
		return list
	end
	local stacks: { [string]: number } = {}
	for _, egg in data.Eggs or {} do
		stacks[egg.Rarity] = (stacks[egg.Rarity] or 0) + 1
	end
	for rarity, n in stacks do
		local def = Eggs.ByName[rarity]
		local order = def and def.Order or 0
		table.insert(list, {
			key = "Egg:" .. rarity,
			kind = "Egg",
			id = rarity,
			count = n,
			order = order,
			value = 1e12 + order,
		})
	end
	for uid, pet in data.Pets or {} do
		if not pet.Placed then
			local def = Eggs.ByName[PetStats.rarity(pet)]
			table.insert(list, {
				key = "Pet:" .. uid,
				kind = "Pet",
				id = uid,
				count = 1,
				order = def and def.Order or 0,
				value = PetStats.income(pet),
				pet = pet,
			})
		end
	end
	table.sort(list, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.key < b.key
	end)
	return list
end

-- A 3D look of an item in a ViewportFrame (turned a little to the side).
local function viewport(parent: GuiObject, item: Item, size: UDim2, pos: UDim2)
	local old = parent:FindFirstChild("View")
	if old then
		old:Destroy()
	end
	local vp = Instance.new("ViewportFrame")
	vp.Name = "View"
	vp.BackgroundTransparency = 1
	vp.Size = size
	vp.Position = pos
	vp.Ambient = Color3.fromRGB(190, 195, 210)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = Vector3.new(-1, -1, -0.6)
	vp.ZIndex = 2
	local model: Model?
	if item.kind == "Egg" then
		model = EggLook.make(item.id)
	elseif item.pet then
		model = PetLook.make(item.pet.Id, item.pet.Mutation, item.pet.Huge)
	end
	if model then
		model:PivotTo(CFrame.Angles(0, math.rad(200), 0))
		model.Parent = vp
		local cam = Instance.new("Camera")
		local box, sz = model:GetBoundingBox()
		local d = math.max(sz.X, sz.Y, sz.Z) * 1.35 + 0.8
		local target = box.Position
		cam.FieldOfView = 38
		cam.CFrame = CFrame.lookAt(target + Vector3.new(0, sz.Y * 0.15, -d * 1.4), target)
		cam.Parent = vp
		vp.CurrentCamera = cam
	end
	vp.Parent = parent
end

local function held(): string?
	return if C.PlacementController then C.PlacementController:HeldKey() else nil
end

-- Carry an item, or put it away when it's already in your hands.
function InventoryController:Use(item: Item)
	if held() == item.key then
		C.PlacementController:Stop()
	else
		C.PlacementController:Hold(item.kind, item.id)
	end
end

-------------------------------------------------------------------------- hotbar

local function slotCount(): number
	return if Ui.isPhone() then 3 else 4
end

local function makeSlot(i: number): TextButton
	local s = L.Slot
	local b = Instance.new("TextButton")
	b.Name = "Slot" .. i
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(s, s)
	b.BackgroundColor3 = Ui.Colors.PanelDark
	b.BackgroundTransparency = 0.15
	b.LayoutOrder = i
	Ui.corner(b, 14)
	local stroke = Ui.stroke(b, 3)
	stroke.Name = "Edge"
	local key = Ui.label({
		Name = "Key",
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.fromOffset(4, 2),
		Text = tostring(i),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	key.Visible = not UserInputService.TouchEnabled
	key.Parent = b
	local count = Ui.label({
		Name = "Count",
		Size = UDim2.new(1, -6, 0, 22),
		Position = UDim2.new(0, 3, 1, -24),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	})
	count.Parent = b
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.Activated:Connect(function()
		local item = slotItems[i]
		if item then
			Ui.sound("Click")
			scale.Scale = 0.88
			game:GetService("TweenService")
				:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 })
				:Play()
			InventoryController:Use(item)
		end
	end)
	return b
end

local function renderHotbar(items: { Item })
	local n = slotCount()
	local list = {}
	for i = 1, n do
		list[i] = items[i]
	end
	local keys = {}
	for i = 1, n do
		local it = list[i]
		keys[i] = if it then `{it.key}x{it.count}` else "-"
	end
	local heldKey = held()
	local sig = table.concat(keys, ",") .. "|" .. tostring(n)
	if sig ~= shownKeys then
		shownKeys = sig
		for i, b in slots do
			b.Visible = i <= n
			local item = list[i]
			slotItems[i] = item
			local view = b:FindFirstChild("View")
			if view then
				view:Destroy()
			end
			local count = b:FindFirstChild("Count") :: TextLabel
			if item then
				viewport(b, item, UDim2.new(1, -6, 1, -6), UDim2.fromOffset(3, 3))
				count.Text = if item.kind == "Egg" then `x{item.count}` else ""
			else
				count.Text = ""
			end
		end
	end
	for i, b in slots do
		local item = slotItems[i]
		local edge = b:FindFirstChild("Edge") :: UIStroke
		local on = item ~= nil and item.key == heldKey
		edge.Color = if on
			then Ui.Colors.Green
			elseif item then rarityColor(if item.kind == "Egg" then item.id else PetStats.rarity(item.pet))
			else Ui.Colors.Ink
		edge.Thickness = if on then 5 else 3
		b.BackgroundColor3 = if on then Color3.fromRGB(40, 90, 60) else Ui.Colors.PanelDark
	end
end

-------------------------------------------------------------------------- bag window

local function tile(item: Item, i: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = item.key
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.LayoutOrder = i
	local rarity = if item.kind == "Egg" then item.id else PetStats.rarity(item.pet)
	local color = rarityColor(rarity)
	b.BackgroundColor3 = color:Lerp(Ui.Colors.PanelDark, 0.6)
	Ui.corner(b, 14)
	Ui.gradient(b, b.BackgroundColor3)
	local edge = Ui.stroke(b, 3, color)
	edge.Name = "Edge"
	viewport(b, item, UDim2.new(1, -8, 1, -44), UDim2.fromOffset(4, 4))
	local name = Ui.label({
		Name = "Name",
		Size = UDim2.new(1, -8, 0, 20),
		Position = UDim2.new(0, 4, 1, -42),
		Text = if item.kind == "Egg" then `{rarity} Egg` else PetStats.name(item.pet),
		ZIndex = 3,
	})
	colorText(name, rarity)
	name.Parent = b
	local sub = Ui.label({
		Name = "Sub",
		Size = UDim2.new(1, -8, 0, 18),
		Position = UDim2.new(0, 4, 1, -22),
		Text = if item.kind == "Egg" then `x{item.count}` else PetStats.kgText(item.pet.Weight),
		TextColor3 = Ui.Colors.Snow,
		ZIndex = 3,
	})
	sub.Parent = b
	if item.kind == "Pet" then
		local cash = Ui.label({
			Name = "Cash",
			Size = UDim2.new(1, -10, 0, 18),
			Position = UDim2.fromOffset(5, 4),
			Text = `{Format.cash(item.value)}/s`,
			TextColor3 = Ui.Colors.Green,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 3,
		})
		cash.Parent = b
	end
	if seenReady and not seen[item.key] then
		local new = Ui.label({
			Name = "New",
			Size = UDim2.fromOffset(46, 22),
			Position = UDim2.fromOffset(2, 2),
			Rotation = -12,
			Text = "NEW!",
			TextColor3 = Ui.Colors.Yellow,
			ZIndex = 5,
		})
		new.Parent = b
	end
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.Activated:Connect(function()
		Ui.sound("Click")
		InventoryController:Use(item)
		Ui.closeWindow(window)
	end)
	b.MouseEnter:Connect(function()
		scale.Scale = 1.05
	end)
	b.MouseLeave:Connect(function()
		scale.Scale = 1
	end)
	return b
end

local function renderBag(items: { Item })
	local data = State.data
	if not data or not window.Visible then
		return
	end
	local placed, slotsN = 0, data.PetSlots or 6
	for _, pet in data.Pets or {} do
		if pet.Placed then
			placed += 1
		end
	end
	if data.Gamepasses and data.Gamepasses.ExtraSlots then
		slotsN += 4
	end
	slotsN = math.min(slotsN, World.PetSpotsMax + 4)
	petsCount.Text = `{placed}/{slotsN}`
	eggsCount.Text = `{#(data.Hatching or {})}/{World.HatchSpots}`
	local keys = {}
	for _, it in items do
		table.insert(keys, `{it.key}x{it.count}`)
	end
	local sig = table.concat(keys, ",")
	if sig == bagKeys then
		return
	end
	bagKeys = sig
	for _, child in grid:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for i, item in items do
		tile(item, i).Parent = grid
	end
	empty.Visible = #items == 0
end

local function markSeen(items: { Item })
	for _, it in items do
		seen[it.key] = true
	end
	seenReady = true
end

local function newCount(items: { Item }): number
	if not seenReady then
		return 0
	end
	local n = 0
	for _, it in items do
		if not seen[it.key] then
			n += 1
		end
	end
	return n
end

function InventoryController:Toggle()
	if window.Visible then
		Ui.closeWindow(window)
		markSeen(InventoryController:Items())
	else
		bagKeys = ""
		Ui.openWindow(window)
		Net.event("Analytics"):FireServer("Open", "Bag")
		renderBag(InventoryController:Items())
		markSeen(InventoryController:Items())
	end
end

function InventoryController:Refresh()
	local items = InventoryController:Items()
	renderHotbar(items)
	renderBag(items)
	Ui.badge(bagButton, newCount(items))
end

function InventoryController:Init(controllers)
	C = controllers
	gui = Ui.screen("Bag", 12)

	-- Hotbar.
	hotbar = Ui.frame({ Name = "Hotbar", BackgroundTransparency = 1 })
	hotbar.AnchorPoint = L.Hotbar.Anchor
	hotbar.Position = L.Hotbar.Pos
	hotbar.Size = UDim2.fromOffset(L.Hotbar.Size.X, L.Hotbar.Size.Y)
	Ui.autoScale(hotbar)
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Right
	row.VerticalAlignment = Enum.VerticalAlignment.Bottom
	row.Padding = UDim.new(0, 8)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = hotbar
	for i = 1, 4 do
		local b = makeSlot(i)
		b.Parent = hotbar
		slots[i] = b
	end
	bagButton = Ui.tile("Bag", "Chest", "Bag", Ui.Colors.Orange, function()
		InventoryController:Toggle()
	end, L.Slot)
	bagButton.LayoutOrder = 10
	-- The tile's word hangs under it; keep the bar's bottom edge on the slots.
	local word = bagButton:FindFirstChild("Label") :: TextLabel?
	if word then
		word.Visible = false
	end
	bagButton.Parent = hotbar
	hotbar.Parent = gui

	-- Bag window.
	local body
	window, body = Ui.window(gui, "BagWindow", "BAG", Vector2.new(660, 500))
	local top = Ui.frame({ Name = "Top", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56) })
	Ui.icon("Pets", { Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(0, 4) }).Parent = top
	petsCount = Ui.label({
		Size = UDim2.fromOffset(90, 36),
		Position = UDim2.fromOffset(52, 10),
		Text = "0/6",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	petsCount.Parent = top
	Ui.icon("Egg", { Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(150, 4) }).Parent = top
	eggsCount = Ui.label({
		Size = UDim2.fromOffset(90, 36),
		Position = UDim2.fromOffset(202, 10),
		Text = "0/4",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	eggsCount.Parent = top
	local best = Ui.bigButton("Best", "Star", "BEST", Ui.Colors.Orange, function()
		local ok, why = Net.func("Pets"):InvokeServer("Best")
		if not ok and why then
			Ui.toast(why, "Bad")
		end
	end, Vector2.new(170, 50))
	best.AnchorPoint = Vector2.new(1, 0)
	best.Position = UDim2.new(1, -4, 0, 3)
	best.Parent = top
	top.Parent = body

	grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Size = UDim2.new(1, 0, 1, -64)
	grid.Position = UDim2.fromOffset(0, 64)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(116, 140)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 4)
	pad.Parent = grid
	grid.Parent = body
	empty = Ui.label({
		Name = "Empty",
		Size = UDim2.new(1, -40, 0, 40),
		Position = UDim2.new(0, 20, 0.5, -20),
		Text = "Roll to find eggs!",
		TextColor3 = Ui.Colors.Ice,
		Visible = false,
	})
	empty.Parent = body
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if not window.Visible then
			markSeen(InventoryController:Items())
			InventoryController:Refresh()
		end
	end)
end

function InventoryController:Start()
	State.observe(function()
		if not seenReady and State.data and State.data.Pets then
			markSeen(InventoryController:Items()) -- what you join with isn't "new"
		end
		InventoryController:Refresh()
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.B or k == Enum.KeyCode.Backquote then
			InventoryController:Toggle()
			return
		end
		local nums = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
		for i, code in nums do
			if k == code and slots[i].Visible and slotItems[i] then
				InventoryController:Use(slotItems[i] :: Item)
			end
		end
	end)
	-- Only in the open world (not while training, packing or rolling).
	task.spawn(function()
		while true do
			local mode = C.HudController:Mode()
			hotbar.Visible = mode == "Normal"
			if mode ~= "Normal" and window.Visible then
				Ui.closeWindow(window)
			end
			task.wait(0.2)
		end
	end)
end

return InventoryController
