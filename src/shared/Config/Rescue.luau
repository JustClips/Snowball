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
	BackMin = 50,
	BackPerStud = 0.03,
	BackMax = 190,
	GrabRadius = 8, -- walk this close to the pile to grab an egg
	FlagRadius = 10, -- this close to the flag banks what you carry
	WalkSpeed = 16,
	CarrySpeed = 14, -- slower with an egg in your arms
	TimeLimit = 180, -- seconds; then the rest of the pile melts
	-- The yeti: wakes when you grab, roars, then chases at a speed set by the egg you hold.
	YetiDen = 30, -- studs downhill of the pile
	YetiWake = 1.4,
	YetiSpeed = 12,
	YetiPerRarity = 0.55, -- + per rarity order of the best egg held (Common 1 .. Mythic 6+)
	YetiMax = 15.5,
	CatchRadius = 4.5,
	KnockSeconds = 1.6,
	YetiStun = 3, -- the yeti celebrates before it goes back to its den
	FirstRunsNoYeti = 1, -- the very first roll's rescue has no yeti (learn to carry first)
	RepelMinutes = 10, -- Yeti Repellent
	CarryTwoPass = "CarryTwo",
}

return Rescue
