--!strict
-- Economy and tuning numbers that don't belong to one feature config.
local Economy = {
	AutosaveSeconds = 120,
	SessionStaleSeconds = 90, -- a save lock older than this is taken over (ProfileStore)
	StateFlushInterval = 0.15, -- PlayerState snapshots go out at most this often

	-- Training (GAME_PLAN §5.1)
	TapsPerSecond = 8, -- server cap on manual taps
	HoldTapsPerSecond = 3, -- holding the screen trains at this rate
	AutoTrainTapsPerSecond = 5, -- Auto Train pass, while standing on the roller
	RollerRadius = 9, -- studs (flat) from the roller pad centre that count as "on the roller"
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
