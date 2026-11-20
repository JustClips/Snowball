--!strict
-- The Pets window, icon first: egg bag + PLACE / OPEN / BEST tiles on top, then a grid of
-- pet cards with a 3D preview in the rarity colour (check = following, house = on base).
-- Tap a card: FOLLOW (boosts training) / TO BASE (earns cash) tiles for that pet.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local PetLook = require(Shared.PetLook)
local Net = require(Shared.Net)
local Pets = require(Shared.Config.Pets)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local PetsController = {}

local window: Frame
local list: ScrollingFrame
local eggCountLabel: TextLabel
local placeTile: TextButton
local openTile: TextButton
local actions: Frame
local actName: TextLabel
local actTrain: TextLabel
local actIncome: TextLabel
local followTile: TextButton
local baseTile: TextButton
local rows: { GuiObject } = {}
local shownVersion = -1

local function act(action: string, arg: any?)
	local ok, why = Net.func("Pets"):InvokeServer(action, arg)
	if not ok and why then
		Ui.toast(why, "Bad")
	end
end

-- A pet's 3D preview in a ViewportFrame.
local function preview(parent: GuiObject, pet)
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Preview"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.new(1, -8, 1, -30)
	vp.Position = UDim2.fromOffset(4, 4)
	vp.Ambient = Color3.fromRGB(200, 200, 210)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	local model = PetLook.make(pet.Id, pet.Mutation, pet.Huge)
	if model then
		model:PivotTo(CFrame.new())
		model.Parent = vp
		local cam = Instance.new("Camera")
		local _, size = model:GetBoundingBox()
		local d = math.max(size.X, size.Y, size.Z) * 1.5 + 1.5
		cam.CFrame = CFrame.lookAt(Vector3.new(d * 0.45, size.Y * 0.75, -d), Vector3.new(0, size.Y / 2, 0))
		cam.FieldOfView = 40
		cam.Parent = vp
		vp.CurrentCamera = cam
	end
	vp.Parent = parent
end

-- Tapping a card shows two big icon tiles for that pet: follow me / put on base.
local selected: string? = nil
local function select(uid: string?)
	selected = uid
	local data = State.data
	local pet = uid and data and data.Pets[uid]
	actions.Visible = pet ~= nil
	if not pet then
		return
	end
	local def = Pets.ById[pet.Id]
	actName.Text = (if pet.Huge then "Huge " else "") .. (if pet.Mutation then pet.Mutation .. " " else "") .. (def and def.Name or pet.Id)
	actName.TextColor3 = if def then Eggs.ByName[def.Rarity].Color else Ui.Colors.Snow
	actTrain.Text = if def then `+{math.floor(def.Train * 100)}%` else ""
	actIncome.Text = if def then Format.cash(def.Income) .. "/s" else ""
	Ui.setText(followTile, if pet.Equipped then "UNFOLLOW" else "FOLLOW")
	Ui.setText(baseTile, if pet.Placed then "TO BAG" else "TO BASE")
end

local function render(data)
	if not window.Visible then
		shownVersion = -1
		return
	end
	local eggCount, ready = 0, 0
	for _ in data.Eggs do
		eggCount += 1
	end
	for _, h in data.Hatching do
		if h.EndsAt <= State.now() then
			ready += 1
		end
	end
	eggCountLabel.Text = `x{eggCount}`
	Ui.badge(openTile, ready)
	Ui.badge(placeTile, eggCount)
	if shownVersion == data.InvVersion then
		return
	end
	shownVersion = data.InvVersion
	for _, r in rows do
		r:Destroy()
	end
	rows = {}
	local sorted = {}
	for uid, pet in data.Pets do
		table.insert(sorted, { uid = uid, pet = pet, def = Pets.ById[pet.Id] })
	end
	table.sort(sorted, function(a, b)
		local ea, eb = a.pet.Equipped and 1 or 0, b.pet.Equipped and 1 or 0
		if ea ~= eb then
			return ea > eb
		end
		local ra = a.def and Eggs.ByName[a.def.Rarity].Order or 0
		local rb = b.def and Eggs.ByName[b.def.Rarity].Order or 0
		return ra > rb
	end)
	for i, item in sorted do
		local def = item.def
		if def then
			local rarity = Eggs.ByName[def.Rarity]
			local card = Instance.new("TextButton")
			card.Name = item.uid
			card.Text = ""
			card.AutoButtonColor = false
			card.BorderSizePixel = 0
			card.LayoutOrder = i
			card.BackgroundColor3 = rarity.Color:Lerp(Ui.Colors.PanelDark, 0.55)
			Ui.gradient(card, card.BackgroundColor3)
			Ui.stroke(card, 3, rarity.Color)
			preview(card, item.pet)
			Ui.label({
				Size = UDim2.new(1, -6, 0, 22),
				Position = UDim2.new(0, 3, 1, -24),
				Text = def.Name,
				TextColor3 = rarity.Color,
			}).Parent = card
			if item.pet.Equipped then
				Ui.icon("Checkmark", { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(2, 2), ZIndex = 3 }).Parent = card
			end
			if item.pet.Placed then
				Ui.icon("Base", { Size = UDim2.fromOffset(30, 30), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, 2), ZIndex = 3 }).Parent =
					card
			end
			card.Activated:Connect(function()
				Ui.sound("Click")
				select(item.uid)
			end)
			card.Parent = list
			table.insert(rows, card)
		end
	end
	if selected and not data.Pets[selected] then
		select(nil)
	elseif selected then
		select(selected)
	end
