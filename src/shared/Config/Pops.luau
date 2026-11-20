--!strict
-- Snow Pops (GAME_PLAN §5.3): random tap targets that show up only while you train.
local Types = require(script.Parent.Parent.Types)

-- Free pops. Weights are relative. Coin and Luck pops are ~1 in 12 together.
local Free: { Types.PopTier } = {
	{
		Id = "Snowflake",
		Name = "Snowflake",
		Kind = "Train",
		Mult = 2,
		Seconds = 30,
		Weight = 50.5,
		Color = Color3.fromRGB(245, 250, 255),
	},
	{
		Id = "Ice",
		Name = "Ice",
		Kind = "Train",
		Mult = 3,
		Seconds = 30,
		Weight = 23,
		Color = Color3.fromRGB(90, 180, 255),
	},
	{
		Id = "Frost",
		Name = "Frost",
		Kind = "Train",
		Mult = 5,
		Seconds = 30,
		Weight = 12,
		Color = Color3.fromRGB(170, 110, 255),
	},
	{
		Id = "Golden",
		Name = "Golden",
		Kind = "Train",
		Mult = 10,
		Seconds = 30,
		Weight = 5.5,
		Color = Color3.fromRGB(255, 200, 40),
	},
	{
		Id = "Present",
		Name = "Present",
		Kind = "Present",
		Mult = 60,
		Seconds = 0,
		Weight = 1,
		Color = Color3.fromRGB(235, 60, 70),
	},
	{
		Id = "Coin",
		Name = "Coin",
		Kind = "Coin",
		Mult = 15,
		Seconds = 0,
		Weight = 4.5,
		Color = Color3.fromRGB(255, 225, 90),
	},
	{
		Id = "Luck",
		Name = "Luck",
		Kind = "Luck",
		Mult = 3,
		Seconds = 0,
		Weight = 3.5,
		Color = Color3.fromRGB(110, 230, 120),
	},
}

-- Rainbow Pops: paid, price always shown on the pop. Rolled 60/30/10.
local Rainbow: { Types.PopTier } = {
	{
		Id = "Rainbow25",
		Name = "Rainbow x25",
		Kind = "Rainbow",
		Mult = 25,
		Seconds = 120,
		Weight = 60,
		Color = Color3.fromRGB(255, 120, 200),
		Product = "RainbowPop25",
	},
	{
		Id = "Rainbow50",
		Name = "Rainbow x50",
		Kind = "Rainbow",
		Mult = 50,
		Seconds = 120,
		Weight = 30,
		Color = Color3.fromRGB(255, 120, 200),
		Product = "RainbowPop50",
	},
	{
		Id = "Rainbow100",
		Name = "Rainbow x100",
		Kind = "Rainbow",
		Mult = 100,
		Seconds = 120,
		Weight = 10,
		Color = Color3.fromRGB(255, 120, 200),
		Product = "RainbowPop100",
	},
}

local Pops = {
	Free = Free,
	Rainbow = Rainbow,
	ById = {} :: { [string]: Types.PopTier },

	MinGap = 8, -- seconds of training between pops
	MaxGap = 15,
	FirstPopAfter = 5, -- the very first pop (scripted, always FirstPopTier)
	FirstPopTier = "Frost",
	LifeSeconds = 4, -- a pop drifts this long, then melts
	ClaimGrace = 0.6, -- network slack on top of LifeSeconds

	RainbowEvery = 180, -- at most one Rainbow Pop per this many seconds
	RainbowNotBefore = 180, -- never in the first 3 minutes of play
	RainbowAfterDecline = 300,
	RainbowChance = 0.3, -- share of scheduled pops that are Rainbow once one is allowed

	PopRushGap = 3, -- during an Avalanche: one pop every 3 s

	-- Screen spot (0-1) safe area: away from the HUD edges and the bottom buttons.
	SafeArea = { MinX = 0.22, MaxX = 0.78, MinY = 0.2, MaxY = 0.62 },
}
for _, def in Free do
	Pops.ById[def.Id] = def
end
for _, def in Rainbow do
	Pops.ById[def.Id] = def
end

local function pick(list: { Types.PopTier }, rng: Random): Types.PopTier
	local total = 0
	for _, def in list do
		total += def.Weight
	end
	local roll = rng:NextNumber() * total
	for _, def in list do
		roll -= def.Weight
		if roll <= 0 then
			return def
		end
	end
	return list[1]
end

function Pops.rollFree(rng: Random): Types.PopTier
	return pick(Free, rng)
end

function Pops.rollRainbow(rng: Random): Types.PopTier
	return pick(Rainbow, rng)
end

return Pops
