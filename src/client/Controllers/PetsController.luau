--!strict
-- The Pets window (GAME_PLAN §7 items 12-13): your eggs (place them, open ready ones), your
-- pets with Equip (follow you, boost training) and Base (earn cash on your base), Equip Best.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)
local Pets = require(Shared.Config.Pets)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local PetsController = {}

local window: Frame
local list: ScrollingFrame
local eggLine: TextLabel
local rows: { Frame } = {}
local shownVersion = -1

local function act(action: string, arg: any?)
	local ok, why = Net.func("Pets"):InvokeServer(action, arg)
	if not ok and why then
		Ui.toast(why, "Bad")
	end
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
	eggLine.Text = `Eggs in bag: {eggCount} · hatching: {#data.Hatching} · ready: {ready}`
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
			local row = Ui.frame({ Name = item.uid, Size = UDim2.new(1, -8, 0, 56), BackgroundColor3 = Ui.Colors.PanelDark, LayoutOrder = i })
			Ui.stroke(row, 2, rarity.Color)
			local name = (if item.pet.Huge then "Huge " else "") .. (if item.pet.Mutation then item.pet.Mutation .. " " else "") .. def.Name
			Ui.label({ Size = UDim2.new(1, -250, 0, 28), Position = UDim2.fromOffset(8, 4), Text = name, TextColor3 = rarity.Color, TextXAlignment = Enum.TextXAlignment.Left }).Parent = row
			Ui.label({ Size = UDim2.new(1, -250, 0, 18), Position = UDim2.fromOffset(8, 33), Text = `{def.Rarity} · {item.pet.Zone or "Meadow"}`, TextXAlignment = Enum.TextXAlignment.Left }).Parent = row
			local equipped = item.pet.Equipped == true
			Ui.button({ Size = UDim2.fromOffset(116, 44), Position = UDim2.new(1, -240, 0, 6), BackgroundColor3 = if equipped then Ui.Colors.Yellow else Ui.Colors.Ice }, if equipped then "UNEQUIP" else "EQUIP", function()
				act(if equipped then "Unequip" else "Equip", item.uid)
			end).Parent = row
			local placed = item.pet.Placed ~= nil
			Ui.button({ Size = UDim2.fromOffset(116, 44), Position = UDim2.new(1, -120, 0, 6), BackgroundColor3 = if placed then Ui.Colors.Yellow else Ui.Colors.Green }, if placed then "TO BAG" else "TO BASE", function()
				act(if placed then "Unplace" else "Place", item.uid)
			end).Parent = row
			row.Parent = list
			table.insert(rows, row)
		end
	end
end

function PetsController:Toggle()
	if window.Visible then
		Ui.closeWindow(window)
	else
		Ui.openWindow(window)
		Net.event("Analytics"):FireServer("Open", "Pets")
		if State.data then
			render(State.data)
		end
	end
end

function PetsController:Init()
	local gui = Ui.screen("Pets", 20)
	local body
	window, body = Ui.window(gui, "Window", "PETS & EGGS", Vector2.new(600, 560))
	eggLine = Ui.label({ Size = UDim2.new(1, 0, 0, 26), Text = "", TextXAlignment = Enum.TextXAlignment.Left })
	eggLine.Parent = body
	local buttons = {
		{ "PLACE EGGS", Ui.Colors.Green, "PlaceEggs" },
		{ "OPEN READY", Ui.Colors.Yellow, "OpenReady" },
		{ "EQUIP BEST", Ui.Colors.Ice, "Best" },
	}
	for i, b in buttons do
		Ui.button({ Size = UDim2.new(1 / 3, -6, 0, 50), Position = UDim2.new((i - 1) / 3, 3, 0, 32), BackgroundColor3 = b[2] }, b[1], function()
			act(b[3])
		end).Parent = body
	end
	list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, 0, 1, -92)
	list.Position = UDim2.fromOffset(0, 92)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	list.Parent = body
end

function PetsController:Start()
	State.observe(render)
end

return PetsController
