--!strict
-- Admin chat commands for testing (GAME_PLAN §12): admins only, anyone in Studio.
--   /power <n>      set your Power          /cash <n>     add cash
--   /pop <tier>     show a pop now (Snowflake, Ice, Frost, Golden, Present, Coin, Luck, Rainbow25...)
--   /egg <rarity>   add an egg to your bag  /avalanche    start an Avalanche
--   /reset          wipe your save (rejoin after)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Pops = require(Shared.Config.Pops)

local AdminService = {}

local S: any
local ADMINS: { [number]: boolean } = { [822623546] = true, [347852675] = true }

function AdminService:IsAdmin(player: Player): boolean
	return ADMINS[player.UserId] == true or RunService:IsStudio()
end

local function parseNumber(text: string?): number?
	if not text then
		return nil
	end
	local n = tonumber(text)
	if n then
		return n
	end
	local num, suffix = string.match(string.lower(text), "^([%d%.]+)(%a+)$")
	local mult = ({ k = 1e3, m = 1e6, b = 1e9, t = 1e12 } :: { [string]: number })[suffix or ""]
	return if num and mult then (tonumber(num) or 0) * mult else nil
end

local COMMANDS: { [string]: (Player, { string }) -> string? } = {
	power = function(player, args)
		local n = parseNumber(args[1])
		if not n then
			return "Usage: /power 50M"
		end
		S.RollService:SetPower(player, n)
		return `Power set to {args[1]}`
	end,
	cash = function(player, args)
		local n = parseNumber(args[1])
		if not n then
			return "Usage: /cash 1M"
		end
		S.CashService:Give(player, n, "Admin")
		return `+{args[1]} cash`
	end,
	pop = function(player, args)
		local tier = Pops.ById[args[1] or "Golden"]
		if not tier then
			return "Unknown pop tier"
		end
		S.PopService:ForceNext(player, tier.Id)
		return `Next pop: {tier.Id} (stand on your roller)`
	end,
	egg = function(player, args)
		S.InventoryService:AddEgg(player, args[1] or "Rare", "Pine", "Admin")
		return "Egg added"
	end,
	avalanche = function(player)
		if not S.AvalancheService then
			return "Avalanche isn't built yet"
		end
		S.AvalancheService:Trigger(player)
		return nil
	end,
	village = function(player)
		local data = S.DataService:GetData(player)
		if data then
			data.ReachedVillage = true
			S.StateService:Mark(player)
		end
		return "Village marked as reached (Rebirth unlocked)"
	end,
	keeprolling = function(player)
		local session = S.DataService:GetSession(player)
		if session then
			session.Runtime.ForceContinue = not session.Runtime.ForceContinue
			return if session.Runtime.ForceContinue
				then "KEEP ROLLING? now shows after every roll"
				else "KEEP ROLLING? back to near misses only"
		end
		return "No save loaded"
	end,
	starter = function(player)
		local session = S.DataService:GetSession(player)
		if session then
			local data = session.Data
			data.Flags.StarterPackBought = false
			data.Flags.StarterPackEnds = os.time() + 7200
			session.Runtime.StarterShown = nil
			session.Runtime.TutorialDoneAt = nil
			S.StateService:Mark(player)
		end
		return "Starter Pack is for sale again (pops in a few seconds if the tutorial is done)"
	end,
	nextday = function(player)
		S.RewardService:SkewClock(86400)
		S.StateService:Mark(player)
		return "Moved the reward clock 24 h ahead (this server)"
	end,
	spins = function(player, args)
		local n = tonumber(args[1]) or 5
		S.RewardService:AddSpins(player, n)
		return `+{n} wheel spins`
	end,
	reset = function(player)
		local session = S.DataService:GetSession(player)
		if session then
			session.Profile.Data = nil
			player:Kick("Save wiped. Rejoin!")
		end
		return nil
	end,
}

local function onChat(player: Player, message: string)
	if string.sub(message, 1, 1) ~= "/" or not AdminService:IsAdmin(player) then
		return
	end
	local words = string.split(string.sub(message, 2), " ")
	local name = string.lower(table.remove(words, 1) or "")
	local fn = COMMANDS[name]
	if not fn then
		return
	end
	local ok, result = pcall(fn, player, words)
	Net.fire(
		"Notify",
		player,
		if ok then (result or "Done") else "Error: " .. tostring(result),
		if ok then "Info" else "Bad"
	)
end

function AdminService:Init(services)
	S = services
	local function hook(player: Player)
		player.Chatted:Connect(function(message)
			onChat(player, message)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
end

return AdminService
