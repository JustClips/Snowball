--!strict
-- The track as a curve you can ask about by distance: (s, x) -> world position.
-- s = studs along the run from the launch deck, x = side offset (right is +).
-- Built once from Config/Track (Catmull-Rom through the points), resampled every STEP
-- studs of arc length so lookups are O(1) and identical on server and client.
local Types = require(script.Parent.Types)

local STEP = 2 -- studs between samples
local SUB = 24 -- curve pieces per control segment while measuring length

export type Sample = {
	Pos: Vector3,
	Forward: Vector3, -- unit, along the run (includes the downhill slope)
	Right: Vector3, -- unit, flat, to the right of Forward
	Width: number,
	Slope: number,
	Surface: Types.Surface,
}

export type Spline = {
	Length: number,
	sample: (self: Spline, s: number) -> Sample,
	position: (self: Spline, s: number, x: number) -> Vector3,
	cframe: (self: Spline, s: number, x: number) -> CFrame,
	_pos: { Vector3 },
	_meta: { number }, -- control point index per sample
	_points: { Types.TrackPoint },
}

local Spline = {}
Spline.__index = Spline

local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
end

function Spline.new(points: { Types.TrackPoint }): Spline
	assert(#points >= 2, "track needs at least 2 points")
	-- Dense polyline with the control segment each piece belongs to.
	local dense: { Vector3 } = {}
	local denseSeg: { number } = {}
	local n = #points
	for i = 1, n - 1 do
		local p0 = points[math.max(1, i - 1)].Pos
		local p1 = points[i].Pos
		local p2 = points[i + 1].Pos
		local p3 = points[math.min(n, i + 2)].Pos
		for k = 0, SUB - 1 do
			table.insert(dense, catmull(p0, p1, p2, p3, k / SUB))
			table.insert(denseSeg, i)
		end
	end
	table.insert(dense, points[n].Pos)
	table.insert(denseSeg, n - 1)

	-- Resample at equal arc length.
	local pos: { Vector3 } = { dense[1] }
	local meta: { number } = { 1 }
	local travelled = 0
	local nextAt = STEP
	for i = 2, #dense do
		local a, b = dense[i - 1], dense[i]
		local len = (b - a).Magnitude
		while travelled + len >= nextAt do
			local t = (nextAt - travelled) / len
			table.insert(pos, a:Lerp(b, t))
			table.insert(meta, denseSeg[i])
			nextAt += STEP
		end
		travelled += len
	end
	local self = setmetatable({
		Length = (#pos - 1) * STEP,
		_pos = pos,
		_meta = meta,
		_points = points,
	}, Spline)
	return (self :: any) :: Spline
end

local function index(self: any, s: number): (number, number)
	local f = math.clamp(s, 0, self.Length) / STEP
	local i = math.min(math.floor(f) + 1, #self._pos - 1)
	return i, f - (i - 1)
end

function Spline.sample(self: Spline, s: number): Sample
	local i, t = index(self, s)
	local a, b = self._pos[i], self._pos[i + 1]
	local forward = (b - a).Unit
	local flat = Vector3.new(forward.X, 0, forward.Z)
	local right = if flat.Magnitude > 1e-4 then flat.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
	local seg = self._meta[i]
	local p1 = self._points[seg]
	return {
		Pos = a:Lerp(b, t),
		Forward = forward,
		Right = right,
		Width = p1.Width,
		Slope = p1.Slope,
		Surface = p1.Surface,
	}
end

function Spline.position(self: Spline, s: number, x: number): Vector3
	local smp = self:sample(s)
	return smp.Pos + smp.Right * x
end

-- Looking down the run, standing on the surface at (s, x).
function Spline.cframe(self: Spline, s: number, x: number): CFrame
	local smp = self:sample(s)
	local p = smp.Pos + smp.Right * x
	return CFrame.lookAt(p, p + smp.Forward)
end

-- The one shared spline for the current mountain (built on first use).
local cached: Spline? = nil
function Spline.main(): Spline
	if not cached then
		local Track = require(script.Parent.Config.Track) :: any
		cached = Spline.new(Track.Points)
	end
	return cached :: Spline
end

return Spline
