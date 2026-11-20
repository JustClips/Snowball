--!strict
-- Global leaderboards, the overhead name tags' numbers and the small competition moments
-- (Dev 2026-11-20: a tag above each player with what their base makes, VIP tag,
-- leaderboards for longest roll / luckiest roll, "they need to have some competition").
--
-- Boards (Config/Leaderboards): FARTHEST (best roll, studs), LUCKIEST (best roll luck),
-- INCOME (best $/s of your base), RICHEST (cash earned). Each one has an all-time and a
-- this-week OrderedDataStore (weekly boards give new players a chance). Ported from Sweep
-- the World's LeaderboardService, plus:
--   * every server reads the top 50 of each board every LoadSeconds and publishes them in
--     ReplicatedStorage.Leaderboards (one StringValue of JSON per board + period), so the
--     plaza stands and the window draw on the client;
--   * scores are written only when they changed, staggered, every SaveSeconds + on leave;
--   * "you passed X": when a score goes up we check the cached top 50 (world / week) and
--     the players in this server and tell you who you just passed (RankEvent);
--   * server records: a new best roll or luckiest roll in this server is called out to
--     everyone (ServerRecord);
--   * player attributes for the name tags: ServerRank (1-3 by income in this server, the
--     crowns), WorldRank / WorldBoard (best all-time rank in the top 50). IncomePerSec and
--     VIP are set by PetService / ShopService.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Config = require(Shared.Config.Leaderboards)
local Net = require(Shared.Net)
local ModelLoader = require(script.Parent.Parent.Lib.ModelLoader)

local LeaderboardService = {}

type Row = { U: number, N: string, S: number }
type Period = "All" | "Week"

local PERIODS: { Period } = { "All", "Week" }
local TOAST_GAP = 8 -- seconds between "you passed" toasts for one player
local MONEY_TOAST_GAP = 60 -- income / earned climb all the time: fewer toasts
local RECORD_GAP = 15 -- seconds between server record callouts

local S: any
local allStores: { [string]: OrderedDataStore } = {}
local weekStores: { [string]: OrderedDataStore } = {}
local weekStoresId = -1
local cache: { [string]: { [string]: { Row } } } = {} -- key -> period -> rows (best first)
local names: { [number]: string } = {}
local published: Folder
local lastToast: { [Player]: number } = {}
local lastMoneyToast: { [Player]: number } = {}
local serverBest: { [string]: { UserId: number, Value: number } } = {}
local lastRecord = 0

-------------------------------------------------------------------------------- scores

local function ensureWeek(data: any)
	local stats = data.Stats
	local week = Config.weekId()
	if stats.WeekId ~= week then
		stats.WeekId = week
		stats.WeekDistance = 0
		stats.WeekLuck = 0
		stats.WeekIncome = 0
		stats.WeekEarnedStart = BigNum.toNumber(data.CashEarned)
	end
end

-- The raw value of each board for one period (numbers or BigNum).
local function values(data: any, period: Period): { [string]: any }
	local stats = data.Stats
	if period == "All" then
		return {
			Distance = data.BestDistance or 0,
			Luck = stats.BestLuck or 0,
			Income = stats.BestIncome or 0,
			Earned = data.CashEarned,
		}
	end
	return {
		Distance = stats.WeekDistance or 0,
		Luck = stats.WeekLuck or 0,
		Income = stats.WeekIncome or 0,
		Earned = math.max(0, BigNum.toNumber(data.CashEarned) - (stats.WeekEarnedStart or 0)),
	}
end

local function scores(data: any, period: Period): { [string]: number }
	local out = {}
	for key, v in values(data, period) do
		out[key] = Config.encode(key, v)
	end
	return out
end

-------------------------------------------------------------------------------- stores

local function weekStore(key: string): OrderedDataStore?
	local week = Config.weekId()
	if week ~= weekStoresId then
		weekStoresId = week
		table.clear(weekStores)
	end
	local store = weekStores[key]
	if not store then
		local ok, s = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, `LB_{key}_W{week}_{Config.Version}`)
		if ok then
			weekStores[key] = s
			store = s
		end
	end
	return store
end

local function storeFor(key: string, period: Period): OrderedDataStore?
	return if period == "All" then allStores[key] else weekStore(key)
end

local function save(player: Player, session: any)
	if not session or not session.Data or player.UserId <= 0 then
		return
	end
	local runtime = session.Runtime
	runtime.LbSaved = runtime.LbSaved or {}
	ensureWeek(session.Data)
	for _, period in PERIODS do
		for key, score in scores(session.Data, period) do
			local id = `{key}_{period}_{if period == "Week" then Config.weekId() else 0}`
			if score > 0 and runtime.LbSaved[id] ~= score then
				local store = storeFor(key, period)
				if store and pcall(store.SetAsync, store, tostring(player.UserId), score) then
					runtime.LbSaved[id] = score
				end
			end
		end
	end
