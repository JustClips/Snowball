--!strict
-- Hover card for pets and eggs in any base (Steal an Egg / Sweep the World): point the mouse
-- at one, or tap it on a phone (it stays 3 s). Pets: name in their rarity colour, the
-- rarity word, weight and cash per second (plus Huge / mutation in the name). Eggs: rarity
-- and the time left. The card sits next to the pointer, no window.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local PetStats = require(Shared.PetStats)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local TAP_SECONDS = 3

local HoverController = {}

local C: any
local card: Frame
local nameLabel: TextLabel
local rarityLabel: TextLabel
local weightLabel: TextLabel
local cashLabel: TextLabel
local tapUntil = 0
local tapPos: Vector2? = nil
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

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

local function show(target: Instance, point: Vector2)
	if target:IsA("Model") then
		local info = {
			Id = target:GetAttribute("PetId"),
			Mutation = target:GetAttribute("Mutation"),
			Huge = target:GetAttribute("Huge") == true,
			Weight = target:GetAttribute("Weight"),
		}
		local rarity = PetStats.rarity(info)
		nameLabel.Text = PetStats.name(info)
		C.InventoryController.colorText(nameLabel, rarity)
		rarityLabel.Text = rarity
		C.InventoryController.colorText(rarityLabel, rarity)
		weightLabel.Text = PetStats.kgText(info.Weight)
		weightLabel.Visible = true
		cashLabel.Text = `{Format.cash(target:GetAttribute("Income") or 0)}/s`
		cashLabel.TextColor3 = Ui.Colors.Green
	else
		local rarity = tostring(target:GetAttribute("Rarity"))
		nameLabel.Text = `{rarity} Egg`
		C.InventoryController.colorText(nameLabel, rarity)
		rarityLabel.Text = rarity
		C.InventoryController.colorText(rarityLabel, rarity)
		weightLabel.Visible = false
		local left = (target:GetAttribute("EndsAt") or 0) - State.now()
		cashLabel.Text = if left > 0 then Format.time(left) else "READY!"
		cashLabel.TextColor3 = if left > 0 then Ui.Colors.Snow else Ui.Colors.Green
	end
	local inset = game:GetService("GuiService"):GetGuiInset()
	card.Position = UDim2.fromOffset(point.X + 22, point.Y - inset.Y - 10)
	card.Visible = true
end

function HoverController:Init(controllers)
	C = controllers
	local gui = Ui.screen("Hover", 40)
	card = Ui.frame({
		Name = "Card",
		Size = UDim2.fromOffset(230, 104),
		BackgroundColor3 = Ui.Colors.PanelDark,
		BackgroundTransparency = 0.1,
		Visible = false,
	})
	Ui.corner(card, 14)
	Ui.stroke(card, 3)
	nameLabel = Ui.label({
		Size = UDim2.new(1, -16, 0, 32),
		Position = UDim2.fromOffset(8, 6),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	nameLabel.Parent = card
	rarityLabel = Ui.label({
		Size = UDim2.new(0.5, -8, 0, 24),
		Position = UDim2.fromOffset(8, 40),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	rarityLabel.Parent = card
	weightLabel = Ui.label({
		Size = UDim2.new(0.5, -8, 0, 24),
		Position = UDim2.new(0.5, 0, 0, 40),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	weightLabel.Parent = card
	cashLabel = Ui.label({
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.fromOffset(8, 68),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	cashLabel.Parent = card
	card.Parent = gui
end

function HoverController:Start()
	UserInputService.TouchTap:Connect(function(positions, processed)
		if processed or (C.PlacementController and C.PlacementController:HeldKey()) then
			return
		end
		local p = positions[1]
		if p then
			local inset = game:GetService("GuiService"):GetGuiInset()
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
		if C.HudController:Mode() ~= "Normal" then
			card.Visible = false
			return
		end
		local point: Vector2?
		if tapPos and os.clock() < tapUntil then
			point = tapPos
		elseif UserInputService.MouseEnabled then
			point = UserInputService:GetMouseLocation()
		end
		local target = point and pick(point)
		if target and point then
			show(target, point)
		else
			card.Visible = false
		end
	end)
end

return HoverController
