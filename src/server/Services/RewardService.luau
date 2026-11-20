--!strict
-- Free rewards from Config/Rewards: daily streak, playtime gifts, the Lucky Wheel and the
-- tutorial reward (ported from Sweep's RewardService). One remote:
--   Rewards(action, arg) -> ok, message, extra
--   ClaimDaily, ClaimPlaytime(index), Spin -> (ok, message, segmentIndex)
-- Session playtime is counted by the 1 s loop, so it resets when the player rejoins.
-- Other services (CodeService, ShopService) give rewards through RewardService:Grant.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Pets = require(Shared.Config.Pets)
local Rewards = require(Shared.Config.Rewards)
local Zones = require(Shared.Config.Zones)

local RewardService = {}

local S: any
local clockOffset = 0
local wheelRng = Random.new()

local function now(): number
	return os.time() + clockOffset
end

-- Tests move the calendar (daily streak) without waiting for real days.
function RewardService:SkewClock(seconds: number)
	clockOffset += seconds
end

local function runtime(player: Player): any
	local session = S.DataService:GetSession(player)
	return session and session.Runtime
end

local function grantOne(player: Player, data, r: Rewards.Reward, sku: string): string
	if r.Kind == "Cash" then
		local cash = S.ShopService:CashFor(player, r.Seconds or 60, r.Floor)
		S.CashService:Give(player, cash, sku, Enum.AnalyticsEconomyTransactionType.Gameplay)
		return Format.cash(cash)
	elseif r.Kind == "Egg" then
		local rarity = r.Rarity or "Common"
		local zone = Zones.List[data.BestZone] or Zones.List[1]
		local uid = S.InventoryService:AddEgg(player, rarity, zone.Id, sku)
		return if uid then `{rarity} Egg` else `{rarity} Egg (bag full!)`
	elseif r.Kind == "Spin" then
		local amount = r.Amount or 1
		data.Spins = (data.Spins or 0) + amount
		return if amount > 1 then `{amount} Wheel Spins` else "Wheel Spin"
	elseif r.Kind == "Pet" then
		local id = r.Pet
		local huge = false
		if id == "Daily" then
			id = Rewards.DailyPet
			huge = (data.Daily.Weeks or 0) >= 1 -- every week after the first: Huge
			data.Daily.Weeks = (data.Daily.Weeks or 0) + 1
		end
		local def = id and Pets.ById[id]
		if not def then
			return ""
		end
		S.PetService:GivePet(player, def.Id, { Zone = "Meadow", Huge = if huge then true else nil })
		return if huge then `Huge {def.Name}` else def.Name
	elseif r.Kind == "Boost" then
		S.BoostService:AddPersonal(player, r.Boost, r.Minutes or 5)
		return `{if r.Boost == "Train2x" then "2x Power" else "2x Cash"} for {r.Minutes} min`
	elseif r.Kind == "Charge" then
		local name = r.Charge or "LuckyRoll"
		local amount = r.Amount or 1
		data.Charges[name] = (data.Charges[name] or 0) + amount
		return `{amount} {if name == "LuckyRoll" then "Lucky Rolls" else "Golden Runs"}`
	elseif r.Kind == "Power" then
		local gain = S.TrainService:Grant(player, r.Taps or 100, true)
		return `+{Format.big(gain)} Power`
	end
	return ""
end

local function grant(player: Player, r: Rewards.Reward, sku: string): string
	local data = S.DataService:GetData(player)
	if not data then
		return ""
	end
	local text = grantOne(player, data, r, sku)
	if r.Bonus then
		text ..= " + " .. grant(player, r.Bonus, sku)
	end
	return text
end

function RewardService:Grant(player: Player, r: Rewards.Reward, sku: string): string
	local text = grant(player, r, sku)
	S.StateService:Mark(player)
	return text
end

-------------------------------------------------------------------------- daily

-- (card 1-7, ready, streak shown, next open time or 0)
function RewardService:DailyStatus(data): (number, boolean, number, number)
	local daily = data.Daily
	local count = #Rewards.Daily
	local last = daily.LastClaim or 0
	local t = now()
	if daily.Streak <= 0 or last <= 0 or t - last >= Rewards.DailyStreakWindow then
		return 1, true, 0, 0
	end
	if t - last < Rewards.DailyCooldown then
		return (daily.Streak - 1) % count + 1, false, daily.Streak, last + Rewards.DailyCooldown
	end
	return daily.Streak % count + 1, true, daily.Streak, 0
end

local function claimDaily(player: Player): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading"
	end
	local index, ready, streak = RewardService:DailyStatus(data)
	if not ready then
		return false, "Come back tomorrow for the next reward!"
	end
	data.Daily.Streak = streak + 1
	data.Daily.LastClaim = now()
	local got = grant(player, Rewards.Daily[index], "Daily" .. index)
	S.AnalyticsService:Custom(player, "DailyClaimed", index)
	S.StateService:Mark(player)
	return true, `Day {index} reward: {got}!`
end

-------------------------------------------------------------------------- playtime

local function claimPlaytime(player: Player, index: any): (boolean, string?)
	local rt = runtime(player)
	local entry = type(index) == "number" and Rewards.Playtime[index]
	if not rt or not entry then
		return false, nil
	end
	if rt.PlaytimeClaimed[index] then
		return false, "Already claimed"
	end
	if rt.Playtime < entry.Minutes * 60 then
		return false, `Play {Format.time(entry.Minutes * 60 - rt.Playtime)} more to unlock this gift`
	end
	rt.PlaytimeClaimed[index] = true
	local got = grant(player, entry.Reward, "Playtime" .. index)
	S.StateService:Mark(player)
	return true, `Gift: {got}!`
end

-------------------------------------------------------------------------- lucky wheel

-- Whether the free spin can be used now, and when the next one opens.
local function freeSpin(data): (boolean, number?)
	local at = data.Flags.FreeSpinAt
	if type(at) ~= "number" then
		return true, nil
	end
	return now() - at >= Rewards.Wheel.FreeEvery, at + Rewards.Wheel.FreeEvery
end

function RewardService:AddSpins(player: Player, count: number): number
	local data = S.DataService:GetData(player)
	if not data then
		return 0
	end
	data.Spins = (data.Spins or 0) + count
	S.StateService:Mark(player)
	return data.Spins
end

local function rollSegment(): number
	local pick = wheelRng:NextNumber() * Rewards.wheelTotal()
	for i, seg in Rewards.Wheel.Segments do
		pick -= seg.Weight
		if pick < 0 then
			return i
		end
	end
	return 1
end

local function spin(player: Player): (boolean, string?, number?)
	local data = S.DataService:GetData(player)
	local rt = runtime(player)
	if not data or not rt then
		return false, "Still loading"
	end
	if (rt.WheelBusyUntil or 0) > os.clock() then
		return false, nil
	end
	local free = freeSpin(data)
	if free then
		data.Flags.FreeSpinAt = now()
	elseif (data.Spins or 0) > 0 then
		data.Spins -= 1
	else
		return false, "No spins left. Get more below!"
	end
	rt.WheelBusyUntil = os.clock() + Rewards.Wheel.SpinSeconds - 0.4
	local index = rollSegment()
	if not data.Flags.FirstSpinDone then
		data.Flags.FirstSpinDone = true
		for i, seg in Rewards.Wheel.Segments do
			if seg.Reward.Kind == "Egg" and seg.Reward.Rarity == Rewards.Wheel.FirstSpinRarity then
				index = i
				break
			end
		end
	end
	local seg = Rewards.Wheel.Segments[index]
	local got = grant(player, seg.Reward, "Wheel" .. index)
	S.StateService:Mark(player)
	S.AnalyticsService:Custom(player, "WheelSpin", index, { Free = tostring(free) })
	S.AnalyticsService:WheelSpun(player)
	if seg.Weight <= 1 then
		local name = player.DisplayName
		task.delay(Rewards.Wheel.SpinSeconds, function()
			Net.fireAll("Announce", `{name} hit the JACKPOT on the Lucky Wheel: {got}!`)
		end)
	end
	return true, `You won {got}!`, index
end

-------------------------------------------------------------------------- tutorial

function RewardService:TutorialReward(player: Player)
	local data = S.DataService:GetData(player)
	if not data or data.Flags.TutorialRewarded then
		return
	end
	data.Flags.TutorialRewarded = true
	local got = grant(player, Rewards.Tutorial, "Tutorial")
	S.StateService:Mark(player)
	Net.fire("Notify", player, `Tutorial done! You got a free {got}. Find the Lucky Wheel on the plaza!`, "Good")
end

-------------------------------------------------------------------------- snapshot

-- Added to the player snapshot (StateService) as Rewards.
function RewardService:Snapshot(player: Player): { [string]: any }?
	local data = S.DataService:GetData(player)
	local rt = runtime(player)
	if not data or not rt or not rt.Playtime then
		return nil
	end
	local index, ready, streak, nextAt = RewardService:DailyStatus(data)
	local claimed = {}
	for i in Rewards.Playtime do
		claimed[i] = rt.PlaytimeClaimed[i] == true
	end
	local free, freeAt = freeSpin(data)
	return {
		DailyIndex = index,
		DailyReady = ready,
		DailyStreak = streak,
		DailyNextAt = nextAt,
		DailyHuge = (data.Daily.Weeks or 0) >= 1,
		Playtime = rt.Playtime,
		PlaytimeClaimed = claimed,
		Spins = data.Spins or 0,
		FreeSpin = free,
		FreeSpinAt = freeAt,
		Now = now(),
	}
end

local ACTIONS: { [string]: (Player, any) -> (boolean, string?, any) } = {
	ClaimDaily = claimDaily,
	ClaimPlaytime = claimPlaytime,
	Spin = spin,
}

function RewardService:Init(services)
	S = services
	Net.onInvoke("Rewards", function(player, action, arg)
		local handler = type(action) == "string" and ACTIONS[action]
		if not handler then
			return false, nil
		end
		return handler(player, arg)
	end)
	S.DataService.ProfileLoaded:Connect(function(_player, session)
		session.Runtime.Playtime = 0
		session.Runtime.PlaytimeClaimed = {}
	end)
end

function RewardService:Start()
	task.spawn(function()
		while true do
			task.wait(1)
			for player, session in S.DataService:GetSessions() do
				local rt = session.Runtime
				if rt.Playtime then
					rt.Playtime += 1
					for _, entry in Rewards.Playtime do
						if rt.Playtime == entry.Minutes * 60 then
							S.StateService:Mark(player) -- badge on the Gifts button
						end
					end
				end
				if session.Data then
					local _, ready = RewardService:DailyStatus(session.Data)
					if ready and rt.DailyWasReady == false then
						S.StateService:Mark(player)
					end
					rt.DailyWasReady = ready
				end
			end
		end
	end)
end

return RewardService