end

-------------------------------------------------------------------------------- names

local function resolveNames(ids: { number })
	local missing = {}
	for _, id in ids do
		if not names[id] then
			local p = Players:GetPlayerByUserId(id)
			if p then
				names[id] = p.DisplayName
			else
				table.insert(missing, id)
			end
		end
	end
	for i = 1, #missing, 100 do
		local batch = table.move(missing, i, math.min(i + 99, #missing), 1, {})
		local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, batch)
		if ok and type(infos) == "table" then
			for _, info in infos do
				names[info.Id] = info.DisplayName or info.Username
			end
		end
	end
	for _, id in missing do
		if not names[id] then
			local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, id)
			names[id] = if ok and type(name) == "string" then name else "Player"
		end
	end
end

-------------------------------------------------------------------------------- loading

local function publish(key: string, period: Period, rows: { Row })
	local name = `{key}_{period}`
	local value = published:FindFirstChild(name) :: StringValue?
	if not value then
		local v = Instance.new("StringValue")
		v.Name = name
		v.Parent = published
		value = v
	end
	local ok, json = pcall(HttpService.JSONEncode, HttpService, rows);
	(value :: StringValue).Value = if ok then json else "[]"
end

local function loadBoard(key: string, period: Period)
	local store = storeFor(key, period)
	if not store then
		return
	end
	local ok, pages = pcall(store.GetSortedAsync, store, false, Config.WindowTop)
	if not ok then
		return
	end
	local list = (pages :: DataStorePages):GetCurrentPage()
	local ids = {}
	for _, entry in list do
		local id = tonumber(entry.key)
		if id then
			table.insert(ids, id)
		end
	end
	resolveNames(ids)
	local rows: { Row } = {}
	for _, entry in list do
		local id = tonumber(entry.key)
		if id and type(entry.value) == "number" and entry.value > 0 then
			table.insert(rows, { U = id, N = names[id] or "Player", S = entry.value })
		end
	end
	cache[key] = cache[key] or {}
	cache[key][period] = rows
	publish(key, period, rows)
end

local function loadAll()
	for _, board in Config.Boards do
		for _, period in PERIODS do
			loadBoard(board.Key, period)
			task.wait(0.25)
		end
	end
	published:SetAttribute("WeekEndsAt", Config.weekEndsAt())
	published:SetAttribute("LoadedAt", os.time())
end

-------------------------------------------------------------------------------- ranks

