--!strict
-- Frozen eggs (GAME_PLAN §5.9): rarities, zone pools, hatch times, mutations, Huge.
export type RarityDef = { Name: string, Order: number, HatchSeconds: number, Color: Color3 }
export type MutationDef = { Name: string, Chance: number, IncomeMult: number, Color: Color3 }

local Rarities: { RarityDef } = {
	{ Name = "Common", Order = 1, HatchSeconds = 10, Color = Color3.fromRGB(200, 205, 215) },
	{ Name = "Uncommon", Order = 2, HatchSeconds = 30, Color = Color3.fromRGB(90, 220, 110) },
	{ Name = "Rare", Order = 3, HatchSeconds = 90, Color = Color3.fromRGB(70, 150, 255) },
	{ Name = "Epic", Order = 4, HatchSeconds = 240, Color = Color3.fromRGB(170, 90, 255) },
	{ Name = "Legendary", Order = 5, HatchSeconds = 600, Color = Color3.fromRGB(255, 200, 40) },
	{ Name = "Mythic", Order = 6, HatchSeconds = 1500, Color = Color3.fromRGB(255, 60, 90) },
	{ Name = "Secret", Order = 7, HatchSeconds = 3600, Color = Color3.fromRGB(40, 40, 50) },
}

-- Checked rarest first: 1 in Chance.
local Mutations: { MutationDef } = {
	{ Name = "Aurora", Chance = 500, IncomeMult = 5, Color = Color3.fromRGB(150, 255, 200) },
	{ Name = "Crystal", Chance = 100, IncomeMult = 3, Color = Color3.fromRGB(200, 240, 255) },
	{ Name = "Frosty", Chance = 20, IncomeMult = 2, Color = Color3.fromRGB(150, 210, 255) },
}

-- Weights per zone (§5.9). The Village row is the Village bonus egg.
local Pools: { [string]: { [string]: number } } = {
	Meadow = { Common = 75, Uncommon = 25 },
	Pine = { Common = 55, Uncommon = 30, Rare = 15 },
	Lake = { Common = 40, Uncommon = 32, Rare = 20, Epic = 8 },
	Cave = { Common = 30, Uncommon = 30, Rare = 24, Epic = 12, Legendary = 4 },
	Aurora = { Common = 22, Uncommon = 28, Rare = 26, Epic = 15, Legendary = 7, Mythic = 2 },
	Village = { Uncommon = 30, Rare = 30, Epic = 22, Legendary = 12, Mythic = 5.9, Secret = 0.1 },
}

local Eggs = {
	Rarities = Rarities,
	ByName = {} :: { [string]: RarityDef },
	Mutations = Mutations,
	Pools = Pools,
	FirstEggSeconds = 3, -- a brand-new player's first egg hatches this fast
	FastHatchMult = 0.5, -- Fast Hatch pass
	HugeChance = 1000, -- 1 in N on Legendary and up
	HugeMinOrder = 5,
	HugeIncomeMult = 10,
	-- Bought eggs (Products): the lowest rarity they can hatch.
	BoughtFloor = { Frozen = "Epic", Aurora = "Legendary" },
	BagSize = 40,
}
for _, r in Rarities do
	Eggs.ByName[r.Name] = r
end

-- Rolls a rarity from a zone pool. luck >= 1 shifts weight to the rarer tiers.
function Eggs.roll(rng: Random, pool: { [string]: number }, luck: number, floor: string?): string
	local floorOrder = if floor then Eggs.ByName[floor].Order else 0
	local total = 0
	local weights: { [string]: number } = {}
	for _, r in Rarities do
		local w = pool[r.Name] or 0
		if r.Order < floorOrder then
			w = 0
		elseif w > 0 then
			w *= math.max(1, luck) ^ ((r.Order - 1) * 0.5)
		end
		weights[r.Name] = w
		total += w
	end
	if total <= 0 then
		return floor or "Common"
	end
	local roll = rng:NextNumber() * total
	for _, r in Rarities do
		roll -= weights[r.Name]
		if roll <= 0 and weights[r.Name] > 0 then
			return r.Name
		end
	end
	return floor or "Common"
end

function Eggs.rollMutation(rng: Random, luck: number): string?
	for _, m in Mutations do
		if rng:NextNumber() < math.min(0.5, luck / m.Chance) then
			return m.Name
		end
	end
	return nil
end

function Eggs.hatchSeconds(rarity: string): number
	local def = Eggs.ByName[rarity]
	return if def then def.HatchSeconds else 10
end

return Eggs
