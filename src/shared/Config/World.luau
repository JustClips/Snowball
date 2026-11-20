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

-- The Snow Roller pad of base i (on the plaza side of the base).
function World.rollerSpot(i: number): Vector3
	return (World.baseCFrame(i) * CFrame.new(0, 0, -World.BaseSize.Z / 2 - 4)).Position
end

-- Side offset (x on the track) of lane i.
function World.laneX(i: number): number
	return (i - (World.LaneCount + 1) / 2) * World.LaneSpacing
end

return World
