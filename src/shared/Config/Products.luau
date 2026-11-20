--!strict
-- Gamepasses and developer products (GAME_PLAN §6).
-- Id 0 = not created yet (TODO(Dev): create with tools/create_products.py once the
-- universe exists): its button stays hidden and the server warns once.
export type ProductDef = { [string]: any }

local Gamepasses: { ProductDef } = {
	{ Key = "Train2x", Id = 0, Price = 149, Name = "2x Training", Description = "All training x2, forever." },
	{ Key = "Cash2x", Id = 0, Price = 99, Name = "2x Cash", Description = "All cash x2, forever." },
	{
		Key = "AutoTrain",
		Id = 0,
		Price = 129,
		Name = "Fast Train",
		Description = "Your roller trains 2x as fast, forever.",
	},
	{
		Key = "PopMagnet",
		Id = 0,
		Price = 99,
		Name = "Pop Magnet",
		Description = "Free Snow Pops are claimed for you while you train.",
	},
	{ Key = "Lucky", Id = 0, Price = 149, Name = "Lucky", Description = "+50% luck forever." },
	{
		Key = "GoldenSnowball",
		Id = 0,
		Price = 249,
		Name = "Golden Snowball",
		Description = "A gold ball: x2 coins and it smashes obstacles 1.5x its size.",
	},
	{
		Key = "VIP",
		Id = 0,
		Price = 249,
		Name = "VIP",
		Description = "+20% cash, +10% luck, VIP tag, 12 h offline cash and a daily gift.",
	},
	{
		Key = "ExtraEquips",
		Id = 0,
		Price = 199,
		Name = "+2 Pet Equips",
		Description = "5 pets follow you and boost training instead of 3.",
	},
	{ Key = "ExtraSlots", Id = 0, Price = 199, Name = "+4 Pet Slots", Description = "4 more pets on your base." },
	{ Key = "FastHatch", Id = 0, Price = 229, Name = "Fast Hatch", Description = "All hatch timers halved." },
}

local function p(
	key: string,
	price: number,
	name: string,
	kind: string,
	giftable: boolean,
	extra: { [string]: any }?
): ProductDef
	local def: ProductDef = { Key = key, Id = 0, Price = price, Name = name, Kind = kind, Giftable = giftable }
	for k, v in extra or {} do
		def[k] = v
	end
	return def
end

