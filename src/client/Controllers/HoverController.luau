--!strict
-- Hover card for pets and eggs in any base (Steal an Egg / Sweep the World): point the mouse
-- at one, or tap it on a phone (it stays 3 s). Mobile first (Dev 2026-11-20: the plain text
-- card looked cheap). The card is a navy sticker with the rarity's colour as its border:
--   pets: rarity pill (+ HUGE / mutation pills), the name in its rarity colour, then two
--         icon chips: weight (kettlebell) and cash per second;
--   eggs: rarity pill, "<Rarity> Egg", and a clock chip with the time left (READY! when done).
-- On PC it sits beside the pointer; on a phone it sits above your finger so the thumb never
-- hides it. It pops in when it changes target and keeps inside the screen.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local PetStats = require(Shared.PetStats)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local TAP_SECONDS = 3
local WIDTH = 250
local INK = Ui.Colors.Ink
local GOLD = Color3.fromRGB(255, 200, 40)
local CASH_GREEN = Color3.fromRGB(110, 235, 120)
local KG_BLUE = Color3.fromRGB(170, 220, 255)
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
	ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 90, 255)),
})

local HoverController = {}

local C: any
local gui: ScreenGui
local holder: Frame -- follows the screen size (Ui.autoScale)
local card: Frame
local pop: UIScale
local edge: UIStroke
local edgeGradient: UIGradient
local pills: Frame
local rarityPill: Frame
local rarityText: TextLabel
local rarityGradient: UIGradient
local hugePill: Frame
local mutationPill: Frame
local mutationText: TextLabel
local nameLabel: TextLabel
local chips: Frame
local weightChip: Frame
local weightText: TextLabel
local cashChip: Frame
local cashText: TextLabel
local cashIcon: ImageLabel
local shownTarget: Instance? = nil
local tapUntil = 0
local tapPos: Vector2? = nil
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

------------------------------------------------------------------ building blocks

local function text(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = Ui.FontBlack
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = false
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromOffset(0, 24)
	l.TextSize = 20
	for k, v in props do
		(l :: any)[k] = v
	end
	local s = Instance.new("UIStroke")
	s.Thickness = 2.5
	s.Color = INK
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = l
	return l
end

local function padding(parent: Instance, x: number, y: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, x)
	p.PaddingRight = UDim.new(0, x)
	p.PaddingTop = UDim.new(0, y)
	p.PaddingBottom = UDim.new(0, y)
	p.Parent = parent
end

local function row(parent: Instance, name: string, gap: number, height: number, order: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, height)
	f.LayoutOrder = order
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, gap)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = f
	f.Parent = parent
	return f
end

-- A rounded pill with bold text (rarity, HUGE, mutation).
local function pill(parent: Instance, name: string, color: Color3, order: number): (Frame, TextLabel)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.AutomaticSize = Enum.AutomaticSize.X
	f.Size = UDim2.fromOffset(0, 26)
	f.LayoutOrder = order
	Ui.corner(f, 13)
	Ui.stroke(f, 2.5)
	padding(f, 10, 0)
	local t = text({ Size = UDim2.fromOffset(0, 26), TextSize = 17, Text = "" })
	t.Parent = f
	f.Parent = parent
	return f, t
end

-- A dark chip with an icon and a value (weight, cash per second, time left).
local function chip(
	parent: Instance,
	name: string,
	icon: string,
	color: Color3,
	order: number
): (Frame, TextLabel, ImageLabel)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Color3.fromRGB(12, 14, 34)
	f.BackgroundTransparency = 0.15
	f.AutomaticSize = Enum.AutomaticSize.X
	f.Size = UDim2.fromOffset(0, 34)
	f.LayoutOrder = order
	Ui.corner(f, 10)
	padding(f, 6, 0)
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 5)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = f
	local img = Ui.icon(icon, { Size = UDim2.fromOffset(26, 26), LayoutOrder = 1 })
	img.Parent = f
	local t = text({ Size = UDim2.fromOffset(0, 30), TextSize = 21, TextColor3 = color, Text = "", LayoutOrder = 2 })
	t.Parent = f
	f.Parent = parent
	return f, t, img
