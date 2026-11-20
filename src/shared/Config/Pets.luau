--!strict
-- Pets (GAME_PLAN §5.10). Every pet is an animal from Dev's StudAnimalPack_100
-- (Model = the pack model name). Income is $/s on your base; Train is the training boost
-- an equipped pet gives (+0.05 = +5%). Both scale with the zone the egg came from.
export type PetDef = {
	Id: string,
	Name: string,
	Model: string,
	Rarity: string,
	Income: number,
	Train: number,
	Body: string, -- shared bone animation set: "Quad" | "Bird" | "Sea" | "Biped"
	Exclusive: string?, -- not from zone eggs: "Daily" | "Huge" | "Christmas"
	Scale: number?,
}

local function pet(id: string, rarity: string, income: number, train: number, body: string, extra: any?): PetDef
	local def: any = { Id = id, Name = id, Model = id, Rarity = rarity, Income = income, Train = train, Body = body }
	for k, v in extra or {} do
		def[k] = v
	end
	return def
end

local List: { PetDef } = {
	pet("Rabbit", "Common", 1, 0.05, "Quad"),
	pet("Mouse", "Common", 1, 0.05, "Quad"),
	pet("Hamster", "Common", 1, 0.05, "Quad"),
	pet("Chipmunk", "Common", 1, 0.05, "Quad"),
	pet("Squirrel", "Uncommon", 2.5, 0.10, "Quad"),
	pet("Duck", "Uncommon", 2.5, 0.10, "Bird"),
	pet("Sheep", "Uncommon", 2.5, 0.10, "Quad"),
	pet("Hedgehog", "Uncommon", 2.5, 0.10, "Quad"),
	pet("Fox", "Rare", 6, 0.20, "Quad"),
	pet("Raccoon", "Rare", 6, 0.20, "Quad"),
	pet("Owl", "Rare", 6, 0.20, "Bird"),
	pet("Beaver", "Rare", 6, 0.20, "Quad"),
	pet("Penguin", "Epic", 15, 0.40, "Bird"),
	pet("Seal", "Epic", 15, 0.40, "Sea"),
	pet("Otter", "Epic", 15, 0.40, "Quad"),
	pet("Wolf", "Epic", 15, 0.40, "Quad"),
	pet("ArcticFox", "Legendary", 40, 0.80, "Quad", { Name = "Arctic Fox" }),
	pet("Walrus", "Legendary", 40, 0.80, "Sea"),
	pet("Moose", "Legendary", 40, 0.80, "Quad"),
	pet("Bear", "Legendary", 40, 0.80, "Quad"),
	pet("PolarBear", "Mythic", 120, 1.50, "Quad", { Name = "Polar Bear" }),
	pet("Orca", "Mythic", 120, 1.50, "Sea"),
	pet("Narwhal", "Mythic", 120, 1.50, "Sea"),
	pet("Reindeer", "Mythic", 120, 1.50, "Quad"),
	pet("Mammoth", "Secret", 600, 4.00, "Quad"),
	pet("Dragon", "Secret", 600, 4.00, "Quad"),
	-- Exclusives
	pet("RedPanda", "Epic", 20, 0.50, "Quad", { Name = "Red Panda", Exclusive = "Daily" }),
	pet(
		"HugePenguin",
		"Legendary",
		150,
		1.0,
		"Bird",
		{ Name = "Huge Penguin", Model = "Penguin", Exclusive = "Huge", Scale = 2.5 }
	),
	pet(
		"HugeWolf",
		"Mythic",
		500,
		2.0,
		"Quad",
		{ Name = "Huge Wolf", Model = "Wolf", Exclusive = "Huge", Scale = 2.5 }
	),
	pet(
		"HugePolarBear",
		"Mythic",
		1500,
		4.0,
		"Quad",
		{ Name = "Huge Polar Bear", Model = "PolarBear", Exclusive = "Huge", Scale = 2.5 }
	),
	pet(
		"HugeDragon",
		"Secret",
		5000,
		8.0,
		"Quad",
		{ Name = "Huge Dragon", Model = "Dragon", Exclusive = "Huge", Scale = 2.5 }
	),
	-- Christmas Egg (update 13 Dec, off until then)
	pet("Panda", "Rare", 10, 0.30, "Quad", { Exclusive = "Christmas" }),
	pet("Koala", "Rare", 10, 0.30, "Quad", { Exclusive = "Christmas" }),
	pet("Llama", "Epic", 25, 0.60, "Quad", { Exclusive = "Christmas" }),
	pet("Swan", "Epic", 25, 0.60, "Bird", { Exclusive = "Christmas" }),
	pet("Goose", "Legendary", 70, 1.20, "Bird", { Exclusive = "Christmas" }),
	pet("Tiger", "Mythic", 200, 2.50, "Quad", { Exclusive = "Christmas" }),
}

local Pets = {
	List = List,
	ById = {} :: { [string]: PetDef },
	ByRarity = {} :: { [string]: { PetDef } }, -- zone egg pets only
	-- Zone the egg came from -> income/training scale (GAME_PLAN §5.10).
	ZoneMult = { Meadow = 1, Pine = 3, Lake = 9, Cave = 27, Aurora = 80, Village = 120 } :: { [string]: number },
	TrainZoneMult = { Meadow = 1, Pine = 1.3, Lake = 1.7, Cave = 2.2, Aurora = 3, Village = 4 } :: { [string]: number },
}
-- Weight (Steal an Egg style): every pet rolls a weight when it hatches. Heavier pets
-- are drawn a bit bigger and earn a bit more (PetStats.weightMult). Kg = a normal pet of
-- that rarity; Huge pets weigh x10.
Pets.Kg = {
	Common = 1.2,
	Uncommon = 2.5,
	Rare = 5,
	Epic = 10,
	Legendary = 20,
	Mythic = 45,
	Secret = 90,
} :: { [string]: number }

-- A weight for a new pet: mostly near normal, now and then a heavy one (up to x2.2).
function Pets.rollWeight(rng: Random, def: PetDef, huge: boolean?): number
	local base = (Pets.Kg[def.Rarity] or 1) * (if huge then 10 else 1)
	local u = rng:NextNumber()
	local f = 0.8 + 0.5 * u ^ 2
	if rng:NextNumber() < 0.05 then
		f = rng:NextNumber(1.4, 2.2) -- a "Big" one
	end
	return math.floor(base * f * 10 + 0.5) / 10
end

for _, def in List do
	Pets.ById[def.Id] = def
	if not def.Exclusive then
		Pets.ByRarity[def.Rarity] = Pets.ByRarity[def.Rarity] or {}
		table.insert(Pets.ByRarity[def.Rarity], def)
	end
end

return Pets
