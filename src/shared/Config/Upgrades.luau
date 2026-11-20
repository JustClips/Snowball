--!strict
-- Cash upgrades in the Upgrades window (GAME_PLAN §5.8). Rollers live in Config/Rollers.
local Upgrades = {}

-- Snowball Cores: luck + growth of your ball. Level 1 is free.
Upgrades.Cores = {
	{ Id = "Snow", Name = "Snow Core", Luck = 1, Growth = 1, Price = 0 },
	{ Id = "Packed", Name = "Packed Core", Luck = 1.3, Growth = 1.1, Price = 1_000 },
	{ Id = "Ice", Name = "Ice Core", Luck = 1.7, Growth = 1.2, Price = 15_000 },
	{ Id = "Crystal", Name = "Crystal Core", Luck = 2.2, Growth = 1.3, Price = 200_000 },
	{ Id = "Golden", Name = "Golden Core", Luck = 3, Growth = 1.4, Price = 3_000_000 },
	{ Id = "Aurora", Name = "Aurora Core", Luck = 4, Growth = 1.5, Price = 50_000_000 },
}

-- Egg Slots: eggs one ball can carry. Start 1, max 6. Price of the 2nd, 3rd...
Upgrades.EggSlotPrices = { 300, 3_000, 30_000, 300_000, 3_000_000 }
-- Pet Slots on your base: 6 -> 10. Price of the 7th, 8th...
Upgrades.PetSlotPrices = { 2_000, 50_000, 1_000_000, 25_000_000 }
-- Pack Zone: a wider green zone on the pack meter. $50 x 1.5^L, 10 levels.
Upgrades.PackZoneMax = 10
Upgrades.PackGreenBase = 0.14 -- share of the meter that is green at level 0
Upgrades.PackGreenPerLevel = 0.015
Upgrades.PackYellow = 0.16 -- yellow band on each side of green

function Upgrades.packZonePrice(level: number): number
	return math.floor(50 * 1.5 ^ level)
end

function Upgrades.packGreen(level: number): number
	return Upgrades.PackGreenBase + Upgrades.PackGreenPerLevel * math.clamp(level, 0, Upgrades.PackZoneMax)
end

-- What the Upgrades window sells, with the price of the next level (nil = maxed).
function Upgrades.nextPrice(id: string, data: any): number?
	if id == "Core" then
		local def = Upgrades.Cores[data.Core + 1]
		return if def then def.Price else nil
	elseif id == "EggSlots" then
		return Upgrades.EggSlotPrices[data.EggSlots]
	elseif id == "PetSlots" then
		return Upgrades.PetSlotPrices[data.PetSlots - 5]
	elseif id == "PackZone" then
		return if data.PackZone < Upgrades.PackZoneMax then Upgrades.packZonePrice(data.PackZone) else nil
	end
	return nil
end

return Upgrades