end

------------------------------------------------------------------ what's under the pointer

local function targets(): { Instance }
	local list: { Instance } = {}
	local parks = Workspace:FindFirstChild("PetParks")
	if parks then
		table.insert(list, parks)
	end
	local m = Workspace:FindFirstChild("Mountain")
	local bases = m and m:FindFirstChild("Summit") and (m :: any).Summit:FindFirstChild("Bases")
	if bases then
		for _, base in bases:GetChildren() do
			local eggs = base:FindFirstChild("Eggs")
			if eggs then
				table.insert(list, eggs)
			end
		end
	end
	return list
end

-- What's under a screen point: a pet model, an egg part, or nil.
local function pick(point: Vector2): Instance?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	params.FilterDescendantsInstances = targets()
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	if not hit then
		return nil
	end
	local inst: Instance? = hit.Instance
	while inst and inst ~= Workspace do
		if inst:IsA("Model") and inst:GetAttribute("PetId") then
			return inst
		end
		if inst:IsA("BasePart") and inst:GetAttribute("Rarity") and inst:GetAttribute("EndsAt") then
			return inst
		end
		inst = inst.Parent
	end
	return nil
end

------------------------------------------------------------------ filling the card

local function setRarity(rarity: string)
	local def = Eggs.ByName[rarity]
	local color = if def then def.Color else Color3.new(1, 1, 1)
	local secret = rarity == "Secret"
	rarityText.Text = string.upper(rarity)
	rarityPill.BackgroundColor3 = if secret then Color3.new(1, 1, 1) else color
	rarityGradient.Enabled = secret
	edge.Color = if secret then Color3.new(1, 1, 1) else color
	edgeGradient.Enabled = secret
	C.InventoryController.colorText(nameLabel, rarity)
end

local function fill(target: Instance)
	if target:IsA("Model") then
		local info = {
			Id = target:GetAttribute("PetId"),
			Mutation = target:GetAttribute("Mutation"),
			Huge = target:GetAttribute("Huge") == true,
			Weight = target:GetAttribute("Weight"),
		}
		setRarity(PetStats.rarity(info))
		hugePill.Visible = info.Huge
		mutationPill.Visible = info.Mutation ~= nil
		if info.Mutation then
			mutationText.Text = string.upper(tostring(info.Mutation))
			for _, m in Eggs.Mutations do
				if m.Name == info.Mutation then
					mutationPill.BackgroundColor3 = m.Color
				end
			end
		end
		-- The pills already say Huge / the mutation, so the name is just the pet.
		nameLabel.Text = PetStats.name({ Id = info.Id })
		weightChip.Visible = true
		weightText.Text = PetStats.kgText(info.Weight)
		cashIcon.Image = Ui.Images.Cash
		cashText.Text = `{Format.cash(target:GetAttribute("Income") or 0)}/s`
		cashText.TextColor3 = CASH_GREEN
	else
		local rarity = tostring(target:GetAttribute("Rarity"))
		setRarity(rarity)
		hugePill.Visible = false
		mutationPill.Visible = false
		nameLabel.Text = `{rarity} Egg`
		weightChip.Visible = false
		local left = (target:GetAttribute("EndsAt") or 0) - State.now()
		cashIcon.Image = if left > 0 then Ui.Images.Clock else Ui.Images.Checkmark
		cashText.Text = if left > 0 then Format.time(left) else "READY!"
		cashText.TextColor3 = if left > 0 then Color3.new(1, 1, 1) else CASH_GREEN
	end
end

