--!strict
-- Obstacles on the run (GAME_PLAN §5.5, §5.7). A ball with radius >= SizeNeeded SMASHES it
-- (debris, +cash, a little slower); smaller balls BONK (much slower, bounced sideways).
-- The layout is fixed per mountain (same seed on server and client).
local Zones = require(script.Parent.Zones)

export type Kind = {
	Id: string,
	Zone: string,
	SizeNeeded: number,
	Radius: number, -- hit radius in studs (graybox size too)
	Height: number,
	Cash: number, -- smash cash (x zone coin value)
	Color: Color3,
}

export type Obstacle = { Id: number, Kind: string, s: number, x: number, Radius: number, SizeNeeded: number }

local KINDS: { Kind } = {
	{
		Id = "Snowman",
		Zone = "Meadow",
		SizeNeeded = 3,
		Radius = 2.5,
		Height = 7,
		Cash = 3,
		Color = Color3.fromRGB(250, 250, 255),
	},
	{
		Id = "Fence",
		Zone = "Meadow",
		SizeNeeded = 4,
		Radius = 3,
		Height = 4,
		Cash = 4,
		Color = Color3.fromRGB(140, 95, 60),
	},
	{
		Id = "Pine",
		Zone = "Pine",
		SizeNeeded = 6,
		Radius = 3,
		Height = 16,
		Cash = 6,
		Color = Color3.fromRGB(40, 110, 60),
	},
	{
		Id = "Log",
		Zone = "Pine",
		SizeNeeded = 5,
		Radius = 4,
		Height = 3,
		Cash = 5,
		Color = Color3.fromRGB(110, 75, 45),
	},
	{
		Id = "IceBlock",
		Zone = "Lake",
		SizeNeeded = 8,
		Radius = 4,
		Height = 7,
		Cash = 9,
		Color = Color3.fromRGB(170, 225, 255),
	},
	{
		Id = "FishingHut",
		Zone = "Lake",
		SizeNeeded = 11,
		Radius = 6,
		Height = 10,
		Cash = 12,
		Color = Color3.fromRGB(170, 70, 55),
	},
	{
		Id = "Crystal",
		Zone = "Cave",
		SizeNeeded = 14,
		Radius = 5,
		Height = 14,
		Cash = 15,
		Color = Color3.fromRGB(120, 160, 255),
	},
	{
		Id = "Stalagmite",
		Zone = "Cave",
		SizeNeeded = 17,
		Radius = 6,
		Height = 20,
		Cash = 18,
		Color = Color3.fromRGB(150, 160, 190),
	},
	{
		Id = "Boulder",
		Zone = "Aurora",
		SizeNeeded = 21,
		Radius = 8,
		Height = 14,
		Cash = 24,
		Color = Color3.fromRGB(120, 120, 130),
	},
	{
		Id = "BigPine",
		Zone = "Aurora",
		SizeNeeded = 25,
		Radius = 6,
		Height = 34,
		Cash = 28,
		Color = Color3.fromRGB(30, 95, 60),
	},
	{
		Id = "SnowmanWall",
		Zone = "Village",
		SizeNeeded = 30,
		Radius = 6,
		Height = 18,
		Cash = 30,
		Color = Color3.fromRGB(250, 250, 255),
	},
}

local Obstacles = {
	Kinds = KINDS,
	ById = {} :: { [string]: Kind },
	Spacing = 55, -- studs between obstacle rows
	FirstAt = 90, -- the first stretch after the push is clear
	Seed = 12345,
}
for _, k in KINDS do
	Obstacles.ById[k.Id] = k
end

local byZone: { [string]: { Kind } } = {}
for _, k in KINDS do
	byZone[k.Zone] = byZone[k.Zone] or {}
	table.insert(byZone[k.Zone], k)
end

-- The fixed layout for a track of `length` studs. widthAt(s) gives the track width.
function Obstacles.layout(length: number, widthAt: (number) -> number, stopAt: number): { Obstacle }
	local rng = Random.new(Obstacles.Seed)
	local out: { Obstacle } = {}
	local s = Obstacles.FirstAt
	local id = 0
	while s < math.min(length, stopAt) do
		local zone = Zones.at(s)
		local kinds = byZone[zone.Id]
		if kinds and zone.Id ~= "Village" then
			local count = if rng:NextNumber() < 0.35 then 2 else 1
			local half = widthAt(s) / 2
			for _ = 1, count do
				local kind = kinds[rng:NextInteger(1, #kinds)]
				id += 1
				table.insert(out, {
					Id = id,
					Kind = kind.Id,
					s = s + rng:NextNumber(-10, 10),
					x = rng:NextNumber(-half + kind.Radius + 4, half - kind.Radius - 4),
					Radius = kind.Radius,
					SizeNeeded = kind.SizeNeeded,
				})
			end
		end
		s += Obstacles.Spacing * rng:NextNumber(0.8, 1.25)
	end
	return out
end

return Obstacles
