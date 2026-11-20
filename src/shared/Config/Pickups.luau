--!strict
-- Things a ball picks up (GAME_PLAN §5.5). Each run gets its own seed; server and client
-- build the same list from it, and only the roller sees and collects their own.
local Zones = require(script.Parent.Zones)

export type Pickup = { Id: number, Kind: string, s: number, x: number }

local Pickups = {
	HitRadius = 3, -- pickup radius (added to the ball radius)
	-- Average studs between pickups of each kind.
	Every = {
		Snow = 22,
		Coin = 38,
		Egg = 180,
		Present = 700,
		Ramp = 450,
	},
	SnowPerPile = 0.2, -- x zone index: deeper piles are bigger
	CoinsPerCluster = 5, -- x zone coin value
	FirstEggAt = 120, -- a new player's first run: a Common egg right in the middle here
	Margin = 160, -- pickups are made this far past the ball's target distance
}

-- All pickups for one run, up to `limit` studs. widthAt(s) gives the track width.
function Pickups.generate(seed: number, limit: number, widthAt: (number) -> number, firstEgg: boolean): { Pickup }
	local rng = Random.new(seed)
	local out: { Pickup } = {}
	local id = 0
	local function add(kind: string, s: number, x: number)
		id += 1
		table.insert(out, { Id = id, Kind = kind, s = s, x = x })
	end
	if firstEgg then
		add("Egg", Pickups.FirstEggAt, 0)
	end
	for kind, every in Pickups.Every do
		local s = 40 + rng:NextNumber(0, every)
		while s < limit do
			local half = widthAt(s) / 2 - 6
			if not (firstEgg and kind == "Egg" and s < Pickups.FirstEggAt + 60) then
				add(kind, s, rng:NextNumber(-half, half))
			end
			s += every * rng:NextNumber(0.6, 1.4)
		end
	end
	table.sort(out, function(a, b)
		return a.s < b.s
	end)
	return out
end

function Pickups.snowAt(s: number): number
	return Pickups.SnowPerPile * Zones.at(s).Index
end

function Pickups.coinsAt(s: number): number
	return Pickups.CoinsPerCluster * Zones.at(s).CoinValue
end

return Pickups