local function place(point: Vector2, touch: boolean)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	-- This ScreenGui covers the whole screen (no insets), the same space as the mouse.
	local view = camera.ViewportSize
	local p = point
	local scale = holder:FindFirstChildOfClass("UIScale")
	local s = if scale then scale.Scale else 1
	local w = card.AbsoluteSize.X / math.max(pop.Scale, 0.01)
	local h = card.AbsoluteSize.Y / math.max(pop.Scale, 0.01)
	if w < 1 then
		w, h = WIDTH * s, 120 * s
	end
	local x, y
	if touch then
		-- Above the finger, centred on it.
		x = p.X - w / 2
		y = p.Y - h - 40 * s
		if y < 8 then
			y = p.Y + 40 * s
		end
	else
		x = p.X + 26 * s
		y = p.Y - h / 2
		if x + w > view.X - 8 then
			x = p.X - 26 * s - w
		end
	end
	x = math.clamp(x, 8, math.max(8, view.X - w - 8))
	y = math.clamp(y, 8, math.max(8, view.Y - h - 8))
	card.Position = UDim2.fromOffset(x / s, y / s)
end

local function show(target: Instance, point: Vector2, touch: boolean)
	fill(target)
	place(point, touch)
	if shownTarget ~= target or not card.Visible then
		shownTarget = target
		card.Visible = true
		pop.Scale = 0.8
		TweenService:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		Ui.sound("Tap", 1.3)
	end
end

local function hide()
	card.Visible = false
	shownTarget = nil
end

------------------------------------------------------------------ lifecycle

function HoverController:Init(controllers)
	C = controllers
	gui = Ui.screen("Hover", 40)
	gui.ScreenInsets = Enum.ScreenInsets.None
	holder = Ui.frame({ Name = "Holder", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	Ui.autoScale(holder)
	holder.Parent = gui

	card = Ui.frame({
		Name = "Card",
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Ui.Colors.PanelDark,
		BackgroundTransparency = 0.04,
		Visible = false,
	})
	Ui.corner(card, 16)
	edge = Ui.stroke(card, 4)
	edgeGradient = Instance.new("UIGradient")
	edgeGradient.Color = RAINBOW
	edgeGradient.Enabled = false
	edgeGradient.Parent = edge
	pop = Instance.new("UIScale")
	pop.Parent = card
	padding(card, 12, 10)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = card

	pills = row(card, "Pills", 6, 26, 1)
	rarityPill, rarityText = pill(pills, "Rarity", Color3.new(1, 1, 1), 1)
	rarityGradient = Instance.new("UIGradient")
	rarityGradient.Color = RAINBOW
	rarityGradient.Enabled = false
	rarityGradient.Parent = rarityPill
	local hugeText
	hugePill, hugeText = pill(pills, "Huge", GOLD, 2)
	hugeText.Text = "HUGE"
	mutationPill, mutationText = pill(pills, "Mutation", Ui.Colors.Ice, 3)

	nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.FontFace = Ui.FontBlack
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Size = UDim2.new(1, 0, 0, 34)
	nameLabel.LayoutOrder = 2
	nameLabel.Text = ""
	local ns = Instance.new("UIStroke")
	ns.Thickness = 3
	ns.Color = INK
	ns.LineJoinMode = Enum.LineJoinMode.Round
	ns.Parent = nameLabel
	nameLabel.Parent = card

	chips = row(card, "Chips", 8, 34, 3)
	weightChip, weightText = chip(chips, "Weight", "Weight", KG_BLUE, 1)
	cashChip, cashText, cashIcon = chip(chips, "Cash", "Cash", CASH_GREEN, 2)
	card.Parent = holder
end

function HoverController:Start()
	UserInputService.TouchTap:Connect(function(positions, processed)
		if processed or (C.PlacementController and C.PlacementController:HeldKey()) then
			return
		end
		local p = positions[1]
		if p then
			local inset = GuiService:GetGuiInset()
			tapPos = Vector2.new(p.X, p.Y) + inset
			tapUntil = os.clock() + TAP_SECONDS
		end
	end)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc < 0.05 then
			return
		end
		acc = 0
		if C.HudController:Mode() ~= "Normal" or (C.HatchController and C.HatchController:IsBusy()) then
			hide()
			return
		end
		local point: Vector2?
		local touch = false
		if tapPos and os.clock() < tapUntil then
			point = tapPos
			touch = true
		elseif UserInputService.MouseEnabled and UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then
			point = UserInputService:GetMouseLocation()
		end
		local target = point and pick(point)
		if target and point then
			show(target, point, touch)
		else
			hide()
		end
	end)
end

return HoverController
