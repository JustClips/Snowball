--!strict
-- Codes that ship with the game (CodeService). Upper-case letters and digits only.
-- ExpiresAt is unix time (UTC), nil = never. Rewards use Config/Rewards kinds.
return {
	SNOWBALL = { Rewards = { { Kind = "Cash", Seconds = 300, Floor = 0.3 }, { Kind = "Spin", Amount = 1 } } },
	AVALANCHE = { Rewards = { { Kind = "Charge", Charge = "LuckyRoll", Amount = 2 } } },
	RELEASE = {
		Rewards = { { Kind = "Egg", Rarity = "Rare" }, { Kind = "Boost", Boost = "Train2x", Minutes = 15 } },
		ExpiresAt = 1798761600, -- 1 Jan 2027 (UTC)
	},
} :: { [string]: { Rewards: { any }, ExpiresAt: number? } }
