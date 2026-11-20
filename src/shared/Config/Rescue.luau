--!strict
-- Egg rescue (Dev 2026-11-20, his pick "1", Throw Food For Animals' carry-home): the eggs a
-- ball collects are NOT banked when it cracks. They sit frozen in a snow pile at the crack
-- site; you walk into the pile to grab one (held in your arms) and carry it uphill to the
-- green flag. A yeti wakes up and chases you; if it catches you, you fall and the egg goes
-- back to the pile. Farther rolls = rarer eggs but a longer way to the flag.
-- Robux: Sled Home (every egg left is sledded home), Yeti Repellent (no yeti for a while),
-- Carry Two (gamepass: hold 2 eggs at once).
local Rescue = {
	-- Flag distance uphill from the pile: BackMin + s * BackPerStud, capped at BackMax.
	-- Dev 2026-11-20: "as less friction as possible". Shorter way, faster walk, bigger
	-- grab/flag circles, quick trips back, Commons fly home by themselves.
	BackMin = 30,
	BackPerStud = 0.015,
	BackMax = 80,
	GrabRadius = 11, -- walk this close to the pile to grab an egg
	FlagRadius = 14, -- this close to the flag banks what you carry
	WalkSpeed = 20,
	CarrySpeed = 18, -- a little slower with an egg in your arms
	-- Eggs below this rarity go straight to your bag when the ball cracks (no trip for a
	-- Common). If nothing better is left, there's no rescue at all.
	CarryFrom = "Uncommon",
	BackSeconds = 0.6, -- the fade back to the pile after saving an egg or a yeti hit
	TimeLimit = 180, -- seconds; then the rest of the pile melts
	-- The yeti: wakes when you grab, roars, then chases at a speed set by the egg you hold.
	YetiDen = 30, -- studs downhill of the pile
	YetiWake = 1.4,
	-- Always a bit slower than you carrying: it only catches you if you stop or get stuck.
	YetiSpeed = 13,
	YetiPerRarity = 0.6, -- + per rarity order of the best egg held (Common 1 .. Mythic 6+)
	YetiMax = 17.4,
	CatchRadius = 4.5,
	KnockSeconds = 1.1, -- then you're put back at the pile (no walking back down)
	YetiStun = 3, -- the yeti celebrates before it goes back to its den
	FirstRunsNoYeti = 1, -- the very first roll's rescue has no yeti (learn to carry first)
	RepelMinutes = 10, -- Yeti Repellent
	CarryTwoPass = "CarryTwo",
}

return Rescue
