--!strict
-- The egg bag: frozen eggs from runs, pops and purchases wait here until you place them
-- on your base (HatchService). Pets live in data.Pets (PetService).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)
local Zones = require(Shared.Config.Zones)

local InventoryService = {}

local S: any
local rng = Random.new()
local versions: { [Player]: number } = {}

-- Bumped whenever Eggs/Pets/Hatching change, so StateService resends those tables.
function InventoryService:Bump(player: Player)
	versions[player] = (versions[player] or 0) + 1
	S.StateService:Mark(player)
end

function InventoryService:GetVersion(player: Player): number
	return versions[player] or 0
end

local function eggCount(data: any): number
	local n = 0
	for _ in data.Eggs do
		n += 1
	end
	return n
end

function InventoryService:HasEggRoom(player: Player): boolean
	local data = S.DataService:GetData(player)
	return data ~= nil and eggCount(data) < Eggs.BagSize
end

function InventoryService:RollRarity(zoneId: string, luck: number, floor: string?): string
	local pool = Eggs.Pools[zoneId] or Eggs.Pools.Meadow
	return Eggs.roll(rng, pool, luck, floor)
end

-- Adds an egg to the bag. Returns its uid, or nil if the bag is full.
function InventoryService:AddEgg(player: Player, rarity: string, zoneId: string, source: string): string?
	local data = S.DataService:GetData(player)
	if not data then
		return nil
	end
	if eggCount(data) >= Eggs.BagSize then
		Net.fire("Notify", player, "Your egg bag is full! Place some eggs on your base.", "Bad")
		return nil
	end
	local uid = S.DataService:NewUid(data, "e")
	data.Eggs[uid] = { Rarity = rarity, Zone = zoneId, Source = source }
	data.Stats.EggsFound += 1
	S.AnalyticsService:Funnel(player, "FirstEgg")
	S.AnalyticsService:Custom(player, "EggFound", 1, { Rarity = rarity, Zone = zoneId, Source = source })
	InventoryService:Bump(player)
	return uid
end

-- An egg from a zone (by index), rolled with the player's luck. Returns the rarity.
function InventoryService:AddZoneEgg(player: Player, zoneIndex: number, source: string, floor: string?): string
	local zone = Zones.List[zoneIndex] or Zones.List[1]
	local rarity = InventoryService:RollRarity(zone.Id, S.BoostService:GetLuck(player), floor)
	InventoryService:AddEgg(player, rarity, zone.Id, source)
	return rarity
end

function InventoryService:Init(services)
	S = services
	Players.PlayerRemoving:Connect(function(player)
		versions[player] = nil
	end)
end

return InventoryService
