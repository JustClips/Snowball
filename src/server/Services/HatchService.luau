--!strict
-- Hatching on your base (GAME_PLAN §5.9), Steal an Egg style: you carry an egg from your
-- bag (CarryService) and put it down anywhere in your pet park (Shared/EggSpots, up to
-- World.HatchSpots growing at once). It waits its rarity's time (Fast Hatch halves it; a new player's first egg takes
-- 3 s), then open into a pet with a roll for mutation and Huge. Ready eggs open with a
-- ProximityPrompt on the egg ("Open"); a growing egg's prompt is "Hatch Now" and asks for
-- the Skip Hatch product for that very egg (Sweep the World's flow, Dev 2026-11-20). The
-- client plays the hatch show (HatchController) from HatchCompleted; everyone near sees a
-- short version from HatchShown.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)
local Pets = require(Shared.Config.Pets)
local EggSpots = require(Shared.EggSpots)
local World = require(Shared.Config.World)
local PetStats = require(Shared.PetStats)
local ModelLoader = require(script.Parent.Parent.Lib.ModelLoader)

local HatchService = {}

local S: any
local rng = Random.new()
-- The egg a player last asked to Hatch Now, so the Skip Hatch purchase opens that egg.
local skipTarget: { [Player]: string } = {}

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
		-- The Blender egg for this rarity (art/blender/track.py), graybox until it loads.
		local spotCf = World.baseCFrame(index :: number) * CFrame.new(h.X or 0, World.ParkTop, h.Z or 0)
		local egg = ModelLoader.part("Egg_" .. h.Rarity, spotCf)
		if not egg then
			local p = Instance.new("Part")
			p.Size = Vector3.new(3.4, 4.4, 3.4)
			p.Material = Enum.Material.Glass
			p.Transparency = 0.15
			p.Color = if rarity then rarity.Color else Color3.new(1, 1, 1)
			p.CFrame = spotCf * CFrame.new(0, 2.2, 0)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
			egg = p
		end
		egg.Name = "Egg" .. h.Spot
		egg.Anchored = true
		egg.CanCollide = false
		egg:SetAttribute("EndsAt", h.EndsAt)
		egg:SetAttribute("StartsAt", h.StartsAt or (h.EndsAt - Eggs.hatchSeconds(h.Rarity)))
		egg:SetAttribute("Rarity", h.Rarity)
		egg:SetAttribute("Owner", player.UserId)
		egg:SetAttribute("Uid", h.Uid)
		-- Only the owner sees it (PetWorldController hides it for others and keeps the
		-- action text up to date: "Hatch Now" with the price, then "Open").
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "EggPrompt"
		prompt.ActionText = if h.EndsAt <= os.time() then "Open" else "Hatch Now"
		prompt.ObjectText = h.Rarity .. " Egg"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("OwnerUserId", player.UserId)
		prompt.Parent = egg
		local spot = h.Spot
		prompt.Triggered:Connect(function(who)
			if who ~= player then
				return
			end
			local current = HatchService:Hatching(player, spot)
			if not current then
				return
			end
			if current.EndsAt <= os.time() then
				HatchService:Open(player, spot)
			else
				-- Not ready: offer Skip Hatch for this egg right away.
				skipTarget[player] = current.Uid
				local ok, message = S.ShopService:Prompt(player, "SkipHatch" .. current.Rarity)
				if not ok and message then
					Net.fire("Notify", player, message, "Bad")
				end
			end
		end)
		egg.Parent = folder
	end
	folder.Parent = base
end

-- The hatching entry on a spot, if any.
function HatchService:Hatching(player: Player, spot: number): any
	local data = S.DataService:GetData(player)
	for _, h in (data and data.Hatching or {}) do
		if h.Spot == spot then
			return h
		end
	end
	return nil
end

-- The first egg in the bag of a rarity (what you carry when you hold that egg stack).
function HatchService:FirstEggOf(player: Player, rarity: string): string?
	local data = S.DataService:GetData(player)
	for uid, egg in (data and data.Eggs or {}) do
		if egg.Rarity == rarity then
			return uid
		end
	end
	return nil
end

function HatchService:HasRoom(player: Player): boolean
	local data = S.DataService:GetData(player)
	return data ~= nil and freeSpot(data) ~= nil
end

local PLACE_REACH = 70 -- studs from the park centre the player may stand