local Products: { ProductDef } = {
	p("StarterPack", 9, "Starter Pack", "StarterPack", false),
	-- Rainbow Pops: only from the on-screen pop (PopService)
	p("RainbowPop25", 19, "Rainbow Pop x25", "RainbowPop", false, { Mult = 25, Seconds = 120 }),
	p("RainbowPop50", 39, "Rainbow Pop x50", "RainbowPop", false, { Mult = 50, Seconds = 120 }),
	p("RainbowPop100", 79, "Rainbow Pop x100", "RainbowPop", false, { Mult = 100, Seconds = 120 }),
	-- Robux Snow Rollers, one by one
	p("RollerCandyCane", 29, "Candy Cane Roller", "RobuxRoller", true, { Roller = "CandyCane" }),
	p("RollerGolden", 89, "Golden Roller", "RobuxRoller", true, { Roller = "Golden" }),
	p("RollerNorthernLights", 249, "Northern Lights Roller", "RobuxRoller", true, { Roller = "NorthernLights" }),
	p("RollerGalaxy", 599, "Galaxy Roller", "RobuxRoller", true, { Roller = "Galaxy" }),
	p("RollerDivine", 1499, "Divine Roller", "RobuxRoller", true, { Roller = "Divine" }),
	-- Training time and Power
	p("TrainTime5", 39, "5 min of Training", "TrainTime", true, { Minutes = 5 }),
	p("TrainTime15", 99, "15 min of Training", "TrainTime", true, { Minutes = 15 }),
	p("TrainTime30", 179, "30 min of Training", "TrainTime", true, { Minutes = 30 }),
	p("PowerPack1", 3, "Power Pack I", "PowerPack", true, { Taps = 48 }),
	p("PowerPack2", 9, "Power Pack II", "PowerPack", true, { Taps = 192 }),
	p("PowerPack3", 39, "Power Pack III", "PowerPack", true, { Taps = 960 }),
	p("PowerPack4", 99, "Power Pack IV", "PowerPack", true, { Taps = 2_880 }),
	p("Train2xBoost", 29, "2x Training (10 min)", "Boost", true, { Boost = "Train2x", Minutes = 10 }),
	p("Cash2xBoost", 25, "2x Cash (15 min)", "Boost", true, { Boost = "Cash2x", Minutes = 15 }),
	-- Lucky Rolls
	p("LuckyRoll3", 27, "3 Lucky Rolls", "LuckyRoll", true, { Count = 3 }),
	p("LuckyRoll10", 69, "10 Lucky Rolls", "LuckyRoll", true, { Count = 10 }),
	p("LuckyRoll35", 199, "35 Lucky Rolls", "LuckyRoll", true, { Count = 35 }),
	p("LuckyRoll100", 499, "100 Lucky Rolls", "LuckyRoll", true, { Count = 100 }),
	p("SuperLuckyRoll", 9, "Super Lucky Roll", "SuperLucky", true, { Count = 1 }),
	-- Server Luck (15 min, whole server)
	p("ServerLuck2", 19, "2x Server Luck", "ServerLuck", false, { Mult = 2, Minutes = 15 }),
	p("ServerLuck4", 39, "4x Server Luck", "ServerLuck", false, { Mult = 4, Minutes = 15 }),
	p("ServerLuck8", 79, "8x Server Luck", "ServerLuck", false, { Mult = 8, Minutes = 15 }),
	p("ServerLuck16", 159, "16x Server Luck", "ServerLuck", false, { Mult = 16, Minutes = 15 }),
	-- Golden Snowball rentals
	p("GoldenRuns1", 9, "Golden Snowball (1 run)", "GoldenRuns", true, { Count = 1 }),
	p("GoldenRuns5", 39, "Golden Snowball (5 runs)", "GoldenRuns", true, { Count = 5 }),
	p("GoldenRuns20", 129, "Golden Snowball (20 runs)", "GoldenRuns", true, { Count = 20 }),
	-- Eggs
	p("FrozenEgg1", 49, "Frozen Egg", "EggPack", true, { Egg = "Frozen", Count = 1 }),
	p("FrozenEgg3", 129, "3 Frozen Eggs", "EggPack", true, { Egg = "Frozen", Count = 3 }),
	p("FrozenEgg10", 399, "10 Frozen Eggs", "EggPack", true, { Egg = "Frozen", Count = 10 }),
	p("AuroraEgg1", 99, "Aurora Egg", "EggPack", true, { Egg = "Aurora", Count = 1 }),
	p("AuroraEgg3", 249, "3 Aurora Eggs", "EggPack", true, { Egg = "Aurora", Count = 3 }),
	p("AuroraEgg10", 799, "10 Aurora Eggs", "EggPack", true, { Egg = "Aurora", Count = 10 }),
	-- Huge pets
	p("HugePenguin", 99, "Huge Penguin", "HugePet", true, { Pet = "HugePenguin" }),
	p("HugeWolf", 499, "Huge Wolf", "HugePet", true, { Pet = "HugeWolf" }),
	p("HugePolarBear", 1999, "Huge Polar Bear", "HugePet", true, { Pet = "HugePolarBear" }),
	p("HugeDragon", 4999, "Huge Dragon", "HugePet", true, { Pet = "HugeDragon" }),
	-- Skip Hatch (Sweep's tested prices)
	p("SkipHatchCommon", 3, "Skip Hatch (Common)", "SkipHatch", true, { Rarity = "Common" }),
	p("SkipHatchUncommon", 5, "Skip Hatch (Uncommon)", "SkipHatch", true, { Rarity = "Uncommon" }),
	p("SkipHatchRare", 9, "Skip Hatch (Rare)", "SkipHatch", true, { Rarity = "Rare" }),
	p("SkipHatchEpic", 19, "Skip Hatch (Epic)", "SkipHatch", true, { Rarity = "Epic" }),
	p("SkipHatchLegendary", 35, "Skip Hatch (Legendary)", "SkipHatch", true, { Rarity = "Legendary" }),
	p("SkipHatchMythic", 59, "Skip Hatch (Mythic)", "SkipHatch", true, { Rarity = "Mythic" }),
	p("SkipHatchSecret", 89, "Skip Hatch (Secret)", "SkipHatch", true, { Rarity = "Secret" }),
	-- Cash packs (scaled to income, Sweep's floor rules)
	p("Cash1", 25, "Pile of Cash", "CashPack", true, { Seconds = 600, FloorFactor = 0.5 }),
	p("Cash2", 59, "Bag of Cash", "CashPack", true, { Seconds = 1_800, FloorFactor = 1 }),
	p("Cash3", 149, "Crate of Cash", "CashPack", true, { Seconds = 5_400, FloorFactor = 2 }),
	p("Cash4", 399, "Vault of Cash", "CashPack", true, { Seconds = 18_000, FloorFactor = 5 }),
	-- Server events and the rest
	p("TriggerAvalanche", 149, "Avalanche Now", "Avalanche", false),
	-- Lucky Wheel spins (sold in the wheel window, not the Shop)
	p("WheelSpin1", 19, "1 Wheel Spin", "WheelSpins", true, { Count = 1 }),
	p("WheelSpin5", 79, "5 Wheel Spins", "WheelSpins", true, { Count = 5 }),
	p("WheelSpin10", 149, "10 Wheel Spins", "WheelSpins", true, { Count = 10 }),
	p("SkipRebirth", 79, "Skip Rebirth", "SkipRebirth", false),
	p("DoubleOffline", 49, "Double Offline Cash", "DoubleOffline", false),
}

local Config = {
	Gamepasses = Gamepasses,
	Products = Products,
	PassByKey = {} :: { [string]: ProductDef },
	PassById = {} :: { [number]: ProductDef },
	ProductByKey = {} :: { [string]: ProductDef },
	ProductById = {} :: { [number]: ProductDef },
	GiftWindowSeconds = 120,
	-- Regional pricing stays off for these (one buyer's price covers the whole server).
	FullPriceKinds = { ServerLuck = true, Avalanche = true } :: { [string]: boolean },
}
for _, def in Gamepasses do
	Config.PassByKey[def.Key] = def
	if def.Id ~= 0 then
		Config.PassById[def.Id] = def
	end
end
for _, def in Products do
	Config.ProductByKey[def.Key] = def
	if def.Id ~= 0 then
		Config.ProductById[def.Id] = def
	end
end

return Config
