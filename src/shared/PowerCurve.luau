--!strict
-- Power -> target roll distance (GAME_PLAN §5.2). Log interpolation between the zone
-- thresholds, so every 10x of Power feels like real progress.
local BigNum = require(script.Parent.BigNum)
local Zones = require(script.Parent.Config.Zones)

-- { log10(Power), studs }. Built from the zones, plus the far end of the run.
local KNOTS: { { number } } = { { 0, Zones.MinRoll } }
for _, z in Zones.List do
	if z.Power > 0 then
		table.insert(KNOTS, { math.log10(z.Power), z.Start })
	end
end
table.insert(KNOTS, { math.log10(5e8), 6_000 })

local PowerCurve = {}

PowerCurve.PackMult = { Perfect = 1, Good = 0.85, Weak = 0.7 }

-- Studs a Perfect, clean roll goes with this much Power.
function PowerCurve.distance(power: BigNum.BigNum | number): number
	local lp = math.max(0, BigNum.log10(power))
	if lp <= KNOTS[1][1] then
		return KNOTS[1][2]
	end
	for i = 2, #KNOTS do
		local a, b = KNOTS[i - 1], KNOTS[i]
		if lp <= b[1] then
			local t = (lp - a[1]) / (b[1] - a[1])
			return a[2] + (b[2] - a[2]) * t
		end
	end
	return KNOTS[#KNOTS][2]
end

-- Power needed for a Perfect roll to reach this many studs (inverse, for HUD goals).
function PowerCurve.powerFor(studs: number): number
	if studs <= KNOTS[1][2] then
		return 1
	end
	for i = 2, #KNOTS do
		local a, b = KNOTS[i - 1], KNOTS[i]
		if studs <= b[2] then
			local t = (studs - a[2]) / (b[2] - a[2])
			return 10 ^ (a[1] + (b[1] - a[1]) * t)
		end
	end
	return 10 ^ KNOTS[#KNOTS][1]
end

return PowerCurve
