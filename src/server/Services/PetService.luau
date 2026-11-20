--!strict
-- Pets (GAME_PLAN §5.10), ported from Sweep's AlienService: income from pets placed on your
-- base, the training boost from your equipped pets (3, +2 with the pass, they follow you),
-- offline income, and the base pet models. Also answers the "Pets" remote for both pets
-- and eggs (egg actions go to HatchService).
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local PetLook = require(Shared.PetLook)
local Pets = require(Shared.Config.Pets)
local World = require(Shared.Config.World)
local PetModels = require(script.Parent.Parent.Lib.PetModels)

local PetService = {}

local S: any
local mutationMult: { [string]: number } = {}
for _, m in Eggs.Mutations do
	mutationMult[m.Name] = m.IncomeMult
end

local function petIncome(pet: any): number
	local def = Pets.ById[pet.Id]
	if not def then
		return 0
	end
	local mult = (Pets.ZoneMult[pet.Zone or "Meadow"] or 1) * (mutationMult[pet.Mutation or ""] or 1)
	if pet.Huge then
		mult *= Eggs.HugeIncomeMult
	end
	return def.Income * mult
end

local function petTrain(pet: any): number
	local def = Pets.ById[pet.Id]
	if not def then
		return 0
	end
	local mult = (Pets.TrainZoneMult[pet.Zone or "Meadow"] or 1) * math.sqrt(mutationMult[pet.Mutation or ""] or 1)
	if pet.Huge then
		mult *= 3
	end
	return def.Train * mult
end

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