-- Rank of `score` among the cached rows (ignoring `userId`'s own old row), or nil if it
-- would not make the top WindowTop.
local function rankIn(rows: { Row }?, userId: number, score: number): number?
	if not rows or score <= 0 then
		return nil
	end
	local above = 0
	local others = 0
	for _, row in rows do
		if row.U ~= userId then
			others += 1
			if row.S > score then
				above += 1
			end
		end
	end
	if above >= Config.WindowTop or (others >= Config.WindowTop and above >= others) then
		return nil
	end
	return above + 1
end

-- The best player (highest score) we went past: old <= their score < new.
local function passedIn(rows: { Row }?, userId: number, old: number, new: number): Row?
	local best: Row? = nil
	for _, row in rows or {} do
		if row.U ~= userId and row.S >= old and row.S < new and (not best or row.S > best.S) then
			best = row
		end
	end
	return best
end

local function serverPassed(player: Player, key: string, old: number, new: number): Player?
	local best: Player? = nil
	local bestScore = -1
	for other, session in S.DataService:GetSessions() do
		if other ~= player and session.Data then
			local s = scores(session.Data, "All")[key] or 0
			if s > 0 and s >= old and s < new and s > bestScore then
				best = other
				bestScore = s
			end
		end
	end
	return best
end

-- A score went up: tell the player who they passed / where they are now.
local function checkPassed(player: Player, key: string, old: number, new: number, weekOld: number, weekNew: number)
	if new <= old and weekNew <= weekOld then
		return
	end
	local now = os.clock()
	if now - (lastToast[player] or -100) < TOAST_GAP then
		return
	end
	local money = key == "Income" or key == "Earned"
	if money and now - (lastMoneyToast[player] or -100) < MONEY_TOAST_GAP then
		return
	end
	local board = cache[key] or {}
	local event: { [string]: any }? = nil
	local passed = if new > old then passedIn(board.All, player.UserId, old, new) else nil
	if passed then
		event = {
			Kind = "Passed",
			Board = key,
			Scope = "World",
			UserId = passed.U,
			Name = passed.N,
			Rank = rankIn(board.All, player.UserId, new),
		}
	else
		local weekPassed = if weekNew > weekOld then passedIn(board.Week, player.UserId, weekOld, weekNew) else nil
		if weekPassed then
			event = {
				Kind = "Passed",
				Board = key,
				Scope = "Week",
				UserId = weekPassed.U,
				Name = weekPassed.N,
				Rank = rankIn(board.Week, player.UserId, weekNew),
			}
		else
			local other = if new > old then serverPassed(player, key, old, new) else nil
			if other then
				event = {
					Kind = "Passed",
					Board = key,
					Scope = "Server",
					UserId = other.UserId,
					Name = other.DisplayName,
				}
			end
		end
	end
	if event then
		lastToast[player] = now
		if money then
			lastMoneyToast[player] = now
		end
		Net.fire("RankEvent", player, event)
	end
end

-- Remembers each player's last scores so the 1 s loop sees what went up.
local function track(player: Player, session: any)
	local runtime = session.Runtime
	local all = scores(session.Data, "All")
	local week = scores(session.Data, "Week")
	local last = runtime.LbLast
	runtime.LbLast = { All = all, Week = week }
	if not last then
		return
	end
	for key, score in all do
		local old = last.All[key] or 0
		local weekOld = last.Week[key] or 0
		if score > old or (week[key] or 0) > weekOld then
			checkPassed(player, key, old, score, weekOld, week[key] or 0)
		end
	end
end

-- Server crowns (top 3 base income in this server) and the best world rank, for the tags.
local function updateRanks()
	local list = {}
	for player in S.DataService:GetSessions() do
		local income = tonumber(player:GetAttribute("IncomePerSec")) or 0
		if income > 0 then
			table.insert(list, { player = player, income = income })
		end
	end
	table.sort(list, function(a, b)
		return a.income > b.income
	end)
	local crowned: { [Player]: number } = {}
	if #Players:GetPlayers() >= 2 then
		for i = 1, math.min(3, #list) do
			crowned[list[i].player] = i
		end
	end
	for _, player in Players:GetPlayers() do
		player:SetAttribute("ServerRank", crowned[player])
		local bestRank, bestBoard = nil, nil
		for _, board in Config.Boards do
			for i, row in (cache[board.Key] or {}).All or {} do
				if row.U == player.UserId then
					if not bestRank or i < bestRank then
						bestRank, bestBoard = i, board.Key
					end
					break
				end
			end
		end
		player:SetAttribute("WorldRank", bestRank)
		player:SetAttribute("WorldBoard", bestBoard)
	end
end

-------------------------------------------------------------------------------- hooks

-- RollService calls this when a ball cracks (distance in studs, the roll's luck).
function LeaderboardService:RollEnded(player: Player, distance: number, luck: number)
	local session = S.DataService:GetSession(player)
	if not session then
		return
	end
	local data = session.Data
	ensureWeek(data)
	local stats = data.Stats
	stats.BestLuck = math.max(stats.BestLuck or 0, luck)
	stats.WeekLuck = math.max(stats.WeekLuck or 0, luck)
	stats.WeekDistance = math.max(stats.WeekDistance or 0, distance)
	-- Server records: the best roll / luckiest roll since this server started.
	for key, value in { Distance = distance, Luck = luck } do
		local min = if key == "Distance" then Config.MinRecordDistance else Config.MinRecordLuck
		local best = serverBest[key]
		if value >= min and (not best or value > best.Value) then
			local beatOther = best ~= nil and best.UserId ~= player.UserId
			serverBest[key] = { UserId = player.UserId, Value = value }
			local now = os.clock()
			if #Players:GetPlayers() >= 2 and (beatOther or not best) and now - lastRecord >= RECORD_GAP then
				lastRecord = now
				Net.fireAll("ServerRecord", {
					Board = key,
					UserId = player.UserId,
					Name = player.DisplayName,
					Score = Config.encode(key, value),
				})
			end
		end
	end
	track(player, session)
end

-- Own scores for the window's "you" row: { All = { key = score }, Week = {...} }.
local function myScores(player: Player): any
	local data = S.DataService:GetData(player)
	if not data then
		return nil
	end
	ensureWeek(data)
	return { All = scores(data, "All"), Week = scores(data, "Week") }
end

-------------------------------------------------------------------------------- stands

-- The four Blender stands on the summit plaza, each with an invisible Screen part that
-- clients put the board's SurfaceGui on (LeaderboardController).
local function buildStands()
	local mountain = Workspace:WaitForChild("Mountain")
	local summit = mountain:WaitForChild("Summit")
	local old = summit:FindFirstChild("Leaderboards")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	folder.Parent = summit
	for i, cf in Config.spots() do
		local board = Config.Boards[i]
		if not board then
			break
		end
		local stand = Instance.new("Model")
		stand.Name = "Stand_" .. board.Key
		local screen = Instance.new("Part")
		screen.Name = "Screen"
		screen.Anchored = true
		screen.CanCollide = false
		screen.CanQuery = true -- taps on the SurfaceGui
		screen.CanTouch = false
		screen.CastShadow = false
		screen.Transparency = 1
		screen.Size = Vector3.new(Config.ScreenSize.X, Config.ScreenSize.Y, 0.2)
		screen.CFrame = cf * CFrame.new(0, Config.ScreenY, -0.15)
		screen:SetAttribute("Board", board.Key)
		screen.Parent = stand
		local look = ModelLoader.clone("Leaderboard", cf)
		if look then
			look.Name = "Look"
			for _, d in look:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = true
					d.CanQuery = false
				end
			end
			look.Parent = stand
		else
			-- Graybox until the model loads (or if it can't).
			local panel = Instance.new("Part")
			panel.Name = "Panel"
			panel.Anchored = true
			panel.Material = Enum.Material.SmoothPlastic
			panel.Color = Color3.fromRGB(46, 51, 62)
			panel.Size = Vector3.new(Config.ScreenSize.X + 2, Config.ScreenSize.Y + 2, 0.8)
			panel.CFrame = cf * CFrame.new(0, Config.ScreenY, 0.4)
			panel.CanQuery = false
			panel.Parent = stand
		end
		stand.Parent = folder
	end
end

-------------------------------------------------------------------------------- leaderstats

local function ensureStats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, name in { "Income", "Best" } do
		local v = Instance.new("StringValue")
		v.Name = name
		v.Value = "0"
		v.Parent = stats
	end
	stats.Parent = player
end

local function refreshStats(player: Player, data: any, income: number)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	(stats:FindFirstChild("Income") :: StringValue).Value = Format.cash(income) .. "/s"
	(stats:FindFirstChild("Best") :: StringValue).Value = Format.number(data.BestDistance or 0) .. "m"
end

-------------------------------------------------------------------------------- boot

function LeaderboardService:Init(services)
	S = services
	published = Instance.new("Folder")
	published.Name = "Leaderboards"
	published.Parent = ReplicatedStorage
	for _, board in Config.Boards do
		local ok, store =
			pcall(DataStoreService.GetOrderedDataStore, DataStoreService, `LB_{board.Key}_All_{Config.Version}`)
		if ok then
			allStores[board.Key] = store
		end
	end
	S.DataService.ProfileLoaded:Connect(function(player, session)
		ensureWeek(session.Data)
		ensureStats(player)
		track(player, session)
	end)
	S.DataService.ProfileReleasing:Connect(function(player, session)
		save(player, session)
	end)
	Net.onInvoke("Leaderboards", function(player)
		return myScores(player)
	end)
	local function hideDefaultName(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			-- Our own tag (NametagController) replaces Roblox's name.
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(hideDefaultName)
		if player.Character then
			task.spawn(hideDefaultName, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastToast[player] = nil
		lastMoneyToast[player] = nil
	end)
end

function LeaderboardService:Start()
	task.spawn(buildStands)
	-- Every second: income bests, week rollover, leaderstats, "you passed" checks.
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(1)
			tick += 1
			for player, session in S.DataService:GetSessions() do
				local data = session.Data
				if data then
					ensureWeek(data)
					local income = if S.PetService then S.PetService:GetIncomePerSec(player) else 0
					data.Stats.BestIncome = math.max(data.Stats.BestIncome or 0, income)
					data.Stats.WeekIncome = math.max(data.Stats.WeekIncome or 0, income)
					refreshStats(player, data, income)
					track(player, session)
				end
			end
			if tick % 5 == 0 then
				updateRanks()
			end
		end
	end)
	-- Changed scores go to the stores, one player at a time.
	task.spawn(function()
		while true do
			task.wait(Config.SaveSeconds)
			for player, session in S.DataService:GetSessions() do
				save(player, session)
				task.wait(0.3)
			end
		end
	end)
	-- Every server reads the boards (top 50 of each) and shares them with its clients.
	task.spawn(function()
		task.wait(4)
		while true do
			loadAll()
			updateRanks()
			task.wait(Config.LoadSeconds)
		end
	end)
end

return LeaderboardService
