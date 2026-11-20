--!strict
-- Summit layout (GAME_PLAN §3, §9): 8 bases around the plaza, each with a Snow Roller
-- spot, and the launch deck with 8 lanes where the track starts. Graybox until the Blender
-- summit kit is uploaded; the Blender models must keep these spots.
local World = {
	SummitY = 1000, -- top of the plaza floor
	Plaza = { Center = Vector3.new(0, 1000, -133), Size = Vector3.new(400, 4, 330) },
	Deck = { Center = Vector3.new(0, 1000, 4), Size = Vector3.new(140, 1, 44) },
	DeckStand = Vector3.new(0, 1003, -6), -- where a roller stands while packing
	BaseCount = 8,
	BaseSize = Vector3.new(64, 1, 56),
	LaneCount = 8,
	LaneSpacing = 13,
	WheelStand = Vector3.new(0, 1000, -240), -- Lucky Wheel stand at the back of the plaza
}

-- Base i (1-8): left side 1-4, right side 5-8, front to back.
function World.baseCenter(i: number): Vector3
	local side = if i <= 4 then -1 else 1
	local row = (i - 1) % 4
	return Vector3.new(side * 150, World.SummitY, -55 - row * 66)
end

-- Bases face the middle of the plaza.
function World.baseCFrame(i: number): CFrame
	local c = World.baseCenter(i)
	return CFrame.lookAt(c, Vector3.new(0, c.Y, c.Z))
end

-- The Snow Roller of base i: out on the plaza a little away from the base and off to the
-- side, so it never blocks the base's exit (Dev, 2026-11-20).
World.RollerOffset = Vector3.new(20, 0, -(28 + 18))
function World.rollerSpot(i: number): Vector3
	return (World.baseCFrame(i) * CFrame.new(World.RollerOffset)).Position
end

-- Side offset (x on the track) of lane i.
function World.laneX(i: number): number
	return (i - (World.LaneCount + 1) / 2) * World.LaneSpacing
end

World.HatchSpots = 4
World.PetSpotsMax = 10

-- Hatch pedestals and pet pads, matching the base model (art/blender/base.py EGGS / PETS):
-- eggs in a 2x2 block front-left, pets front-right and along the middle, gate path clear.
local EGGS = { { -24, -20 }, { -15, -20 }, { -24, -11 }, { -15, -11 } }
local PETS = {
	{ 10, -20 },
	{ 18, -20 },
	{ 26, -20 },
	{ 10, -11 },
	{ 18, -11 },
	{ 26, -11 },
	{ -24, 2 },
	{ -15, 2 },
	{ 15, 2 },
	{ 24, 2 },
}

function World.eggSpot(b: number, i: number): CFrame
	local p = EGGS[i]
	return World.baseCFrame(b) * CFrame.new(p[1], 2, p[2])
end

function World.petSpot(b: number, i: number): CFrame
	local p = PETS[i]
	return World.baseCFrame(b) * CFrame.new(p[1], 1, p[2])
end

-- The pet park inside a base's fence (base local X/Z studs, gate side = -Z): pets wander
-- here and eggs can be put down anywhere in it (Shared/EggSpots). The cabin starts at
-- z = 15, so the park stops short of it. ParkProps are footprints pets walk around and
-- eggs can't sit on (art/blender/base.py: egg pedestals, lanterns).
World.ParkMin = Vector2.new(-29, -25)
World.ParkMax = Vector2.new(29, 12)
World.ParkTop = 0.5 -- floor top above the base centre (art/blender/base.py FLOOR)
World.ParkProps = {
	{ Position = Vector3.new(-4.5, 0, -14), Radius = 1.2 },
	{ Position = Vector3.new(4.5, 0, -14), Radius = 1.2 },
	{ Position = Vector3.new(-4.5, 0, 4), Radius = 1.2 },
	{ Position = Vector3.new(4.5, 0, 4), Radius = 1.2 },
	{ Position = Vector3.new(-24, 0, -20), Radius = 3.2 },
	{ Position = Vector3.new(-15, 0, -20), Radius = 3.2 },
	{ Position = Vector3.new(-24, 0, -11), Radius = 3.2 },
	{ Position = Vector3.new(-15, 0, -11), Radius = 3.2 },
} :: { { Position: Vector3, Radius: number } }

-- Summit props (Blender Prop_* models): pines around the plaza edge, lamps and benches
-- along the middle walk, snowmen by the spawn, flags by the deck, crystals by the wheel.
-- The middle of the plaza and the paths between bases, rollers and the deck stay clear.
export type PropSpot = { Name: string, CFrame: CFrame, Scale: number }
function World.plazaProps(): { PropSpot }
	local list: { PropSpot } = {}
	local rng = Random.new(20261120)
	local y = World.SummitY
	local function add(name: string, x: number, z: number, scale: number?, yaw: number?)
		table.insert(list, {
			Name = name,
			CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, yaw or rng:NextNumber(0, math.pi * 2), 0),
			Scale = scale or 1,
		})
	end
	-- Pines along both side edges and the back edge, with rocks between them.
	for z = -286, 10, 22 do
		for _, side in { -1, 1 } do
			add("Pine", side * (192 + rng:NextNumber(-3, 3)), z + rng:NextNumber(-4, 4), rng:NextNumber(0.9, 1.35))
			if rng:NextNumber() < 0.45 then
				add("Rock", side * (184 + rng:NextNumber(-2, 2)), z + 11, rng:NextNumber(0.8, 1.4))
			end
		end
	end
	for x = -176, 176, 24 do
		if math.abs(x) > 30 then
			add("Pine", x + rng:NextNumber(-4, 4), -292 + rng:NextNumber(-3, 3), rng:NextNumber(0.9, 1.4))
		end
	end
	-- The middle walk from the deck to the wheel: lamps in pairs, benches facing in.
	for z = -210, -30, 45 do
		add("Lamp", -22, z, 1, 0)
		add("Lamp", 22, z, 1, math.pi)
	end
	for _, z in { -75, -165 } do
		add("Bench", -28, z, 1, math.pi / 2)
		add("Bench", 28, z, 1, -math.pi / 2)
	end
	-- Snowmen and crystals as landmarks.
	add("Snowman", -40, -36, 1.2, math.pi)
	add("Snowman", 40, -36, 1.2, math.pi)
	add("Snowman", 0, -120, 1.6, math.pi)
	for _, p in { { -20, -232 }, { 20, -232 }, { -62, -268 }, { 62, -268 } } do
		add("Crystal", p[1], p[2], rng:NextNumber(1.4, 2.0))
	end
	-- Flags at the corners of the deck.
	for _, side in { -1, 1 } do
		add("Flagpole", side * 80, -18, 1.2, 0)
		add("Flagpole", side * 80, 24, 1.2, 0)
	end
	return list
end

return World
