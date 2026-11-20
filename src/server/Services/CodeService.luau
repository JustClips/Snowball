--!strict
-- Codes players type in the Codes window. Each player can use each code once; codes can
-- expire. Codes live in src/server/Config/Codes.luau (admin-added codes from Sweep's
-- DataStore version can be ported later). Remote: RedeemCode(code) -> ok, message.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Codes = require(script.Parent.Parent.Config.Codes)

local MAX_WRONG = 6 -- wrong guesses a minute before the player has to wait

local CodeService = {}

local S: any
local wrong: { [Player]: { count: number, since: number } } = {}

local function normalize(text: any): string?
	if type(text) ~= "string" then
		return nil
	end
	local clean = string.upper((string.gsub(string.sub(text, 1, 60), "[^%w]", "")))
	if clean == "" or #clean > 30 then
		return nil
	end
	return clean
end

local function redeem(player: Player, text: any): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading"
	end
	local w = wrong[player]
	if w and os.clock() - w.since < 60 and w.count >= MAX_WRONG then
		return false, "Too many tries. Wait a minute."
	end
	local code = normalize(text)
	local def = code and Codes[code]
	if not code or not def then
		if not w or os.clock() - w.since >= 60 then
			w = { count = 0, since = os.clock() }
			wrong[player] = w
		end
		(w :: any).count += 1
		return false, "That code doesn't exist"
	end
	if def.ExpiresAt and os.time() >= def.ExpiresAt then
		return false, "That code has expired"
	end
	if data.CodesRedeemed[code] then
		return false, "You already used that code"
	end
	data.CodesRedeemed[code] = os.time()
	local got = {}
	for i, reward in def.Rewards do
		table.insert(got, S.RewardService:Grant(player, reward, `Code_{code}_{i}`))
	end
	S.AnalyticsService:Custom(player, "CodeRedeemed", 1, { Code = code })
	return true, `Code redeemed: {table.concat(got, " + ")}!`
end

function CodeService:Init(services)
	S = services
	Net.onInvoke("RedeemCode", redeem)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		wrong[player] = nil
	end)
end

return CodeService
