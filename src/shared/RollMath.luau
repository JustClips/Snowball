--!strict
-- Small shared helpers for rolling: the pack meter and the track width lookup.
local Spline = require(script.Parent.Spline)

local RollMath = {
	PackPeriod = 1.1, -- seconds for the needle to go from one end to the other
	MaxPackSeconds = 3, -- the meter swings this long; no tap = a Weak pack
}

-- Needle position 0..1 after `t` seconds (bounces end to end). Green is centred on 0.5.
function RollMath.needle(t: number): number
	local phase = (t / RollMath.PackPeriod) % 2
	return if phase < 1 then phase else 2 - phase
end

function RollMath.packQuality(t: number, green: number, yellow: number): string
	local off = math.abs(RollMath.needle(t) - 0.5)
	if off <= green / 2 then
		return "Perfect"
	elseif off <= green / 2 + yellow then
		return "Good"
	end
	return "Weak"
end

function RollMath.widthAt(s: number): number
	return Spline.main():sample(s).Width
end

return RollMath
