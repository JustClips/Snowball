--!strict
-- Economy and tuning numbers that don't belong to one feature config.
local Economy = {
	AutosaveSeconds = 120,
	SessionStaleSeconds = 90, -- a save lock older than this is taken over (ProfileStore)
	StateFlushInterval = 0.15, -- PlayerState snapshots go out at most this often

	-- Training (GAME_PLAN §5.1)
	-- Training is automatic while you stand near your roller (Dev, 2026-11-20): one slow,
	-- chunky rep every 1.25 s with the push animation (not "+1" spam), x2 speed with the
	-- Auto Train pass ("Fast Train"). Tapping is only for pops. Roller Power is per rep.
	TrainRepsPerSecond = 0.8,
	FastTrainMult = 2,
	AutoTrainTapsPerSecond = 0.8, -- reps/s used to value Training Time products
	RollerDeck = 16, -- the roller's square deck (studs): standing on it = training
	RollerHeight = 8,

	-- Rebirth (GAME_PLAN §5.11)
	RebirthFirstCost = 150_000_000,
	RebirthCostGrowth = 1.6,
	RebirthTrainBonus = 0.5, -- x1.5 training per rebirth (multiplicative)
	RebirthCashBonus = 0.5, -- +50% cash per rebirth (additive)
	RebirthLuckBonus = 0.1,
	SkipRebirthMinShare = 0.3,

	-- Pets (GAME_PLAN §5.10)
	EquipSlots = 3,
	EquipSlotsPass = 2,
	StartPetSlots = 6,
	OfflineIncomeRate = 0.5,
	OfflineCapSeconds = 8 * 3600,
	OfflineCapSecondsVIP = 12 * 3600,
	OfflineMinSeconds = 60,

	-- Multipliers from passes
	Train2xPass = 2,
	Cash2xPass = 2,
	VIPCashBonus = 0.2,
	VIPLuckBonus = 0.1,
	LuckyPassBonus = 0.5,

	-- A pop's cash payouts use at least this much income per second (before pets earn).
	MinIncomeForRewards = 5,

	-- Contextual offers (GAME_PLAN §6 "When offers appear", OfferService)
	Offers = {
		GlobalCooldown = 180, -- at most one offer every 3 minutes
		PerOfferCooldown = 900, -- the same offer at most every 15 minutes
		StuckIncomeMinutes = 5, -- next roller costs more than this much income...
		StuckSeconds = 180, -- ...for this long: offer training time
		FullBounces = 3, -- eggs bounced off a full ball: Egg Slots nudge
		Bonks = 3, -- bonks in a session: Golden Snowball offer
		AvalancheMeter = 0.8, -- meter at 80%+: Server Luck offer
		SkipHatchFrom = "Rare", -- placing an egg this rare or better: Skip Hatch offer
	},

	-- Starter Pack (GAME_PLAN §6)
	StarterPack = { Hours = 2, HideAtZone = 4, EggRarity = "Epic", LuckyRolls = 3, Train2xMinutes = 15 },
}

function Economy.rebirthCost(rebirths: number): number
	return Economy.RebirthFirstCost * Economy.RebirthCostGrowth ^ rebirths
end

function Economy.rebirthTrainMult(rebirths: number): number
	return (1 + Economy.RebirthTrainBonus) ^ rebirths
end

function Economy.rebirthCashMult(rebirths: number): number
	return 1 + Economy.RebirthCashBonus * rebirths
end

return Economy