function PetService:BaseSlots(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return Economy.StartPetSlots
	end
	return math.min(World.PetSpotsMax, data.PetSlots) + (if data.Gamepasses.ExtraSlots then 4 else 0)
end

-- $/s from pets on your base and following you, with cash multipliers.
function PetService:GetIncomePerSec(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 0
	end
	local total = 0
	for _, pet in data.Pets do
		if pet.Placed or pet.Equipped then
			total += petIncome(pet)
		end
	end
	return total * S.BoostService:GetCashMult(player)
end

-- Training bonus (0.25 = +25%) from equipped pets.
function PetService:GetTrainBonus(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 0
	end
	local total = 0
	for _, pet in data.Pets do
		if pet.Equipped then
			total += petTrain(pet)
		end
	end
	return total
end

local function count(data: any, field: string): number
	local n = 0
	for _, pet in data.Pets do
		if pet[field] then
			n += 1
		end
	end
	return n
end

local function freeBaseSlot(player: Player, data: any): number?
	local used = {}
	for _, pet in data.Pets do
		if pet.Placed then
			used[pet.Placed] = true
		end
	end
	for i = 1, PetService:BaseSlots(player) do
		if not used[i] then
			return i
		end
	end
	return nil
end

-- Followers: the client draws each player's equipped pets from this attribute.
local function publishFollowers(player: Player)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	local list = {}
	for _, pet in data.Pets do
		if pet.Equipped then
			table.insert(list, { pet.Id, pet.Mutation or "", if pet.Huge then 1 else 0 })
		end
	end
	player:SetAttribute("Followers", HttpService:JSONEncode(list))
end

-- Base pet models on their slots (static; the client adds the idle bob).
function PetService:RefreshBase(player: Player)
	local data = S.DataService:GetData(player)
	local index = player:GetAttribute("BaseIndex")
	local base = type(index) == "number" and S.WorldService:GetBase(index)
	if not data or not base then
		return
	end
	local old = base:FindFirstChild("Pets")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Pets"
	local slots = PetService:BaseSlots(player)
	for _, pet in data.Pets do
		if pet.Placed and pet.Placed > slots then
			pet.Placed = freeBaseSlot(player, data) -- slots shrank (pass refunded...)
		end
		if pet.Placed then
			local model = PetLook.make(pet.Id, pet.Mutation, pet.Huge)
			if model then
				model:PivotTo(World.petSpot(index :: number, pet.Placed) * CFrame.Angles(0, math.pi, 0))
				model:SetAttribute("PetBob", true)
				model.Parent = folder
			end
		end
	end
	folder.Parent = base
	publishFollowers(player)
	S.StateService:Mark(player)
end

-- Adds a pet. It goes to a free equip slot, then a free base slot, else the bag.
function PetService:GivePet(player: Player, petId: string, fields: { [string]: any }?): string?
	local data = S.DataService:GetData(player)
	if not data or not Pets.ById[petId] then
		return nil
	end
	local uid = S.DataService:NewUid(data, "p")
	local pet: any = { Id = petId, Zone = "Meadow" }
	for k, v in fields or {} do
		pet[k] = v
	end
	data.Pets[uid] = pet
	data.Index[petId] = true
	if count(data, "Equipped") < PetService:EquipSlots(player) then
		pet.Equipped = true
	end
	pet.Placed = freeBaseSlot(player, data)
	S.InventoryService:Bump(player)
	PetService:RefreshBase(player)
	return uid
end

-- Equip the pets with the best training boost, place the best earners.
local function best(player: Player, data: any)
	local list = {}
	for uid, pet in data.Pets do
		pet.Equipped = nil
		pet.Placed = nil
		table.insert(list, { uid = uid, train = petTrain(pet), income = petIncome(pet) })
	end
	table.sort(list, function(a, b)
		return a.train > b.train
	end)
	for i = 1, math.min(#list, PetService:EquipSlots(player)) do
		data.Pets[list[i].uid].Equipped = true
	end
	table.sort(list, function(a, b)
		return a.income > b.income
	end)
	for i = 1, math.min(#list, PetService:BaseSlots(player)) do
		data.Pets[list[i].uid].Placed = i
	end
end

local ACTIONS: { [string]: (Player, any, any) -> (boolean, string?) } = {
	Equip = function(player, data, uid)
		local pet = data.Pets[uid]
		if not pet then
			return false, nil
		end
		if not pet.Equipped and count(data, "Equipped") >= PetService:EquipSlots(player) then
			return false, "All equip slots are full"
		end
		pet.Equipped = true
		return true, nil
	end,
	Unequip = function(_player, data, uid)
		local pet = data.Pets[uid]
		if pet then
			pet.Equipped = nil
		end
		return pet ~= nil, nil
	end,
	Place = function(player, data, uid)
		local pet = data.Pets[uid]
		if not pet then
			return false, nil
		end
		if pet.Placed then
			return true, nil
		end
		local slot = freeBaseSlot(player, data)
		if not slot then
			return false, "Your base is full: buy Pet Slots in Upgrades"
		end
		pet.Placed = slot
		return true, nil
	end,
	Unplace = function(_player, data, uid)
		local pet = data.Pets[uid]
		if pet then
			pet.Placed = nil
		end
		return pet ~= nil, nil
	end,
	Best = function(player, data)
		best(player, data)
		return true, nil
	end,
	PlaceEgg = function(player, _data, uid)
		return S.HatchService:Place(player, uid)
	end,
	PlaceEggs = function(player)
		return S.HatchService:PlaceAll(player)
	end,
	OpenReady = function(player)
		return S.HatchService:OpenReady(player)
	end,
}

local function onPets(player: Player, action: any, arg: any): (boolean, string?)
	local data = S.DataService:GetData(player)
	local fn = type(action) == "string" and ACTIONS[action]
	if not data or not fn then
		return false, "Bad request"
	end
	local ok, why = fn(player, data, arg)
	if ok and action ~= "PlaceEgg" and action ~= "PlaceEggs" and action ~= "OpenReady" then
		S.InventoryService:Bump(player)
		PetService:RefreshBase(player)
	end
	return ok, why
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

function PetService:Init(services)
	S = services
	PetModels.load()
	Net.onInvoke("Pets", onPets)
	S.BaseService.BaseAssigned:Connect(function(player)
		PetService:RefreshBase(player)
		local session = S.DataService:GetSession(player)
		if session then
			task.defer(welcomeBack, player, session)
		end
	end)
	S.DataService.ProfileReleasing:Connect(function(player)
		local index = player:GetAttribute("BaseIndex")
		local base = type(index) == "number" and S.WorldService:GetBase(index)
		local folder = base and base:FindFirstChild("Pets")
		if folder then
			folder:Destroy()
		end
	end)
end

function PetService:Start()
	task.spawn(function()
		while true do
			task.wait(1)
			for player in S.DataService:GetSessions() do
				local income = PetService:GetIncomePerSec(player)
				if income > 0 then
					local data = S.DataService:GetData(player)
					data.Cash = BigNum.add(data.Cash, income)
					data.CashEarned = BigNum.add(data.CashEarned, income)
					S.AnalyticsService:Income(player, income)
					S.StateService:Mark(player)
				end
			end
		end
	end)
end

return PetService
