--!strict
-- Builds an egg you can hold, place or see in the bag: the Blender frozen egg for its
-- rarity (ReplicatedStorage.EggModels, published by CarryService from Config/Models
-- Egg_<Rarity>), or a glassy rarity-coloured egg until those load. Pivot = bottom centre.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Eggs = require(script.Parent.Config.Eggs)

local EggLook = {
	Height = 4.4, -- studs, an egg on the ground
}

function EggLook.make(rarity: string): Model
	local model = Instance.new("Model")
	model.Name = rarity .. "Egg"
	local folder = ReplicatedStorage:FindFirstChild("EggModels")
	local source = folder and folder:FindFirstChild(rarity)
	if source and source:IsA("BasePart") then
		local part = source:Clone()
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.Parent = model
		-- No PrimaryPart yet: WorldPivot is ignored once a model has one.
		model.WorldPivot = CFrame.new()
		model:PivotTo(CFrame.new())
		local _, size = model:GetBoundingBox()
		if size.Y > 0.1 then
			model:ScaleTo(EggLook.Height / size.Y)
		end
		-- Bottom centre at the pivot.
		local box = model:GetBoundingBox()
		local _, sz = model:GetBoundingBox()
		local pivot = CFrame.new(box.Position - Vector3.new(0, sz.Y / 2, 0))
		model.PrimaryPart = part
		part.PivotOffset = part.CFrame:ToObjectSpace(pivot)
		return model
	end
	local def = Eggs.ByName[rarity]
	local p = Instance.new("Part")
	p.Name = "Egg"
	p.Size = Vector3.new(3.4, EggLook.Height, 3.4)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.Material = Enum.Material.Glass
	p.Transparency = 0.1
	p.Color = if def then def.Color else Color3.new(1, 1, 1)
	p.CFrame = CFrame.new(0, EggLook.Height / 2, 0)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	p.Parent = model
	model.PrimaryPart = p
	p.PivotOffset = p.CFrame:Inverse() -- pivot = bottom centre (WorldPivot is ignored with a PrimaryPart)
	return model
end

return EggLook
