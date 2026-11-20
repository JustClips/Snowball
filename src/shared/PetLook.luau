--!strict
-- Builds the look of a pet: a clone of its StudAnimalPack model (ReplicatedStorage.PetModels)
-- sized to PetHeight x its scale, tinted by its mutation. Falls back to a graybox block in
-- the rarity colour if the pack isn't loaded. Used by the server (base pets) and the
-- client (followers, hatch show). Pivot = bottom centre, facing -Z (the pack's front).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Eggs = require(script.Parent.Config.Eggs)
local Pets = require(script.Parent.Config.Pets)

local PetLook = {
	PetHeight = 3.6, -- studs, for a normal pet
	HugeScale = 2.5,
}

local mutationColor: { [string]: Color3 } = {}
for _, m in Eggs.Mutations do
	mutationColor[m.Name] = m.Color
end

local function graybox(def: Pets.PetDef): Model
	local m = Instance.new("Model")
	local p = Instance.new("Part")
	p.Name = "Body"
	p.Size = Vector3.new(2.6, PetLook.PetHeight, 3)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	local rarity = Eggs.ByName[def.Rarity]
	p.Color = if rarity then rarity.Color else Color3.new(1, 1, 1)
	p.CFrame = CFrame.new(0, PetLook.PetHeight / 2, 0)
	p.Parent = m
	m.PrimaryPart = p
	m.WorldPivot = CFrame.new()
	return m
end

-- size: extra scale for the pet's weight (PetStats.sizeMult), 1 if left out.
function PetLook.make(petId: string, mutation: string?, huge: boolean?, size: number?): Model?
	local def = Pets.ById[petId]
	if not def then
		return nil
	end
	local models = ReplicatedStorage:FindFirstChild("PetModels")
	local source = models and models:FindFirstChild(def.Model)
	local model: Model
	if source and source:IsA("Model") then
		model = source:Clone()
		local _, box = model:GetBoundingBox()
		local height = math.max(box.Y, 0.1)
		model:ScaleTo(model:GetScale() * PetLook.PetHeight / height)
	else
		model = graybox(def)
	end
	local scale = (def.Scale or 1) * (if huge then PetLook.HugeScale else 1) * (size or 1)
	if scale ~= 1 then
		model:ScaleTo(model:GetScale() * scale)
	end
	local tint = mutation and mutationColor[mutation]
	if tint then
		for _, d in model:GetDescendants() do
			if d:IsA("SurfaceAppearance") then
				(d :: any).Color = tint
			elseif d:IsA("BasePart") and d.Name == "Body" then
				d.Color = d.Color:Lerp(tint, 0.6)
			end
		end
	end
	model.Name = petId
	return model
end

return PetLook
