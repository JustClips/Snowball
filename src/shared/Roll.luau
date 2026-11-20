--!strict
-- The pure roll step, shared by the server sim (RollService, 20 Hz) and client prediction.
-- A ball lives in 2D on the track: s (studs along the run), x (side offset).
-- Distance model: the ball has a target distance D from Power (PowerCurve). Its speed is
-- the lower of the surface's top speed and sqrt(2 * Decel * (D - s)), so a clean run eases
-- to a stop right at D. Smashes, bonks and ramps change D, so skill still matters.
local Spline = require(script.Parent.Spline)

export type Ball = {
	s: number,
	x: number,
	v: number, -- speed along the run, studs/s
	vx: number, -- side speed
	r: number, -- radius
	snow: number, -- snow collected (radius grows from this)
	growth: number, -- Core growth multiplier
	D: number, -- target distance (where a clean run stops)
	steer: number, -- -1..1 from the player
	done: boolean,
	wallUntil: number?,
}

local SURFACE = {
	Snow = { TopSpeed = 72, Decel = 9, Grip = 8, SteerSpeed = 42 },
	Ice = { TopSpeed = 88, Decel = 6, Grip = 2.6, SteerSpeed = 34 },
	Powder = { TopSpeed = 64, Decel = 10, Grip = 6, SteerSpeed = 38 },
}

local Roll = {
	PushSpeed = 26, -- speed right after the push
	Accel = 34, -- how fast the ball gets up to speed
	TopSpeedPerStud = 0.012, -- deeper zones roll faster
	StartRadius = 2,
	MaxRadius = 40,
	GrowthScale = 3, -- r = Start + GrowthScale * sqrt(snow * growth)
	WallBounce = 0.45,
	-- Hits (GAME_PLAN §5.5)
	SmashKeep = 0.95, -- speed kept after a smash
	BonkKeep = 0.65, -- speed kept after a bonk
	BonkSideSpeed = 26,
	RampBoost = 70, -- extra studs a speed ramp adds to the run
	Surface = SURFACE,
}

function Roll.radius(snow: number, growth: number): number
	return math.min(Roll.MaxRadius, Roll.StartRadius + Roll.GrowthScale * math.sqrt(math.max(0, snow * growth)))
end

function Roll.new(x: number, D: number, growth: number): Ball
	return {
		s = 0,
		x = x,
		v = Roll.PushSpeed,
		vx = 0,
		r = Roll.StartRadius,
		snow = 0,
		growth = growth,
		D = D,
		steer = 0,
		done = false,
	}
end

-- Keeps speed in step with a changed D (remaining distance scales with speed squared).
local function scaleRemaining(ball: Ball, keep: number)
	local remaining = math.max(0, ball.D - ball.s)
	ball.D = ball.s + remaining * keep * keep
	ball.v *= keep
end

function Roll.smash(ball: Ball)
	scaleRemaining(ball, Roll.SmashKeep)
end

function Roll.bonk(ball: Ball, side: number)
	scaleRemaining(ball, Roll.BonkKeep)
	ball.vx = (if side >= 0 then 1 else -1) * Roll.BonkSideSpeed
end

function Roll.ramp(ball: Ball)
	ball.D += Roll.RampBoost
	ball.v *= 1.15
end

function Roll.addSnow(ball: Ball, amount: number)
	ball.snow += amount
	ball.r = Roll.radius(ball.snow, ball.growth)
end

-- One step. endAt = where the run is forced to end (the Village wall / end of track).
function Roll.step(ball: Ball, dt: number, spline: Spline.Spline, endAt: number)
	if ball.done then
		return
	end
	local smp = spline:sample(ball.s)
	local surf = SURFACE[smp.Surface] or SURFACE.Snow
	local remaining = math.max(0, ball.D - ball.s)
	local top = surf.TopSpeed + ball.s * Roll.TopSpeedPerStud
	local target = math.min(top, math.sqrt(2 * surf.Decel * remaining))
	if ball.v < target then
		ball.v = math.min(target, ball.v + Roll.Accel * dt)
	else
		ball.v = target
	end
	ball.s += ball.v * dt

	-- Steering: side speed eases toward steer * SteerSpeed (slow to answer on ice).
	local want = math.clamp(ball.steer, -1, 1) * surf.SteerSpeed
	ball.vx += (want - ball.vx) * math.min(1, surf.Grip * dt)
	ball.x += ball.vx * dt
	local half = smp.Width / 2 - ball.r
	if half < 0 then
		half = 0
	end
	if ball.x > half then
		ball.x = half
		ball.vx = -math.abs(ball.vx) * Roll.WallBounce
	elseif ball.x < -half then
		ball.x = -half
		ball.vx = math.abs(ball.vx) * Roll.WallBounce
	end

	if ball.s >= endAt then
		ball.s = endAt
		ball.done = true
	elseif remaining <= 0.5 or (ball.v < 0.5 and remaining < 3) then
		ball.done = true
		ball.v = 0
	end
end

-- World CFrame of the ball's centre (for drawing).
function Roll.worldPosition(ball: Ball, spline: Spline.Spline): Vector3
	return spline:position(ball.s, ball.x) + Vector3.yAxis * ball.r
end

return Roll
