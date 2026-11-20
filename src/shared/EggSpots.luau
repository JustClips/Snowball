--!strict
-- Where eggs may go in a pet park (base local X/Z studs). Shared so the server checks the
-- exact rules the client's placement ghost shows (green = ok, red = not here). Ported from
-- Sweep the World (Steal an Egg style free placement).
local World = require(script.Parent.Config.World)

local EggSpots = {}

EggSpots.Spacing = 4.5 -- studs between egg centres
EggSpots.Margin = 2.5 -- studs from the fence to an egg's centre
EggSpots.EggRadius = 1.6 -- an egg's foot, kept off props

type Entry = { Uid: string?, X: number?, Z: number? }

-- Why an egg can't go at (x, z), or nil if it can. pad makes every rule a bit stricter
-- (the client snaps with a little pad so the server, with none, always agrees).
function EggSpots.problem(hatching: { Entry }, x: number, z: number, ignoreUid: string?, pad: number?): string?
	local extra = pad or 0
	local min, max = World.ParkMin, World.ParkMax
	local m = EggSpots.Margin + extra
	if x < min.X + m or x > max.X - m or z < min.Y + m or z > max.Y - m then
		return "Put it inside your base"
	end
	local p = Vector2.new(x, z)
	for _, prop in World.ParkProps do
		if (p - Vector2.new(prop.Position.X, prop.Position.Z)).Magnitude < prop.Radius + EggSpots.EggRadius + extra then
			return "Something's in the way"
		end
	end
	for _, entry in hatching do
		if
			entry.Uid ~= ignoreUid
			and entry.X
			and entry.Z
			and (p - Vector2.new(entry.X, entry.Z)).Magnitude < EggSpots.Spacing + extra
		then
			return "Too close to another egg"
		end
	end
	return nil
end

-- The closest free spot to (x, z) within reach studs, so a click next to an egg or a prop
-- still lands. Returns nil, nil and the reason when nothing near is free.
function EggSpots.nearest(
	hatching: { Entry },
	x: number,
	z: number,
	reach: number,
	pad: number?
): (number?, number?, string?)
	local min, max = World.ParkMin, World.ParkMax
	local m = EggSpots.Margin + (pad or 0) + 0.05
	local cx = math.clamp(x, min.X + m, max.X - m)
	local cz = math.clamp(z, min.Y + m, max.Y - m)
	if (Vector2.new(cx, cz) - Vector2.new(x, z)).Magnitude > reach then
		return nil, nil, "Put it inside your base"
	end
	local first = EggSpots.problem(hatching, cx, cz, nil, pad)
	if not first then
		return cx, cz, nil
	end
	for r = 0.5, reach, 0.5 do
		local steps = math.max(8, math.floor(r * 6))
		for i = 0, steps - 1 do
			local a = i / steps * math.pi * 2
			local px, pz = cx + math.cos(a) * r, cz + math.sin(a) * r
			if not EggSpots.problem(hatching, px, pz, nil, pad) then
				return px, pz, nil
			end
		end
	end
	return nil, nil, first
end

-- A free spot near the gate (Place for me, the tutorial, and eggs saved before free
-- placement).
function EggSpots.auto(hatching: { Entry }, ignoreUid: string?): (number?, number?)
	local min, max = World.ParkMin, World.ParkMax
	local front = Vector2.new(-12, min.Y + 6)
	local best, bestDistance = nil, math.huge
	for x = min.X + 4, max.X - 4, 4.5 do
		for z = min.Y + 4, max.Y - 4, 4.5 do
			local d = (Vector2.new(x, z) - front).Magnitude
			if d < bestDistance and not EggSpots.problem(hatching, x, z, ignoreUid) then
				best, bestDistance = Vector2.new(x, z), d
			end
		end
	end
	if best then
		return best.X, best.Y
	end
	return nil, nil
end

return EggSpots