end

function PetsController:Toggle()
	if window.Visible then
		Ui.closeWindow(window)
	else
		Ui.openWindow(window)
		Net.event("Analytics"):FireServer("Open", "Pets")
		select(nil)
		if State.data then
			render(State.data)
		end
	end
end

function PetsController:Init()
	local gui = Ui.screen("Pets", 20)
	local body
	window, body = Ui.window(gui, "Window", "PETS", Vector2.new(640, 560))
	-- Top row: egg bag + three icon tiles.
	local eggs = Ui.frame({ Name = "EggBag", Size = UDim2.fromOffset(130, 84), BackgroundTransparency = 1 })
	Ui.icon("GoldenEgg", { Size = UDim2.fromOffset(72, 72) }).Parent = eggs
	eggCountLabel = Ui.label({ Size = UDim2.fromOffset(60, 40), Position = UDim2.fromOffset(68, 22), Text = "x0", TextXAlignment = Enum.TextXAlignment.Left })
	eggCountLabel.Parent = eggs
	eggs.Parent = body
	placeTile = Ui.tile("PlaceEggs", "Base", "PLACE", Ui.Colors.Green, function()
		act("PlaceEggs")
	end, 84)
	placeTile.Position = UDim2.fromOffset(150, 0)
	placeTile.Parent = body
	openTile = Ui.tile("OpenReady", "Egg", "OPEN", Ui.Colors.Yellow, function()
		act("OpenReady")
	end, 84)
	openTile.Position = UDim2.fromOffset(246, 0)
	openTile.Parent = body
	local best = Ui.tile("Best", "Star", "BEST", Ui.Colors.Ice, function()
		act("Best")
	end, 84)
	best.Position = UDim2.fromOffset(342, 0)
	best.Parent = body

	list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, 0, 1, -96)
	list.Position = UDim2.fromOffset(0, 96)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(112, 128)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	list.Parent = body

	-- The selected pet's actions (slides over the top row).
	actions = Ui.frame({ Name = "Actions", Size = UDim2.new(1, 0, 0, 90), BackgroundColor3 = Ui.Colors.PanelDark, Visible = false, ZIndex = 30 })
	Ui.stroke(actions, 3)
	actName = Ui.label({ Size = UDim2.new(0, 200, 0, 34), Position = UDim2.fromOffset(8, 6), Text = "", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31 })
	actName.Parent = actions
	Ui.icon("Power", { Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(6, 46), ZIndex = 31 }).Parent = actions
	actTrain = Ui.label({ Size = UDim2.fromOffset(70, 30), Position = UDim2.fromOffset(44, 50), Text = "", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31 })
	actTrain.Parent = actions
	Ui.icon("Cash", { Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(112, 46), ZIndex = 31 }).Parent = actions
	actIncome = Ui.label({ Size = UDim2.fromOffset(90, 30), Position = UDim2.fromOffset(150, 50), Text = "", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31 })
	actIncome.Parent = actions
	followTile = Ui.tile("Follow", "Pets", "FOLLOW", Ui.Colors.Ice, function()
		local pet = selected and State.data and State.data.Pets[selected]
		if pet then
			act(if pet.Equipped then "Unequip" else "Equip", selected)
		end
	end, 80)
	followTile.Position = UDim2.new(1, -262, 0, 5)
	followTile.ZIndex = 31
	followTile.Parent = actions
	baseTile = Ui.tile("ToBase", "Base", "TO BASE", Ui.Colors.Green, function()
		local pet = selected and State.data and State.data.Pets[selected]
		if pet then
			act(if pet.Placed then "Unplace" else "Place", selected)
		end
	end, 80)
	baseTile.Position = UDim2.new(1, -176, 0, 5)
	baseTile.ZIndex = 31
	baseTile.Parent = actions
	local close = Ui.tile("CloseActions", "Close", "", Ui.Colors.Red, function()
		select(nil)
	end, 80)
	close.Position = UDim2.new(1, -90, 0, 5)
	close.ZIndex = 31
	close.Parent = actions
	actions.Parent = body
end

function PetsController:Start()
	State.observe(render)
end

return PetsController
