--!strict
-- Carrying a pet or an egg from your bag (Steal an Egg / Sweep the World style): the model
-- is welded in front of your chest so everyone sees it, the clients pose the arms
-- (HoldPoseController), and the client shows where it will go (PlacementController).
-- PlaceHeld puts it down: a pet is let out in your park, an egg goes on the spot you
-- picked and starts hatching. Also publishes the Blender eggs (Config/Models Egg_<Rarity>)
-- to ReplicatedStorage.EggModels so clients can draw eggs in the bag and the ghost.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggLook = require(Shared.EggLook)
local Eggs = require(Shared.Config.Eggs)
local PetLook = require(Shared.PetLook)
local PetStats = require(Shared.PetStats)
local ModelLoader = require(script.Parent.Parent.Lib.ModelLoader)

local CarryService = {}

local S: any
local HELD_MAX = 3.4 -- studs: a carried pet or egg is shrunk to fit your arms

type Held = { Kind: string, Id: string } -- Pet: Id = uid, Egg: Id = rarity
local held: { [Player]: Held } = {}

local function clearModel(player: Player)
	local character = player.Character
	if not character then
		return
	end
	for _, name in { "HeldPet", "HeldEgg" } do
		local m = character:FindFirstChild(name)
		if m then
			m:Destroy()
		end
	end
end

local function weldInFront(player: Player, model: Model, name: string)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		model:Destroy()
		return
	end
	model.Name = name
	local _, size = model:GetBoundingBox()
	local biggest = math.max(size.X, size.Y, size.Z)
	if biggest > HELD_MAX then
		model:ScaleTo(model:GetScale() * HELD_MAX / biggest)
		_, size = model:GetBoundingBox()
	end
	-- Pivot = bottom centre: sit it on the forearms, in front of the chest, facing forward.
	model:PivotTo(root.CFrame * CFrame.new(0, -0.6, -(root.Size.Z / 2 + size.Z / 2 + 0.3)))
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
	model.Parent = character
end

-- Welds any model into your arms (the egg rescue uses it): named "HeldEgg"/"HeldPet" so
-- HoldPoseController poses the arms. It does not change what you hold from your bag.
function CarryService:WeldModel(player: Player, model: Model, name: string)
	weldInFront(player, model, name)
end

function CarryService:Held(player: Player): Held?
	return held[player]
end

-- kind "Pet": id = a pet uid in your bag. kind "Egg": id = a rarity you have eggs of.
function CarryService:Hold(player: Player, kind: any, id: any): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data or type(id) ~= "string" then
		return false, nil
	end
	if player:GetAttribute("Training") or player:GetAttribute("RollPhase") then
		return false, nil
	end
	CarryService:StopHolding(player)
	if kind == "Pet" then
		local pet = data.Pets[id]
		if not pet or pet.Placed then
			return false, "That pet is gone"
		end
		held[player] = { Kind = "Pet", Id = id }
		local model = PetLook.make(pet.Id, pet.Mutation, pet.Huge, PetStats.sizeMult(pet))
		if model then
			weldInFront(player, model, "HeldPet")
		end
	elseif kind == "Egg" then
		if not S.HatchService:FirstEggOf(player, id) then
			return false, "No eggs like that left"
		end
		held[player] = { Kind = "Egg", Id = id }
		weldInFront(player, EggLook.make(id), "HeldEgg")
	else
		return false, nil
	end
	player:SetAttribute("Holding", kind)
	return true, nil
end

function CarryService:StopHolding(player: Player)
	held[player] = nil
	player:SetAttribute("Holding", nil)
	clearModel(player)
end

-- Puts down what you hold. pos = the spot you picked (world space).
function CarryService:PlaceHeld(player: Player, pos: Vector3?): (boolean, string?)
	local h = held[player]
	if not h then
		return false, nil
	end
	if h.Kind == "Pet" then
		local ok, why = S.PetService:PlacePet(player, h.Id, pos)
		if ok then
			CarryService:StopHolding(player)
		end
		return ok, why
	end
	local uid = S.HatchService:FirstEggOf(player, h.Id)
	if not uid then
		CarryService:StopHolding(player)
		return false, "No eggs like that left"
	end
	local ok, why = S.HatchService:Place(player, uid, pos)
	if ok then
		-- Keep holding the next egg of the same kind (fast to place a stack), if any left.
		if S.HatchService:FirstEggOf(player, h.Id) and S.HatchService:HasRoom(player) then
			CarryService:Hold(player, "Egg", h.Id)
		else
			CarryService:StopHolding(player)
		end
	end
	return ok, why
end

local VFX = {
	"VfxHatchRing",
	"VfxHatchSwirl",
	"VfxHatchPillar",
	"VfxHatchSpikes",
	"VfxHatchCrown",
	"VfxHatchStar",
	"VfxIceShard",
	"VfxIceChip",
	"VfxShellChunk",
}

local function shareEggs()
	local folder = Instance.new("Folder")
	folder.Name = "EggModels"
	for _, r in Eggs.Rarities do
		local part = ModelLoader.part("Egg_" .. r.Name, CFrame.new())
		if part then
			part.Name = r.Name
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
	-- The hatch show's meshes (art/blender/hatch_vfx.py) for the clients' HatchFx.
	local vfx = Instance.new("Folder")
	vfx.Name = "HatchVfx"
	for _, name in VFX do
		local part = ModelLoader.part(name, CFrame.new())
		if part then
			part.Name = name
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
			part.Parent = vfx
		end
	end
	vfx.Parent = ReplicatedStorage
end

function CarryService:Init(services)
	S = services
	S.BaseService.CharacterReady:Connect(function(player)
		held[player] = nil
		player:SetAttribute("Holding", nil)
	end)
	S.DataService.ProfileReleasing:Connect(function(player)
		held[player] = nil
	end)
end

function CarryService:Start()
	task.spawn(shareEggs)
	-- Training or rolling puts what you hold away.
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player in held do
				if player.Parent == nil then
					held[player] = nil
				elseif player:GetAttribute("Training") or player:GetAttribute("RollPhase") then
					CarryService:StopHolding(player)
				end
			end
		end
	end)
end

return CarryService
