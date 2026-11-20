--!strict
-- The server event (GAME_PLAN §5.12).
return {
	FillRadius = 600, -- finished runs add their final radius; this much fills the meter (~10 min with 8 players)
	WarningSeconds = 10,
	ActiveSeconds = 60,
	LuckMult = 2,
	BonusEggFloor = "Rare", -- every run that ends during the Avalanche brings one extra Rare+ egg
	CrownLuckBonus = 0.25,
	CrownMinutes = 5,
}
