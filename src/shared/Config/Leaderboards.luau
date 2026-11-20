--!strict
-- Global leaderboards (Dev 2026-11-20: "add some leaderboards longest distance travelled
-- luckiest roll or smth ... they need to have some competition"). LeaderboardService keeps
-- the scores in OrderedDataStores (all time + this week), the four stands on the summit
-- plaza and the leaderboard window show them (LeaderboardController).
--
-- Kids research (LihFolk vault "Social Design and Multiplayer Play"): rank things players
-- control (not AFK time), weekly boards give newcomers a chance, younger players like
-- positive-sum status (crowns, "you passed X", server records) more than PvP.
local Format = require(script.Parent.Parent.Format)

export type Board = {
	Key: string,
	Title: string, -- one word
	Icon: string, -- Config/Images
	Color: Color3,
}

local Leaderboards = {
	Boards = {
		{ Key = "Distance", Title = "FARTHEST", Icon = "Roll", Color = Color3.fromRGB(0, 170, 255) },
		{ Key = "Luck", Title = "LUCKIEST", Icon = "Luck", Color = Color3.fromRGB(90, 215, 20) },
		{ Key = "Income", Title = "INCOME", Icon = "Cash", Color = Color3.fromRGB(255, 185, 0) },
		{ Key = "Earned", Title = "RICHEST", Icon = "Coin", Color = Color3.fromRGB(255, 50, 145) },
	} :: { Board },
	ByKey = {} :: { [string]: Board },
	Version = "v1",
	WorldTop = 10, -- rows on a plaza stand
	WindowTop = 50, -- rows in the window (one GetSortedAsync page)
	SaveSeconds = 120, -- each player's changed scores go to the stores this often
	LoadSeconds = 120, -- each server reads the boards this often
	SwapSeconds = 15, -- the plaza stands switch between ALL TIME and THIS WEEK
	-- Blender stand (art/blender/leaderboard.py): screen centre height + size, front face
	-- at z = 0 in model studs. LeaderboardService puts the SurfaceGui part there.
	ScreenY = 12.6,
	ScreenSize = Vector2.new(13.8, 17.2),
	-- Server best callouts only for real records (not the first tiny roll of a server).
	MinRecordDistance = 150,
	MinRecordLuck = 5,
}
for _, b in Leaderboards.Boards do
	Leaderboards.ByKey[b.Key] = b
end

-- Plaza spots (Config/World): behind the big snowman, outside the middle walk (lamps at
-- x +-22, benches +-28), in front of the Lucky Wheel, turned toward the deck so players
-- coming back up the track see them.
function Leaderboards.spots(): { CFrame }
	local y = 1000
	local target = Vector3.new(0, y, -40)
	local out = {}
	for i, x in { -70, -42, 42, 70 } do
		local z = if math.abs(x) > 50 then -188 else -196
		out[i] = CFrame.lookAt(Vector3.new(x, y, z), target)
	end
	return out
end

-- Weeks start Monday 00:00 UTC (the Unix epoch was a Thursday).
function Leaderboards.weekId(t: number?): number
	return ((t or os.time()) + 3 * 86400) // (7 * 86400)
end

function Leaderboards.weekEndsAt(t: number?): number
	return (Leaderboards.weekId(t) + 1) * 7 * 86400 - 3 * 86400
end

-- OrderedDataStores hold whole numbers only: money is stored as log10(value + 1) * SCALE.
local SCALE = 1e10

local function log10Big(v: any): number
	if type(v) == "table" then
		local m, e = v.m or 0, v.e or 0
		if m <= 0 then
			return 0
		end
		return if e == 0 then math.log10(m + 1) else math.log10(m) + e
	end
	local n = tonumber(v) or 0
	return if n > 0 then math.log10(n + 1) else 0
end

-- Value (number or BigNum) -> stored score.
function Leaderboards.encode(key: string, value: any): number
	if key == "Distance" then
		return math.max(0, math.floor(tonumber(value) or 0))
	elseif key == "Luck" then
		return math.max(0, math.floor((tonumber(value) or 0) * 100 + 0.5))
	end
	return math.max(0, math.floor(log10Big(value) * SCALE + 0.5))
end

-- Stored score -> BigNum-like value for money boards.
local function decodeCash(score: number): any
	local log = score / SCALE
	if log < 15 then
		return math.max(0, math.floor(10 ^ log - 1 + 0.5))
	end
	local e = math.floor(log)
	return { m = 10 ^ (log - e), e = e }
end

-- Stored score -> short display text ("1.2Km", "x52", "$4.1M/s", "$9.8B").
function Leaderboards.text(key: string, score: number): string
	if key == "Distance" then
		return Format.number(score) .. "m"
	elseif key == "Luck" then
		local luck = score / 100
		if luck < 10 then
			local t = string.format("%.1f", math.floor(luck * 10) / 10)
			if string.sub(t, -2) == ".0" then
				t = string.sub(t, 1, -3)
			end
			return "x" .. t
		end
		return "x" .. Format.number(math.floor(luck))
	elseif key == "Income" then
		return Format.cash(decodeCash(score)) .. "/s"
	end
	return Format.cash(decodeCash(score))
end

return Leaderboards
