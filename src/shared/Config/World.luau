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

return World
