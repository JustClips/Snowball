--!strict
-- Hatching on your base (GAME_PLAN §5.9): eggs from the bag go on the 4 hatch spots of
-- your base, wait their rarity's time (Fast Hatch halves it; a new player's first egg takes
-- 3 s), then open into a pet with a roll for mutation and Huge. Ready eggs open with a
-- ProximityPrompt on the egg or the Pets window. Egg looks are graybox until the Blender
-- frozen eggs (Assets Egg_<Rarity>) are uploaded.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)
local Pets = require(Shared.Config.Pets)
local World = require(Shared.Config.World)

local HatchService = {}

local S: any
local rng = Random.new()

local function hatchSeconds(data: any, rarity: string): number
	if data.Stats.Hatches == 0 and #data.Hatching == 0 then
		return Eggs.FirstEggSeconds
	end
	local t = Eggs.hatchSeconds(rarity)
	if data.Gamepasses.FastHatch then
		t *= Eggs.FastHatchMult
	end
	return math.ceil(t)
end

local function freeSpot(data: any): number?
	local used = {}
	for _, h in data.Hatching do
		used[h.Spot] = true
	end
	for i = 1, World.HatchSpots do
		if not used[i] then
			return i
		end
	end
	return nil
end

-- Graybox egg on the hatch spot, with the EndsAt attribute the client counts down from.
function HatchService:RefreshEggs(player: Player)
	local data = S.DataService:GetData(player)
	local index = player:GetAttribute("BaseIndex")
	local base = type(index) == "number" and S.WorldService:GetBase(index)
	if not data or not base then
		return
	end
	local old = base:FindFirstChild("Eggs")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Eggs"
	for _, h in data.Hatching do
		local rarity = Eggs.ByName[h.Rarity]
		local egg = Instance.new("Part")
		egg.Name = "Egg" .. h.Spot
		egg.Shape = Enum.PartType.Ball
		egg.Size = Vector3.new(3.4, 4.4, 3.4)
		egg.Anchored = true
		egg.CanCollide = false
		egg.Material = Enum.Material.Glass
		egg.Transparency = 0.15
		egg.Color = if rarity then rarity.Color else Color3.new(1, 1, 1)
		egg.CFrame = World.eggSpot(index :: number, h.Spot) * CFrame.new(0, 2.2, 0)
		egg:SetAttribute("EndsAt", h.EndsAt)
		egg:SetAttribute("Rarity", h.Rarity)
		egg:SetAttribute("Owner", player.UserId)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = h.Rarity .. " Egg"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Parent = egg
		local spot = h.Spot
		prompt.Triggered:Connect(function(who)
			if who == player then
				HatchService:Open(player, spot)
			end
		end)
		egg.Parent = folder
	end
	folder.Parent = base
end

-- Puts an egg from the bag on a free hatch spot.
function HatchService:Place(player: Player, uid: any): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data or type(uid) ~= "string" or not data.Eggs[uid] then
		return false, "No such egg"
	end
	local spot = freeSpot(data)
	if not spot then
		return false, "All hatch spots are busy"
	end
	local egg = data.Eggs[uid]
	data.Eggs[uid] = nil
	table.insert(data.Hatching, {
		Uid = uid,
		Rarity = egg.Rarity,
		Zone = egg.Zone,
		Spot = spot,
		EndsAt = os.time() + hatchSeconds(data, egg.Rarity),
	})
	S.AnalyticsService:Funnel(player, "FirstPlace")
	S.InventoryService:Bump(player)
	HatchService:RefreshEggs(player)
	if S.OfferService then
		S.OfferService:OnEggPlaced(player, egg.Rarity)
	end
	return true, nil
end

-- "Place for me": rarest eggs first, as many as fit.
function HatchService:PlaceAll(player: Player): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, nil
	end
	local list = {}
	for uid, egg in data.Eggs do
		table.insert(list, { uid = uid, order = (Eggs.ByName[egg.Rarity] or Eggs.Rarities[1]).Order })
	end
	table.sort(list, function(a, b)
		return a.order > b.order
	end)
	local placed = 0
	for _, item in list do
		if not freeSpot(data) then
			break
		end
		if HatchService:Place(player, item.uid) then
			placed += 1
		end
	end
	if placed == 0 then
		return false, if #list == 0 then "No eggs in your bag" else "All hatch spots are busy"
	end
	return true, nil
