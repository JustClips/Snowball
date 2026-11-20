--!strict
-- Loads the Blender models listed in Config/Models (tools/upload_models.py) once each and
-- hands out clones placed by their model origin (floor centre, front = -Z).
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Models = require(ReplicatedStorage:WaitForChild("Shared").Config.Models)

local ModelLoader = {}

local cache: { [string]: Model | false } = {}
local loading: { [string]: boolean } = {}

local function fetch(name: string): Model?
	local entry = (Models :: any)[name]
	if not entry or entry.Id == 0 then
		return nil
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(entry.Id)
	end)
	if not ok then
		warn(`[ModelLoader] couldn't load {name} ({entry.Id}): {result}`)
		return nil
	end
	local container = result :: Model
	local model = container:FindFirstChildWhichIsA("Model") or container
	model.Parent = nil
	-- The GLB import wraps each Blender object in its own Model ("Ball" -> Model > MeshPart).
	-- Flatten those so every object is one named part (code moves Ball as a BasePart).
	for _, child in model:GetChildren() do
		if child:IsA("Model") then
			local parts = {}
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
			if #parts == 1 then
				parts[1].Name = child.Name
				parts[1].Parent = model
				child:Destroy()
			end
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
		end
	end
	-- Pivot on the axis-aligned bounding box centre, which Config/Models records.
	model.WorldPivot = CFrame.new((model:GetBoundingBox()).Position)
	return model
end

-- The template for `name` (yields the first time), or nil if it isn't uploaded / fails.
function ModelLoader.get(name: string): Model?
	while loading[name] do
		task.wait()
	end
	local c = cache[name]
	if c == nil then
		loading[name] = true
		local m = fetch(name)
		cache[name] = m or false
		loading[name] = nil
		return m
	end
	return if c then c else nil
end

-- A clone of `name` with its model origin at `origin` (optionally scaled), or nil.
function ModelLoader.clone(name: string, origin: CFrame, scale: number?): Model?
	local template = ModelLoader.get(name)
	if not template then
		return nil
	end
	local entry = (Models :: any)[name]
	local m = template:Clone()
	local s = scale or 1
	if s ~= 1 then
		m:ScaleTo(s)
	end
	m:PivotTo(origin * CFrame.new(entry.Center * s))
	return m
end

return ModelLoader
