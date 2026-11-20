--!strict
-- Hover text for pets and eggs in any pet park, exactly like Sweep the World's (Dev
-- 2026-11-20: "take what sweep the world has"): point the mouse at one (or tap it on a
-- phone, it stays 3 s). Minimal, no panel: outlined lines next to the pointer.
--   pets: name in its rarity colour, +$/s, weight, effects (mutation x cash, HUGE)
--   eggs: "<Rarity> Egg", "Ready in 3:57" / "Ready to open!"
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local PetStats = require(Shared.PetStats)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local TAP_SECONDS = 3
local GREEN = Color3.fromRGB(124, 255, 140)
local SOFT = Color3.fromRGB(200, 208, 232)

local HoverController = {}

local C: any
local card: Frame
local nameLabel: TextLabel
local incomeLabel: TextLabel
local weightLabel: TextLabel
local extraLabel: TextLabel
local tapUntil = 0
local tapPoint: Vector2? = nil

-- The pet model or egg part under a screen point, if any.
local function targetAt(point: Vector2): Instance?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = Players.LocalPlayer.Character
	params.FilterDescendantsInstances = if character then { character } else {}
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 250, params)
	local node: Instance? = hit and hit.Instance
	while node and node ~= Workspace do
		if node:IsA("Model") and node:GetAttribute("PetId") ~= nil then
			return node
		end
		if node:IsA("BasePart") and node:GetAttribute("Rarity") ~= nil and node:GetAttribute("EndsAt") ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function showPet(model: Instance): boolean
	local info = {
		Id = model:GetAttribute("PetId"),
		Mutation = model:GetAttribute("Mutation"),
		Huge = model:GetAttribute("Huge") == true,
		Weight = model:GetAttribute("Weight"),
	}
	local rarity = PetStats.rarity(info)
	nameLabel.Text = (if info.Huge then "HUGE " else "") .. PetStats.name({ Id = info.Id, Mutation = info.Mutation })
	C.InventoryController.colorText(nameLabel, rarity)
	incomeLabel.Text = `+{Format.cash(model:GetAttribute("Income") or 0)}/s`
	incomeLabel.TextColor3 = GREEN
	weightLabel.Visible = true
	weightLabel.Text = PetStats.kgText(info.Weight)
	local lines = {}
	local color: Color3? = nil
	for _, m in Eggs.Mutations do
		if m.Name == info.Mutation then
			table.insert(lines, `{m.Name} x{m.IncomeMult} cash`)
			color = m.Color
		end
	end
	if info.Huge then
		table.insert(lines, `HUGE x{Eggs.HugeIncomeMult} cash`)
		color = color or Color3.fromRGB(255, 200, 60)
	end
	extraLabel.Visible = #lines > 0
	extraLabel.Text = table.concat(lines, "\n")
	extraLabel.TextColor3 = color or SOFT
	return true
end

local function showEgg(part: Instance): boolean
	local rarity = tostring(part:GetAttribute("Rarity"))
	nameLabel.Text = `{rarity} Egg`
	C.InventoryController.colorText(nameLabel, rarity)
	local left = (part:GetAttribute("EndsAt") or 0) - State.now()
	incomeLabel.Text = if left > 0 then `Ready in {Format.time(left)}` else "Ready to open!"
	incomeLabel.TextColor3 = if left > 0 then Color3.new(1, 1, 1) else GREEN
	weightLabel.Visible = false
	extraLabel.Visible = false
	return true
end

local function render(point: Vector2?)
	local target = if point then targetAt(point) else nil
	local shown = false
	if target then
		shown = if target:IsA("Model") then showPet(target) else showEgg(target)
	end
	card.Visible = shown
	if shown and point then
		local view = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1000, 800)
		local width = card.AbsoluteSize.X
		local x = point.X + 18
		if x + width > view.X - 8 then
			x = point.X - width - 18
		end
		card.Position = UDim2.fromOffset(x, point.Y + 12)
	end
end

local function line(name: string, order: number, size: number, color: Color3, stroke: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.FontFace = Ui.FontBlack
	l.Text = ""
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = false
	l.Size = UDim2.new(1, 0, 0, size + 4)
	l.LayoutOrder = order
	local s = Instance.new("UIStroke")
	s.Thickness = stroke
	s.Color = Ui.Colors.Ink
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = l
	l.Parent = card
	return l
end

function HoverController:Init(controllers)
	C = controllers
	local gui = Ui.screen("Hover", 30)
	gui.ScreenInsets = Enum.ScreenInsets.None -- same space as the mouse
	card = Ui.frame({
		Name = "Card",
		Size = UDim2.fromOffset(260, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 10,
	})
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = card
	nameLabel = line("Name", 1, 24, Color3.new(1, 1, 1), 3)
	incomeLabel = line("Income", 2, 20, GREEN, 2.5)
	weightLabel = line("Weight", 3, 16, Color3.new(1, 1, 1), 2)
	extraLabel = line("Extra", 4, 15, SOFT, 2)
	-- One effect per line; the card grows to fit.
	extraLabel.Size = UDim2.new(1, 0, 0, 0)
	extraLabel.AutomaticSize = Enum.AutomaticSize.Y
	card.Parent = gui
end

function HoverController:Start()
	UserInputService.InputEnded:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		-- Touch positions leave out the top bar; the mouse (and this gui) include it.
		tapPoint = Vector2.new(input.Position.X, input.Position.Y) + game:GetService("GuiService"):GetGuiInset()
		tapUntil = os.clock() + TAP_SECONDS
	end)
	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.05 then
			return
		end
		accumulator = 0
		if C.HudController:Mode() ~= "Normal" or C.PlacementController:HeldKey() then
			card.Visible = false
		elseif UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
			render(UserInputService:GetMouseLocation())
		elseif os.clock() < tapUntil then
			render(tapPoint)
		else
			card.Visible = false
		end
	end)
end

return HoverController
