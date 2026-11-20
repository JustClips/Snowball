--!strict
-- Snow Rollers (GAME_PLAN §5.1): the training machine next to every base.
-- Cash rollers are a ladder bought one by one; Robux rollers multiply your best cash roller.
-- Model keys (Config/Assets) are "Roller_<Id>"; until those are uploaded a graybox is used.
local Types = require(script.Parent.Parent.Types)

local Cash: { Types.RollerDef } = {
	{
		Index = 1,
		Id = "Wooden",
		Name = "Wooden Roller",
		Power = 5,
		Price = 0,
		RebirthsNeeded = 0,
		Color = Color3.fromRGB(150, 105, 65),
	},
	{
		Index = 2,
		Id = "Stone",
		Name = "Stone Roller",
		Power = 15,
		Price = 400,
		RebirthsNeeded = 0,
		Color = Color3.fromRGB(130, 130, 135),
	},
	{
		Index = 3,
		Id = "Iron",
		Name = "Iron Roller",
		Power = 50,
		Price = 1_500,
		RebirthsNeeded = 0,
		Color = Color3.fromRGB(95, 100, 110),
	},
	{
		Index = 4,
		Id = "Gold",
		Name = "Gold Roller",
		Power = 175,
		Price = 25_000,
		RebirthsNeeded = 0,
		Color = Color3.fromRGB(240, 190, 60),
	},
	{
		Index = 5,
		Id = "Crystal",
		Name = "Crystal Roller",
		Power = 600,
		Price = 300_000,
		RebirthsNeeded = 0,
		Color = Color3.fromRGB(150, 220, 255),
	},
	{
		Index = 6,
		Id = "Diamond",
		Name = "Diamond Roller",
		Power = 2_000,
		Price = 4_000_000,
		RebirthsNeeded = 0,
		Color = Color3.fromRGB(120, 245, 240),
	},
	{
		Index = 7,
		Id = "Aurora",
		Name = "Aurora Roller",
		Power = 7_500,
		Price = 60_000_000,
		RebirthsNeeded = 0,
		Color = Color3.fromRGB(140, 255, 170),
	},
	{
		Index = 8,
		Id = "Glacier",
		Name = "Glacier Roller",
		Power = 30_000,
		Price = 1_000_000_000,
		RebirthsNeeded = 2,
		Color = Color3.fromRGB(80, 150, 255),
	},
}

local Robux: { Types.RobuxRollerDef } = {
	{
		Index = 1,
		Id = "CandyCane",
		Name = "Candy Cane Roller",
		Mult = 1.5,
		Product = "RollerCandyCane",
		Color = Color3.fromRGB(235, 60, 70),
	},
	{
		Index = 2,
		Id = "Golden",
		Name = "Golden Roller",
		Mult = 2,
		Product = "RollerGolden",
		Color = Color3.fromRGB(255, 205, 40),
	},
	{
		Index = 3,
		Id = "NorthernLights",
		Name = "Northern Lights Roller",
		Mult = 3,
		Product = "RollerNorthernLights",
		Color = Color3.fromRGB(90, 255, 180),
	},
	{
		Index = 4,
		Id = "Galaxy",
		Name = "Galaxy Roller",
		Mult = 5,
		Product = "RollerGalaxy",
		Color = Color3.fromRGB(120, 70, 220),
	},
	{
		Index = 5,
		Id = "Divine",
		Name = "Divine Roller",
		Mult = 10,
		Product = "RollerDivine",
		Color = Color3.fromRGB(255, 250, 230),
	},
	-- Not in the one-by-one ladder (Dev 2026-11-20: "admin/gamepass versions"):
	{
		Index = 6,
		Id = "Frostfire",
		Name = "Frostfire Roller",
		Mult = 4,
		Product = "",
		Pass = "FrostfireRoller",
		Color = Color3.fromRGB(255, 110, 60),
	},
	{
		Index = 7,
		Id = "Admin",
		Name = "Admin Roller",
		Mult = 25,
		Product = "",
		Admin = true,
		Color = Color3.fromRGB(30, 30, 40),
	},
}

local Rollers = {
	Cash = Cash,
	Robux = Robux,
	FreeInTutorial = 2, -- the Stone Roller is free while the tutorial runs
	RobuxById = {} :: { [string]: Types.RobuxRollerDef },
}
for _, def in Robux do
	Rollers.RobuxById[def.Id] = def
end

function Rollers.get(index: number): Types.RollerDef?
	return Cash[index]
end

-- The best Robux roller multiplier the player owns (they stack by best, not by product).
function Rollers.robuxMult(owned: { [string]: boolean }): number
	local best = 1
	for _, def in Robux do
		if owned[def.Id] and def.Mult > best then
			best = def.Mult
		end
	end
	return best
end

-- Every special roller the player has: bought ones, the gamepass one, the admin one.
function Rollers.ownedSet(data: any, isAdmin: boolean): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	for id, v in data.RobuxRollers do
		owned[id] = v
	end
	for _, def in Robux do
		if (def.Pass and data.Gamepasses[def.Pass]) or (def.Admin and isAdmin) then
			owned[def.Id] = true
		end
	end
	return owned
end

-- The next Robux roller to sell (one by one, in order), or nil when all are owned.
function Rollers.nextRobux(owned: { [string]: boolean }): Types.RobuxRollerDef?
	for _, def in Robux do
		if not def.Pass and not def.Admin and not owned[def.Id] then
			return def
		end
	end
	return nil
end

-- The roller the player sees on their base: their best Robux one if they own any, else cash.
function Rollers.lookId(cashIndex: number, owned: { [string]: boolean }): string
	local best: Types.RobuxRollerDef? = nil
	for _, def in Robux do
		if owned[def.Id] and (best == nil or def.Mult > (best :: Types.RobuxRollerDef).Mult) then
			best = def
		end
	end
	if best then
		return best.Id
	end
	local def = Cash[cashIndex] or Cash[1]
	return def.Id
end

return Rollers
