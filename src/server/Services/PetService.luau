--!strict
-- Pets, Steal an Egg / Throw Food style (Dev 2026-11-20: "copy their pet system, don't make
-- our own"). A pet is either out in your base's pet park (Placed), where it wanders and
-- earns cash every second, or in your bag (inventory). You take one out of the bag, carry
-- it above your head (CarryService) and let it out in your park; pets in the park get a
-- Pick Up prompt that puts them back in the bag. No followers, no equip buttons.
--
-- The park is published as base.Pets: one Folder per placed pet (name = uid) with PetId,
-- Mutation, Huge, Weight, Income, X, Z attributes. Every client builds the models itself
-- and lets them wander (PetWorldController), like Sweep the World's PetController.
-- Training boost: your best pets in the park (EquipSlots of them, +2 with the pass).
-- Also answers the "Pets" remote for pets, eggs and carrying.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local PetStats = require(Shared.PetStats)
local Pets = require(Shared.Config.Pets)
local World = require(Shared.Config.World)
local PetModels = require(script.Parent.Parent.Lib.PetModels)

local PetService = {}

local S: any
local rng = Random.new()
local PLACE_REACH = 70 -- studs from the park centre you may stand to let a pet out

-- Pets in the park slots the training boost counts (3, +2 with the pass, +1 at 2 and 5 rebirths).
function PetService:EquipSlots(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return Economy.EquipSlots
	end
	local n = Economy.EquipSlots + (if data.Gamepasses.ExtraEquips then Economy.EquipSlotsPass else 0)
	if data.Rebirths >= 2 then
		n += 1
	end
	if data.Rebirths >= 5 then
		n += 1
	end
	return n
end

-- How many pets your park holds.
function PetService:BaseSlots(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return Economy.StartPetSlots
	end
	return math.min(World.PetSpotsMax, data.PetSlots) + (if data.Gamepasses.ExtraSlots then 4 else 0)
end

function PetService:PlacedCount(player: Player): number
	local data = S.DataService:GetData(player)
	local n = 0
	for _, pet in (data and data.Pets or {}) do
		if pet.Placed then
			n += 1
		end
	end
	return n
end

function PetService:BagCount(player: Player): number
	local data = S.DataService:GetData(player)
	local n = 0
	for _, pet in (data and data.Pets or {}) do
		if not pet.Placed then
			n += 1
		end
	end
	return n
end

-- $/s from pets in your park, with cash multipliers.
function PetService:GetIncomePerSec(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 0
	end
	local total = 0
	for _, pet in data.Pets do
		if pet.Placed then
			total += PetStats.income(pet)
		end
	end
	return total * S.BoostService:GetCashMult(player)
end

-- Training bonus (0.25 = +25%) from your best pets in the park.
function PetService:GetTrainBonus(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 0
	end
	local list = {}
	for _, pet in data.Pets do
		if pet.Placed then
			table.insert(list, PetStats.train(pet))
		end
	end
	table.sort(list, function(a, b)
		return a > b
	end)
	local total = 0
	for i = 1, math.min(#list, PetService:EquipSlots(player)) do
		total += list[i]
	end
	return total
end

local function baseOf(player: Player): (Instance?, number?)
	local index = player:GetAttribute("BaseIndex")
	if type(index) ~= "number" then
		return nil, nil
	end
	return S.WorldService:GetBase(index), index
end

-- Where a pet starts when it's let out: x, z in base local studs (runtime only).
local spawnAt: { [string]: Vector2 } = {}

local function randomParkSpot(): Vector2
	local min, max = World.ParkMin, World.ParkMax
	return Vector2.new(rng:NextNumber(min.X + 4, max.X - 4), rng:NextNumber(min.Y + 4, max.Y - 4))
end

-- Syncs base.Pets with the placed pets: adds new ones, removes gone ones, refreshes income.
function PetService:RefreshBase(player: Player)
	local data = S.DataService:GetData(player)
	local base = baseOf(player)
	if not data or not base then
		return
	end
	local folder = base:FindFirstChild("Pets")
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "Pets"
		f.Parent = base
		folder = f
	end
	local f = folder :: Folder
	f:SetAttribute("OwnerUserId", player.UserId)
	local cashMult = S.BoostService:GetCashMult(player)
	for _, entry in f:GetChildren() do
		local pet = data.Pets[entry.Name]
		if not pet or not pet.Placed or entry:GetAttribute("PetId") ~= pet.Id then
			entry:Destroy()
		end
	end
	for uid, pet in data.Pets do
		if pet.Placed then
			local entry = f:FindFirstChild(uid)
			if not entry then
				local e = Instance.new("Folder")
				e.Name = uid
				e:SetAttribute("PetId", pet.Id)
				e:SetAttribute("Mutation", pet.Mutation)
				e:SetAttribute("Huge", pet.Huge == true)
				e:SetAttribute("Weight", pet.Weight)
				e:SetAttribute("Zone", pet.Zone)
				local at = spawnAt[uid] or randomParkSpot()
				spawnAt[uid] = nil
				e:SetAttribute("X", at.X)
				e:SetAttribute("Z", at.Y)
				e:SetAttribute("Income", PetStats.income(pet) * cashMult)
				e.Parent = f
			else
				local income = PetStats.income(pet) * cashMult
				if entry:GetAttribute("Income") ~= income then
					entry:SetAttribute("Income", income)
				end
			end
		end
	end
	S.StateService:Mark(player)
end

local function changed(player: Player)
	S.InventoryService:Bump(player)
	PetService:RefreshBase(player)
end

-- Adds a pet. It goes out in your park (at `at`, base local x/z, if given) when there's
-- room, else into your bag. Returns its uid.
function PetService:GivePet(player: Player, petId: string, fields: { [string]: any }?, at: Vector2?): string?
	local data = S.DataService:GetData(player)
	local def = Pets.ById[petId]
	if not data or not def then
		return nil
	end
	local uid = S.DataService:NewUid(data, "p")
	local pet: any = { Id = petId, Zone = "Meadow" }
	for k, v in fields or {} do
		pet[k] = v
	end
	if type(pet.Weight) ~= "number" then
		pet.Weight = Pets.rollWeight(rng, def, pet.Huge)
	end
	data.Pets[uid] = pet
	data.Index[petId] = true
	if PetService:PlacedCount(player) < PetService:BaseSlots(player) then
		pet.Placed = true
		if at then
			spawnAt[uid] = at
		end
	else
		Net.fire("Notify", player, "Base full! Your new pet is in your bag.", "Bad")
	end
	changed(player)
	return uid
end

-- Lets a pet from the bag out in your park. worldPos = where you clicked / stand.
function PetService:PlacePet(player: Player, uid: string, worldPos: Vector3?): (boolean, string?)
	local data = S.DataService:GetData(player)
	local pet = data and data.Pets[uid]
	if not data or not pet then
		return false, "That pet is gone"
	end
	if pet.Placed then
		return true, nil
	end
	if PetService:PlacedCount(player) >= PetService:BaseSlots(player) then
		return false, "Base full! Buy more pet space in Upgrade."
	end
	local _, index = baseOf(player)
	if not index then
		return false, "You don't have a base yet"
	end
	local cf = World.baseCFrame(index)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local centre = cf * Vector3.new((World.ParkMin.X + World.ParkMax.X) / 2, 0, (World.ParkMin.Y + World.ParkMax.Y) / 2)
	if worldPos then
		if not root or (Vector3.new(root.Position.X, centre.Y, root.Position.Z) - centre).Magnitude > PLACE_REACH then
			return false, "Go to your base first!"
		end
		local p = cf:PointToObjectSpace(worldPos)
		local min, max = World.ParkMin, World.ParkMax
		spawnAt[uid] = Vector2.new(math.clamp(p.X, min.X + 3, max.X - 3), math.clamp(p.Z, min.Y + 3, max.Y - 3))
	end
	pet.Placed = true
	if S.CarryService then
		S.CarryService:StopHolding(player)
	end
	changed(player)
	return true, nil
end

function PetService:PickUp(player: Player, uid: string): (boolean, string?)
	local data = S.DataService:GetData(player)
	local pet = data and data.Pets[uid]
	if not data or not pet then
		return false, "That pet is gone"
	end
	pet.Placed = nil
	changed(player)
	return true, nil
end

-- Best: the top earners go out in the park, the rest go in the bag.
function PetService:Best(player: Player): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, nil
	end
	local list = {}
	for uid, pet in data.Pets do
		table.insert(list, { uid = uid, income = PetStats.income(pet) })
	end
	table.sort(list, function(a, b)
		return a.income > b.income
	end)
	local slots = PetService:BaseSlots(player)
	for i, item in list do
		data.Pets[item.uid].Placed = if i <= slots then true else nil
	end
	if S.CarryService then
		S.CarryService:StopHolding(player)
	end
	changed(player)
	return true, nil
end

local function vec(v: any): Vector3?
	return if typeof(v) == "Vector3" then v else nil
end

local ACTIONS: { [string]: (Player, any, any, any) -> (boolean, string?) } = {
	-- Carrying (CarryService): kind "Pet" (arg = uid) or "Egg" (arg = rarity).
	Hold = function(player, _data, kind, arg)
		return S.CarryService:Hold(player, kind, arg)
	end,
	StopHolding = function(player)
		S.CarryService:StopHolding(player)
		return true, nil
	end,
	-- Put down what you hold where you clicked (pets: anywhere in the park, eggs: a free spot).
	PlaceHeld = function(player, _data, pos)
		return S.CarryService:PlaceHeld(player, vec(pos))
	end,
	PickUp = function(player, _data, uid)
		return PetService:PickUp(player, tostring(uid))
	end,
	Place = function(player, _data, uid, pos)
		return PetService:PlacePet(player, tostring(uid), vec(pos))
	end,
	Best = function(player)
		return PetService:Best(player)
	end,
	-- The tutorial's one button and "Place for me": eggs go on free spots by themselves.
	PlaceEggs = function(player)
		return S.HatchService:PlaceAll(player)
	end,
	OpenReady = function(player)
		return S.HatchService:OpenReady(player)
	end,
}

local function onPets(player: Player, action: any, a: any, b: any): (boolean, string?)
	local data = S.DataService:GetData(player)
	local fn = type(action) == "string" and ACTIONS[action]
	if not data or not fn then
		return false, "Bad request"
	end
	return fn(player, data, a, b)
end

-- Offline income on join (Sweep's welcome back card; Double Offline doubles it).
local function welcomeBack(player: Player, session: any)
	local data = session.Data
	if session.IsNewPlayer or data.LastOnline == 0 then
		return
	end
	local away = os.time() - data.LastOnline
	if away < Economy.OfflineMinSeconds then
		return
	end
	local cap = if data.Gamepasses.VIP then Economy.OfflineCapSecondsVIP else Economy.OfflineCapSeconds
	local seconds = math.min(away, cap)
	local amount = PetService:GetIncomePerSec(player) * seconds * Economy.OfflineIncomeRate
	if amount < 1 then
		return
	end
	local paid = S.CashService:Give(player, amount, "Offline")
	session.Runtime.LastOffline = amount
	Net.fire("WelcomeBack", player, { Cash = paid, Seconds = seconds })
end

function PetService:DoubleOffline(player: Player)
	local session = S.DataService:GetSession(player)
	local amount = session and session.Runtime.LastOffline
	if amount then
		session.Runtime.LastOffline = nil
		local paid = S.CashService:Give(player, amount, "DoubleOffline", Enum.AnalyticsEconomyTransactionType.IAP)
		Net.fire("Notify", player, `+{Format.cash(paid)} offline cash!`, "Good")
	end
end

-- Saves from before the carry system: followers become park pets, everyone gets a weight.
local function migrate(player: Player, data: any)
	local slots = PetService:BaseSlots(player)
	local placed = 0
	for _, pet in data.Pets do
		if pet.Placed then
			placed += 1
		end
	end
	for _, pet in data.Pets do
		if pet.Equipped then
			pet.Equipped = nil
			if not pet.Placed and placed < slots then
				pet.Placed = true
				placed += 1
			end
		end
		if pet.Placed and pet.Placed ~= true then
			pet.Placed = true
		end
		local def = Pets.ById[pet.Id]
		if def and type(pet.Weight) ~= "number" then
			pet.Weight = (Pets.Kg[def.Rarity] or 1) * (if pet.Huge then 10 else 1)
		end
	end
end

function PetService:Init(services)
	S = services
	PetModels.load()
	Net.onInvoke("Pets", onPets)
	S.BaseService.BaseAssigned:Connect(function(player)
		local session = S.DataService:GetSession(player)
		if session then
			migrate(player, session.Data)
		end
		PetService:RefreshBase(player)
		if session then
			task.defer(welcomeBack, player, session)
		end
	end)
	S.DataService.ProfileReleasing:Connect(function(player)
		local base = baseOf(player)
		local folder = base and base:FindFirstChild("Pets")
		if folder then
			folder:Destroy()
		end
	end)
end

function PetService:Start()
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(1)
			tick += 1
			for player in S.DataService:GetSessions() do
				local income = PetService:GetIncomePerSec(player)
				if income > 0 then
					local data = S.DataService:GetData(player)
					data.Cash = BigNum.add(data.Cash, income)
					data.CashEarned = BigNum.add(data.CashEarned, income)
					S.AnalyticsService:Income(player, income)
					S.StateService:Mark(player)
				end
				-- Boosts change income: refresh the park tags now and then.
				if tick % 5 == 0 then
					PetService:RefreshBase(player)
				end
			end
		end
	end)
end

return PetService