end

local function rollPet(rarity: string): string
	local list = Pets.ByRarity[rarity] or Pets.ByRarity.Common
	return list[rng:NextInteger(1, #list)].Id
end

-- Opens the egg on a spot if it's ready. Returns ok, message.
function HatchService:Open(player: Player, spot: any, force: boolean?): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data or type(spot) ~= "number" then
		return false, nil
	end
	for i, h in data.Hatching do
		if h.Spot == spot then
			if h.EndsAt > os.time() and not force then
				return false, "Not ready yet"
			end
			table.remove(data.Hatching, i)
			local luck = S.BoostService:GetLuck(player)
			local petId = rollPet(h.Rarity)
			local mutation = Eggs.rollMutation(rng, luck)
			local order = (Eggs.ByName[h.Rarity] or Eggs.Rarities[1]).Order
			local huge = order >= Eggs.HugeMinOrder and rng:NextNumber() < luck / Eggs.HugeChance
			local uid = S.PetService:GivePet(player, petId, { Zone = h.Zone, Mutation = mutation, Huge = huge or nil })
			data.Stats.Hatches += 1
			S.AnalyticsService:Funnel(player, "FirstHatch")
			S.AnalyticsService:Custom(
				player,
				"EggHatched",
				1,
				{ Rarity = h.Rarity, Pet = petId, Mutation = mutation or "None" }
			)
			Net.fire(
				"HatchCompleted",
				player,
				{ Uid = uid, PetId = petId, Rarity = h.Rarity, Mutation = mutation, Huge = huge, Zone = h.Zone }
			)
			if order >= 6 then
				Net.fireAll(
					"Announce",
					`{player.DisplayName} hatched a {mutation and (mutation .. " ") or ""}{Pets.ById[petId].Name} ({h.Rarity})!`
				)
			end
			S.InventoryService:Bump(player)
			HatchService:RefreshEggs(player)
			if S.OfferService then
				task.delay(4, function() -- after the hatch show
					if player.Parent then
						S.OfferService:OnHatch(player)
					end
				end)
			end
			return true, nil
		end
	end
	return false, nil
end

function HatchService:OpenReady(player: Player): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, nil
	end
	local opened = 0
	for _, h in table.clone(data.Hatching) do
		if h.EndsAt <= os.time() and HatchService:Open(player, h.Spot) then
			opened += 1
		end
	end
	return opened > 0, if opened == 0 then "No egg is ready yet" else nil
end

function HatchService:HasHatching(player: Player, rarity: string): boolean
	local data = S.DataService:GetData(player)
	for _, h in (data and data.Hatching or {}) do
		if h.Rarity == rarity and h.EndsAt > os.time() then
			return true
		end
	end
	return false
end

-- Skip Hatch product: the egg of that rarity with the most time left is ready now.
function HatchService:SkipOne(player: Player, rarity: string)
	local data = S.DataService:GetData(player)
	local best = nil
	for _, h in (data and data.Hatching or {}) do
		if h.Rarity == rarity and h.EndsAt > os.time() and (not best or h.EndsAt > best.EndsAt) then
			best = h
		end
	end
	if best then
		best.EndsAt = os.time()
		S.InventoryService:Bump(player)
		HatchService:RefreshEggs(player)
	end
end

function HatchService:Init(services)
	S = services
	S.BaseService.BaseAssigned:Connect(function(player)
		HatchService:RefreshEggs(player)
	end)
	S.DataService.ProfileReleasing:Connect(function(player)
		local index = player:GetAttribute("BaseIndex")
		local base = type(index) == "number" and S.WorldService:GetBase(index)
		local eggs = base and base:FindFirstChild("Eggs")
		if eggs then
			eggs:Destroy()
		end
	end)
end

return HatchService