-- Puts an egg from the bag down in your park. pos = the spot picked (world space); without
-- it a free spot near the gate is chosen.
function HatchService:Place(player: Player, uid: any, pos: Vector3?): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data or type(uid) ~= "string" or not data.Eggs[uid] then
		return false, "No such egg"
	end
	local spot = freeSpot(data)
	if not spot then
		return false, `Only {World.HatchSpots} eggs can hatch at once! Open one first.`
	end
	local x, z
	if pos then
		local index = player:GetAttribute("BaseIndex")
		if type(index) ~= "number" then
			return false, "You don't have a base yet"
		end
		local cf = World.baseCFrame(index)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local c = (World.ParkMin + World.ParkMax) / 2
		local centre = cf * Vector3.new(c.X, 0, c.Y)
		if not root or (Vector3.new(root.Position.X, centre.Y, root.Position.Z) - centre).Magnitude > PLACE_REACH then
			return false, "Go to your base first!"
		end
		local p = cf:PointToObjectSpace(pos)
		x, z = p.X, p.Z
		local problem = EggSpots.problem(data.Hatching, x, z)
		if problem then
			return false, problem
		end
	else
		x, z = EggSpots.auto(data.Hatching)
		if not x then
			return false, "No room left in your base"
		end
	end
	local egg = data.Eggs[uid]
	data.Eggs[uid] = nil
	table.insert(data.Hatching, {
		Uid = uid,
		Rarity = egg.Rarity,
		Zone = egg.Zone,
		Spot = spot,
		X = x,
		Z = z,
		StartsAt = os.time(),
		EndsAt = os.time() + hatchSeconds(data, egg.Rarity),
	})
	S.AnalyticsService:Funnel(player, "FirstPlace")
	S.InventoryService:Bump(player)
	HatchService:RefreshEggs(player)
	-- No popup any more (Dev 2026-11-20: it looked bad): the egg's own prompt offers Hatch Now.
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
			-- The pet pops out where the egg was (or goes in the bag when the park is full).
			local at = if h.X and h.Z then Vector2.new(h.X, h.Z) else nil
			local uid =
				S.PetService:GivePet(player, petId, { Zone = h.Zone, Mutation = mutation, Huge = huge or nil }, at)
			data.Stats.Hatches += 1
			S.AnalyticsService:Funnel(player, "FirstHatch")
			S.AnalyticsService:Custom(
				player,
				"EggHatched",
				1,
				{ Rarity = h.Rarity, Pet = petId, Mutation = mutation or "None" }
			)
			local show = {
				Uid = uid,
				PetId = petId,
				Rarity = h.Rarity,
				EggRarity = h.Rarity,
				Mutation = mutation,
				Huge = huge or nil,
				Zone = h.Zone,
				X = h.X,
				Z = h.Z,
				Weight = pet and pet.Weight,
				Income = if pet then PetStats.income(pet) * S.BoostService:GetCashMult(player) else 0,
				IsNew = isNew,
				Placed = pet ~= nil and pet.Placed == true,
			}
			Net.fire("HatchCompleted", player, show)
			local others = table.clone(show)
			others.UserId = player.UserId
			for _, other in game:GetService("Players"):GetPlayers() do
				if other ~= player then
					Net.fire("HatchShown", other, others)
				end
			end
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
	local target = skipTarget[player]
	skipTarget[player] = nil
	for _, h in (data and data.Hatching or {}) do
		if h.Rarity == rarity and h.EndsAt > os.time() then
			if h.Uid == target then
				best = h
				break
			elseif not best or h.EndsAt > best.EndsAt then
				best = h
			end
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
		-- Eggs saved before free placement get a park spot.
		local data = S.DataService:GetData(player)
		for _, h in (data and data.Hatching or {}) do
			if not h.X then
				local x, z = EggSpots.auto(data.Hatching, h.Uid)
				h.X, h.Z = x or 0, z or -15
			end
		end
		HatchService:RefreshEggs(player)
	end)
	S.DataService.ProfileReleasing:Connect(function(player)
		skipTarget[player] = nil
		local index = player:GetAttribute("BaseIndex")
		local base = type(index) == "number" and S.WorldService:GetBase(index)
		local eggs = base and base:FindFirstChild("Eggs")
		if eggs then
			eggs:Destroy()
		end
	end)
end

return HatchService
