--!strict
-- Zones by distance down the mountain (GAME_PLAN §5.7). No gates: roll far enough.
-- Power is what you need to reach the zone's Start with a Perfect, clean roll (§5.2).
local Types = require(script.Parent.Parent.Types)

local List: { Types.ZoneDef } = {
	{
		Index = 1,
		Id = "Meadow",
		Name = "Summit Meadow",
		Start = 0,
		Power = 0,
		CoinValue = 1,
		IncomeMult = 1,
		Color = Color3.fromRGB(120, 200, 255),
		GroundColor = Color3.fromRGB(240, 246, 255),
	},
	{
		Index = 2,
		Id = "Pine",
		Name = "Pine Forest",
		Start = 400,
		Power = 1_000,
		CoinValue = 3,
		IncomeMult = 3,
		Color = Color3.fromRGB(70, 170, 90),
		GroundColor = Color3.fromRGB(232, 242, 238),
	},
	{
		Index = 3,
		Id = "Lake",
		Name = "Frozen Lake",
		Start = 1_000,
		Power = 25_000,
		CoinValue = 9,
		IncomeMult = 9,
		Color = Color3.fromRGB(90, 200, 230),
		GroundColor = Color3.fromRGB(190, 230, 250),
	},
	{
		Index = 4,
		Id = "Cave",
		Name = "Ice Cave",
		Start = 2_000,
		Power = 400_000,
		CoinValue = 25,
		IncomeMult = 27,
		Color = Color3.fromRGB(80, 120, 255),
		GroundColor = Color3.fromRGB(200, 215, 245),
	},
	{
		Index = 5,
		Id = "Aurora",
		Name = "Aurora Valley",
		Start = 3_500,
		Power = 5_000_000,
		CoinValue = 70,
		IncomeMult = 80,
		Color = Color3.fromRGB(150, 90, 255),
		GroundColor = Color3.fromRGB(225, 225, 250),
	},
	{
		Index = 6,
		Id = "Village",
		Name = "The Village",
		Start = 5_500,
		Power = 50_000_000,
		CoinValue = 120,
		IncomeMult = 120,
		Color = Color3.fromRGB(255, 170, 70),
		GroundColor = Color3.fromRGB(245, 240, 235),
	},
}

local Zones = {
	List = List,
	ById = {} :: { [string]: Types.ZoneDef },
	MinRoll = 150, -- a roll with 1 Power still goes this far
	VillageWall = 5_560, -- the snowman wall: reaching it ends the run with the Village bonus
}
for _, z in List do
	Zones.ById[z.Id] = z
end

-- The zone at distance s (studs along the track).
function Zones.at(s: number): Types.ZoneDef
	local found = List[1]
	for _, z in List do
		if s >= z.Start then
			found = z
		end
	end
	return found
end

return Zones
