--!strict
-- Free rewards (GAME_PLAN §5.13, ported from Sweep's Config/Rewards, items swapped for this
-- game's boosts and charges):
--   Daily: 7-day streak on the player's own clock (24 h cooldown, streak resets after 48 h).
--     Day 7 = Red Panda (the daily exclusive) + a Legendary egg; from week 2 the panda is Huge.
--   Playtime: gifts after 2, 5, 10, 20, 35 and 60 minutes in one session.
--   Wheel: the Lucky Wheel (plaza stand + HUD button). One free spin a day, more from the
--     daily streak or Robux (Products, Kind "WheelSpins"). Weights add up to 100 = percent,
--     shown in the window (paid random rewards must show odds).
--   Tutorial: what finishing the tutorial gives (a free wheel spin, plan §4).
-- Reward kinds:
--   Cash { Seconds, Floor }   Seconds of the player's income, at least Floor x their next goal
--   Egg { Rarity }            an egg of that rarity from their best zone
--   Spin { Amount }           Lucky Wheel spins
--   Pet { Pet }               a pet id, or "Daily" for the daily exclusive
--   Boost { Boost, Minutes }  a personal boost (Train2x, Cash2x)
--   Charge { Charge, Amount } LuckyRoll / GoldenRuns charges
--   Power { Taps }            that many taps of training at the player's own rate

export type Reward = {
	Kind: string,
	Seconds: number?,
	Floor: number?,
	Rarity: string?,
	Amount: number?,
	Pet: string?,
	Boost: string?,
	Minutes: number?,
	Charge: string?,
	Taps: number?,
	Bonus: Reward?,
}

export type WheelSegment = { Reward: Reward, Weight: number, Color: Color3 }

local Rewards = {}

Rewards.Daily = {
	{ Kind = "Cash", Seconds = 300, Floor = 0.3 },
	{ Kind = "Egg", Rarity = "Rare", Bonus = { Kind = "Boost", Boost = "Train2x", Minutes = 10 } },
	{ Kind = "Cash", Seconds = 600, Floor = 0.5, Bonus = { Kind = "Spin", Amount = 1 } },
	{ Kind = "Charge", Charge = "LuckyRoll", Amount = 3 },
	{ Kind = "Egg", Rarity = "Epic", Bonus = { Kind = "Charge", Charge = "GoldenRuns", Amount = 3 } },
	{ Kind = "Boost", Boost = "Cash2x", Minutes = 15, Bonus = { Kind = "Power", Taps = 240 } },
	{ Kind = "Pet", Pet = "Daily", Bonus = { Kind = "Egg", Rarity = "Legendary" } },
} :: { Reward }

Rewards.DailyPet = "RedPanda"
Rewards.DailyCooldown = 24 * 3600
Rewards.DailyStreakWindow = 48 * 3600

Rewards.Playtime = {
	{ Minutes = 2, Reward = { Kind = "Cash", Seconds = 120, Floor = 0.2 } },
	{ Minutes = 5, Reward = { Kind = "Boost", Boost = "Train2x", Minutes = 5 } },
	{ Minutes = 10, Reward = { Kind = "Cash", Seconds = 300, Floor = 0.3 } },
	{ Minutes = 20, Reward = { Kind = "Charge", Charge = "LuckyRoll", Amount = 1 } },
	{ Minutes = 35, Reward = { Kind = "Egg", Rarity = "Rare" } },
	{ Minutes = 60, Reward = { Kind = "Egg", Rarity = "Epic" } },
} :: { { Minutes: number, Reward: Reward } }

Rewards.Wheel = {
	FreeEvery = 86400,
	SpinSeconds = 4.6,
	FirstSpinRarity = "Rare", -- the very first spin always lands on the Rare egg (Sweep rule)
	Segments = {
		{ Reward = { Kind = "Cash", Seconds = 600, Floor = 0.4 }, Weight = 32, Color = Color3.fromRGB(92, 214, 92) },
		{ Reward = { Kind = "Boost", Boost = "Train2x", Minutes = 10 }, Weight = 18, Color = Color3.fromRGB(76, 168, 255) },
		{ Reward = { Kind = "Egg", Rarity = "Rare" }, Weight = 12, Color = Color3.fromRGB(155, 107, 255) },
		{ Reward = { Kind = "Charge", Charge = "GoldenRuns", Amount = 2 }, Weight = 17, Color = Color3.fromRGB(255, 154, 60) },
		{ Reward = { Kind = "Egg", Rarity = "Legendary" }, Weight = 1, Color = Color3.fromRGB(255, 194, 46) },
		{ Reward = { Kind = "Charge", Charge = "LuckyRoll", Amount = 2 }, Weight = 14, Color = Color3.fromRGB(127, 211, 255) },
		{ Reward = { Kind = "Egg", Rarity = "Mythic" }, Weight = 1, Color = Color3.fromRGB(255, 126, 182) },
		{ Reward = { Kind = "Egg", Rarity = "Epic" }, Weight = 5, Color = Color3.fromRGB(255, 75, 85) },
	} :: { WheelSegment },
}

function Rewards.wheelTotal(): number
	local total = 0
	for _, seg in Rewards.Wheel.Segments do
		total += seg.Weight
	end
	return total
end

Rewards.Tutorial = { Kind = "Spin", Amount = 1 } :: Reward

-- Short text for a reward (wheel wedges, daily cards). The server returns the exact text
-- after granting (cash amounts depend on the player).
function Rewards.describe(r: Reward): string
	local text
	if r.Kind == "Cash" then
		text = "Cash"
	elseif r.Kind == "Egg" then
		text = `{r.Rarity} Egg`
	elseif r.Kind == "Spin" then
		text = if (r.Amount or 1) > 1 then `{r.Amount} Spins` else "Wheel Spin"
	elseif r.Kind == "Pet" then
		text = if r.Pet == "Daily" then "Red Panda" else r.Pet or "Pet"
	elseif r.Kind == "Boost" then
		text = `{if r.Boost == "Train2x" then "2x Power" else "2x Cash"} {r.Minutes}m`
	elseif r.Kind == "Charge" then
		text = `{r.Amount} {if r.Charge == "LuckyRoll" then "Lucky Rolls" else "Golden Runs"}`
	elseif r.Kind == "Power" then
		text = "Power"
	else
		text = "?"
	end
	if r.Bonus then
		text ..= " + " .. Rewards.describe(r.Bonus)
	end
	return text
end

return Rewards
