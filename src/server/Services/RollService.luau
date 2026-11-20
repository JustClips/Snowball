--!strict
-- Rolling (GAME_PLAN §5.5, §5.6): Idle -> Packing -> Rolling -> Cracking.
-- The server owns everything: the pack meter clock, the 20 Hz sim of every ball (Roll.step),
-- pickups, obstacles and the crack. Clients only send the pack tap time and steering, and
-- draw balls from 10 Hz snapshots (buffer) with the same Roll math for prediction.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local Obstacles = require(Shared.Config.Obstacles)
local Pickups = require(Shared.Config.Pickups)
local Products = require(Shared.Config.Products)
local PowerCurve = require(Shared.PowerCurve)
local Roll = require(Shared.Roll)
local RollMath = require(Shared.RollMath)
local Spline = require(Shared.Spline)
local Upgrades = require(Shared.Config.Upgrades)
local World = require(Shared.Config.World)
local Zones = require(Shared.Config.Zones)
local RunService = game:GetService("RunService")

local RollService = {}

local S: any
local SIM_HZ = 20
local SNAP_HZ = 10
local CRACK_SECONDS = 1.6
local DECK_MARGIN = 14 -- studs around the deck where StartPack is allowed

type Run = {
	phase: string,
	lane: number,
	packStart: number,
	packQuality: string?,
	ball: Roll.Ball?,
	seed: number,
	pickups: { Pickups.Pickup },
	pickIndex: number,
	obsIndex: number,
	hitObstacles: { [number]: boolean },
	coins: number,
	smashCash: number,
	eggs: { { Rarity: string, Zone: string } },
	eggSlots: number,
	fullBounces: number,
	bonks: number,
	smashes: number,
	zone: number,
	luck: number,
	golden: boolean,
	lucky: boolean,
	longRoll: boolean?,
	startedAt: number,
	limit: number, -- pickups exist up to here
	continues: number, -- Keep Rolling pushes bought this roll
	stopDeadline: number, -- os.clock() when the KEEP ROLLING? window cracks the ball
}

local runs: { [Player]: Run } = {}
local spline: Spline.Spline
local obstacles: { Obstacles.Obstacle } = {}
local endAt = 0
local rng = Random.new()

function RollService:IsBusy(player: Player): boolean
	local run = runs[player]
	return run ~= nil and run.phase ~= "Idle"
end

function RollService:GetPhase(player: Player): string
	local run = runs[player]
	return if run then run.phase else "Idle"
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function setAnchored(player: Player, anchored: boolean)
	local root = rootOf(player)
	if root then
		root.Anchored = anchored
	end
end

local function standAtDeck(player: Player, lane: number, back: number?)
	local root = rootOf(player)
	local character = player.Character
	if root and character then
		local pos = World.DeckStand + Vector3.new(World.laneX(lane), 0, -(back or 0))
		character:PivotTo(CFrame.lookAt(pos, pos + Vector3.zAxis))
		root.Anchored = true
	end
end

local function nearDeck(player: Player): boolean
	local root = rootOf(player)
	if not root then
		return false
	end
	local d = root.Position - World.Deck.Center
	local half = World.Deck.Size / 2
	return math.abs(d.X) <= half.X + DECK_MARGIN and math.abs(d.Z) <= half.Z + DECK_MARGIN and math.abs(d.Y) < 12
end

local function setPhase(player: Player, run: Run, phase: string)
	run.phase = phase
	player:SetAttribute("RollPhase", if phase == "Idle" then nil else phase)
	S.StateService:Mark(player)
end

-- StartPack: walk onto the deck (or press ROLL near it). Starts the pack meter.
local function startPack(player: Player): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading"
	end
	local run = runs[player]
	if run and run.phase ~= "Idle" then
		return false, "Already rolling"
	end
	if not nearDeck(player) then
		return false, "Walk to the launch deck first"
	end
	local lane = player:GetAttribute("BaseIndex") or 1
	run = {
		phase = "Packing",
		lane = lane :: number,
		packStart = Workspace:GetServerTimeNow(),
		ball = nil,
		seed = rng:NextInteger(1, 2 ^ 30),
		pickups = {},
		pickIndex = 1,
		obsIndex = 1,
		hitObstacles = {},
		coins = 0,
		smashCash = 0,
		eggs = {},
		eggSlots = data.EggSlots,
		fullBounces = 0,
		bonks = 0,
		smashes = 0,
		zone = 1,
		luck = 1,
		golden = false,
		lucky = false,
		startedAt = 0,
		limit = 0,
		continues = 0,
		stopDeadline = 0,
	}
	runs[player] = run
	setPhase(player, run, "Packing")
	-- Pack right where you stand on the deck (keep your x; line up on the stand row).
	local root = rootOf(player)
	local character = player.Character
	if root and character then
		local half = World.Deck.Size.X / 2 - 6
		local x = math.clamp(root.Position.X - World.Deck.Center.X, -half, half)
		local pos = World.DeckStand + Vector3.new(x, 0, 0)
		character:PivotTo(CFrame.lookAt(pos, pos + Vector3.zAxis))
		root.Anchored = true
	else
		standAtDeck(player, run.lane)
	end
	local green = Upgrades.packGreen(data.PackZone)
	Net.fire("PackStart", player, run.packStart, RollMath.PackPeriod, green, Upgrades.PackYellow)
	return true, nil
end

local function cancelPack(player: Player): (boolean, string?)
	local run = runs[player]
	if run and run.phase == "Packing" then
		setPhase(player, run, "Idle")
		setAnchored(player, false)
		return true, nil
	end
	return false, nil
end

local function launch(player: Player, run: Run, quality: string)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	run.packQuality = quality
	-- Luck for this roll, built up in parts so the client can reveal each one (LuckController):
	-- your base luck (core, rebirths, passes, server boosts), the pack hit, the free Lucky
	-- Roll every Economy.LuckyEvery rolls, and the charges (Super Lucky x100, Lucky Roll x10
	-- with +50% distance, Luck Pop x3).
	local base = S.BoostService:GetLuck(player)
	local luck = base
	local parts = {}
	local pack = Economy.PackLuck[quality] or 1
	if pack > 1 then
		luck *= pack
		table.insert(parts, { Name = string.upper(quality), Mult = pack })
	end
	if (data.Stats.Runs + 1) % Economy.LuckyEvery == 0 then
		luck *= Economy.LuckyEveryMult
		run.lucky = true
		table.insert(parts, { Name = "LUCKY ROLL", Mult = Economy.LuckyEveryMult })
	end
	if data.Charges.SuperLucky > 0 then
		data.Charges.SuperLucky -= 1
		luck *= 100
		run.lucky = true
		table.insert(parts, { Name = "SUPER LUCKY", Mult = 100 })
	elseif data.Charges.LuckyRoll > 0 then
		data.Charges.LuckyRoll -= 1
		luck *= 10
		run.lucky = true
		run.longRoll = true
		table.insert(parts, { Name = "LUCKY CHARGE", Mult = 10 })
	end
	if (data.Charges.LuckPop or 0) > 0 then
		data.Charges.LuckPop -= 1
		luck *= 3
		table.insert(parts, { Name = "LUCK POP", Mult = 3 })
	end
	run.golden = data.Gamepasses.GoldenSnowball == true
	if not run.golden and data.Charges.GoldenRuns > 0 then
		data.Charges.GoldenRuns -= 1
		run.golden = true
	end
	run.luck = luck
	local D = PowerCurve.distance(data.Power) * (PowerCurve.PackMult[quality] or 0.7)
	if run.longRoll then
		D *= 1.5
	end
	local core = Upgrades.Cores[data.Core] or Upgrades.Cores[1]
	-- The ball starts where YOU stand on the deck (Dev 2026-11-20: standing on the right, it
	-- spawned on the left). Track x runs along the spline's Right, which at the top points
	-- to world -X, so World.laneX can't be used as a track x directly.
	local start = spline:sample(0)
	local x = -World.laneX(run.lane)
	local root = rootOf(player)
	if root then
		x = (root.Position - start.Pos):Dot(start.Right)
	end
	x = math.clamp(x, -start.Width / 2 + 6, start.Width / 2 - 6)
	run.ball = Roll.new(x, D, core.Growth)
	local firstEgg = data.Stats.Runs == 0 and data.Stats.EggsFound == 0
	local limit = math.min(spline.Length, D * 1.15 + Pickups.Margin)
	run.pickups = Pickups.generate(run.seed, limit, RollMath.widthAt, firstEgg)
	run.limit = limit
	run.startedAt = os.clock()
	setPhase(player, run, "Rolling")
	S.StateService:Mark(player)
	Net.fireAll("RunStarted", player.UserId, {
		Seed = run.seed,
		Limit = limit,
		X = x,
		D = D,
		Growth = core.Growth,
		FirstEgg = firstEgg,
		Golden = run.golden,
		Quality = quality,
		Lucky = run.lucky,
		Luck = luck,
		BaseLuck = base,
		LuckParts = parts,
	})
	S.AnalyticsService:Funnel(player, "FirstPush")
end

local function onPackTap(player: Player, clientTime: any)
	local run = runs[player]
	if not run or run.phase ~= "Packing" then
		return
	end
	local now = Workspace:GetServerTimeNow()
	-- The client says when it tapped; trust it only within a small latency window.
	local t = if type(clientTime) == "number" then math.clamp(clientTime, now - 0.5, now) else now
	t = math.max(t, run.packStart)
	local data = S.DataService:GetData(player)
	local quality =
		RollMath.packQuality(t - run.packStart, Upgrades.packGreen(data and data.PackZone or 0), Upgrades.PackYellow)
	launch(player, run, quality)
end

local function onSteer(player: Player, value: any)
	local run = runs[player]
	if run and run.phase == "Rolling" and run.ball and type(value) == "number" and value == value then
		run.ball.steer = math.clamp(value, -1, 1)
	end
end

local function event(player: Player, kind: string, payload: any)
	Net.fire("RunEvent", player, kind, payload)
end

local function collect(player: Player, run: Run, pickup: Pickups.Pickup)
	local ball = run.ball :: Roll.Ball
	if pickup.Kind == "Snow" then
		Roll.addSnow(ball, Pickups.snowAt(pickup.s))
	elseif pickup.Kind == "Coin" then
		run.coins += Pickups.coinsAt(pickup.s) * (if run.golden then 2 else 1)
	elseif pickup.Kind == "Ramp" then
		Roll.ramp(ball)
	elseif pickup.Kind == "Present" then
		run.coins += Pickups.coinsAt(pickup.s) * 8
	elseif pickup.Kind == "Egg" then
		if #run.eggs >= run.eggSlots then
			run.fullBounces += 1
			event(player, "Full", pickup.Id)
			return
		end
		local zone = Zones.at(pickup.s)
		local data = S.DataService:GetData(player)
		local first = data and data.Stats.EggsFound == 0 and #run.eggs == 0 and pickup.s == Pickups.FirstEggAt
		local rarity = if first then "Common" else S.InventoryService:RollRarity(zone.Id, run.luck)
		table.insert(run.eggs, { Rarity = rarity, Zone = zone.Id })
		event(player, "Egg", { Id = pickup.Id, Rarity = rarity })
		return
	end
	event(player, "Pickup", pickup.Id)
end

local function checkHits(player: Player, run: Run)
	local ball = run.ball :: Roll.Ball
	-- Pickups (sorted by s): advance past the ones behind, test the ones in reach.
	local reach = ball.r + Pickups.HitRadius
	while run.pickIndex <= #run.pickups and run.pickups[run.pickIndex].s < ball.s - reach do
		run.pickIndex += 1
	end
	local i = run.pickIndex
	while i <= #run.pickups and run.pickups[i].s <= ball.s + reach do
		local p = run.pickups[i]
		if p.Kind ~= "Taken" and math.abs(p.x - ball.x) <= reach and math.abs(p.s - ball.s) <= reach then
			collect(player, run, p)
			p.Kind = "Taken"
		end
		i += 1
	end
	-- Obstacles (fixed layout, sorted by s).
	while run.obsIndex <= #obstacles and obstacles[run.obsIndex].s < ball.s - ball.r - 10 do
		run.obsIndex += 1
	end
	i = run.obsIndex
	local size = if run.golden then ball.r * 1.5 else ball.r
	while i <= #obstacles and obstacles[i].s <= ball.s + ball.r + 10 do
		local o = obstacles[i]
		if not run.hitObstacles[o.Id] then
			local ds, dx = o.s - ball.s, o.x - ball.x
			local reachO = ball.r + o.Radius
			if ds * ds + dx * dx <= reachO * reachO then
				run.hitObstacles[o.Id] = true
				if size >= o.SizeNeeded then
					run.smashes += 1
					run.smashCash += Obstacles.ById[o.Kind].Cash * Zones.at(o.s).CoinValue
					Roll.smash(ball)
					event(player, "Smash", o.Id)
				else
					run.bonks += 1
					Roll.bonk(ball, -dx)
					event(player, "Bonk", o.Id)
				end
			end
		end
		i += 1
	end
	local zone = Zones.at(ball.s)
	if zone.Index > run.zone then
		run.zone = zone.Index
		event(player, "Zone", zone.Index)
		S.AnalyticsService:ZoneReached(player, zone.Index)
	end
end

-- Streaming is on (radius 640 around the character, who stays on the deck), so the far
-- track never loaded and the zone "ended" (Dev 2026-11-20). While rolling, the player's
-- ReplicationFocus is a part riding ahead of their ball.
local focusParts: { [Player]: BasePart } = {}
local function setFocus(player: Player, at: Vector3?)
	local part = focusParts[player]
	if at then
		if not part then
			local p = Instance.new("Part")
			p.Name = "StreamFocus_" .. player.UserId
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Transparency = 1
			p.Size = Vector3.one
			p.Parent = Workspace
			focusParts[player] = p
			part = p
		end
		(part :: BasePart).Position = at
		player.ReplicationFocus = part
	elseif part then
		player.ReplicationFocus = nil
		part:Destroy()
		focusParts[player] = nil
	end
end

local function finish(player: Player, run: Run)
	local data = S.DataService:GetData(player)
	local ball = run.ball :: Roll.Ball
	if not data then
		runs[player] = nil
		return
	end
	setPhase(player, run, "Cracking")
	local zone = Zones.at(ball.s)
	local village = ball.s >= endAt - 1
	local cash = run.coins + run.smashCash + ball.r * zone.CoinValue * 2
	if village then
		cash *= 3
		local rarity = S.InventoryService:RollRarity("Village", run.luck)
		table.insert(run.eggs, { Rarity = rarity, Zone = "Village" })
	end
	cash *= S.BoostService:GetCashMult(player)
	local paid = S.CashService:Give(player, cash, "Run")
	local record = ball.s > data.BestDistance
	data.Stats.Runs += 1
	data.Stats.TotalDistance += math.floor(ball.s)
	data.Stats.Smashes += run.smashes
	if record then
		data.BestDistance = math.floor(ball.s)
		S.AnalyticsService:Custom(player, "RecordDistance", math.floor(ball.s))
	end
	data.BestZone = math.max(data.BestZone, zone.Index)
	data.BiggestRadius = math.max(data.BiggestRadius, ball.r)
	local firstVillage = village and not data.ReachedVillage
	if village then
		data.ReachedVillage = true
	end
	-- The eggs are NOT banked here any more (Dev 2026-11-20, egg rescue): they stay frozen in
	-- a snow pile where the ball cracked and you carry them uphill past the yeti
	-- (EggRescueService). Every roll leaves at least one egg to rescue.
	if #run.eggs == 0 then
		table.insert(run.eggs, { Rarity = S.InventoryService:RollRarity(zone.Id, run.luck), Zone = zone.Id })
	end
	local eggsAdded = {}
	for _, egg in run.eggs do
		table.insert(eggsAdded, egg.Rarity)
	end
	if S.AvalancheService then
		S.AvalancheService:AddRadius(player, ball.r)
	end
	local result = {
		Distance = math.floor(ball.s),
		Zone = zone.Index,
		Radius = math.floor(ball.r * 10) / 10,
		Cash = paid,
		Eggs = eggsAdded,
		Record = record,
		Village = village,
		FirstVillage = firstVillage,
		Quality = run.packQuality,
		Bonks = run.bonks,
		Smashes = run.smashes,
		Full = run.fullBounces,
		-- The eggs still have to be carried home (EggRescueService): the client keeps this
		-- card until the rescue is over (Dev 2026-11-20).
		Rescue = S.EggRescueService ~= nil and #run.eggs > 0,
	}
	Net.fireAll("RunEnded", player.UserId, result)
	S.AnalyticsService:Funnel(player, "FirstRunEnded")
	S.AnalyticsService:Custom(
		player,
		"RunEnded",
		math.floor(ball.s),
		{ Zone = tostring(zone.Index), Pack = run.packQuality or "?", Eggs = tostring(#eggsAdded) }
	)
	S.StateService:Mark(player)
	-- Offers wait for the egg run to end (EggRescueService calls AfterRun then), so they
	-- never sit on top of it.
	if S.OfferService and not result.Rescue then
		S.OfferService:AfterRun(player, result)
	end
	task.delay(CRACK_SECONDS, function()
		if runs[player] == run then
			setPhase(player, run, "Idle")
			runs[player] = nil
			setFocus(player, nil)
			if S.EggRescueService and S.EggRescueService:Begin(player, ball.s, ball.x, run.eggs, run.lane, result) then
				return
			end
			if result.Rescue and S.OfferService then
				S.OfferService:AfterRun(player, result) -- no egg run after all
			end
			-- A few steps behind your pad: step forward onto it (or press ROLL) to go again.
			standAtDeck(player, run.lane, 9)
			setAnchored(player, false)
		end
	end)
end

-- Back to your lane, a few steps behind the pad (after the egg rescue).
function RollService:SendToDeck(player: Player, lane: number)
	standAtDeck(player, lane, 9)
	setAnchored(player, false)
end

---------------------------------------------------------------- Keep Rolling (near miss)
-- When the ball stops short of something it could reach with one more push, the roll
-- pauses in phase "Stopped" and the owner sees KEEP ROLLING? for Continue.Seconds
-- (ContinueController). Buying (ShopService -> RollService:Continue) pushes the ball on;
-- "no", the timer or leaving cracks it as usual.
local Rules = Economy.Continue

local function continueRuntime(player: Player)
	local session = S.DataService:GetSession(player)
	if not session then
		return nil
	end
	local rt = session.Runtime.Continue
	if not rt then
		rt = { declines = 0, rest = 0 }
		session.Runtime.Continue = rt
	end
	return rt
end

local function pushProduct(push: number)
	return Products.ProductByKey["KeepRolling" .. push]
end

local function buyable(def): boolean
	return def ~= nil and (def.Id ~= 0 or (Products.StudioTestBuys and RunService:IsStudio()))
end

local function extraFor(ball: Roll.Ball): number
	return math.max(Rules.MinStuds, ball.s * Rules.Share)
end

-- What one more push would reach, or nil when it's not worth offering.
local function nearMiss(player: Player, run: Run)
	local data = S.DataService:GetData(player)
	local ball = run.ball :: Roll.Ball
	if not data or not data.Flags.TutorialDone or ball.s >= endAt - 1 then
		return nil
	end
	if run.continues >= Rules.MaxPerRun then
		return nil
	end
	local def = pushProduct(run.continues + 1)
	if not buyable(def) then
		return nil
	end
	local rt = continueRuntime(player)
	if not rt then
		return nil
	end
	local session = S.DataService:GetSession(player)
	if run.continues == 0 and rt.rest > 0 and not (session and session.Runtime.ForceContinue) then
		rt.rest -= 1
		return nil
	end
	local reach = math.min(endAt, ball.s + extraFor(ball))
	local zone = Zones.at(ball.s)
	local nextZone = Zones.List[zone.Index + 1]
	local reachesZone = nextZone ~= nil and nextZone.Start > ball.s and nextZone.Start <= reach
	local beatsBest = data.BestDistance > ball.s and reach > data.BestDistance
	local forced = session ~= nil and session.Runtime.ForceContinue == true -- /keeprolling
	if not reachesZone and not beatsBest and not forced then
		return nil
	end
	return {
		def = def,
		reach = reach,
		nextZone = if reachesZone or (forced and not beatsBest) then nextZone else nil,
		best = data.BestDistance,
	}
end

local function stopForContinue(player: Player, run: Run, miss): ()
	local ball = run.ball :: Roll.Ball
	run.stopDeadline = os.clock() + Rules.Seconds
	setPhase(player, run, "Stopped")
	local zone = Zones.at(ball.s)
	Net.fire("RunStopped", player, {
		Distance = math.floor(ball.s),
		Seconds = Rules.Seconds,
		Product = miss.def.Key,
		Price = miss.def.Price,
		Push = run.continues + 1,
		Zone = zone.Index,
		NextZone = if miss.nextZone then miss.nextZone.Index else nil,
		ZoneStart = zone.Start,
		ToNext = if miss.nextZone then math.ceil(miss.nextZone.Start - ball.s) else nil,
		Reach = math.floor(miss.reach),
		Best = miss.best,
	})
	S.AnalyticsService:Custom(player, "KeepRolling", run.continues + 1, { Result = "Shown" })
end

-- The KEEP ROLLING? prompt is open: wait for Roblox's buy box instead of the timer.
function RollService:ContinueBuying(player: Player): boolean
	local run = runs[player]
	if not run or run.phase ~= "Stopped" then
		return false
	end
	run.stopDeadline = os.clock() + 120
	return true
end

function RollService:IsStopped(player: Player): boolean
	local run = runs[player]
	return run ~= nil and run.phase == "Stopped"
end

-- No thanks / buy box closed without buying: crack it now.
function RollService:ContinueDeclined(player: Player)
	local run = runs[player]
	if run and run.phase == "Stopped" then
		local rt = continueRuntime(player)
		if rt then
			rt.declines += 1
			if rt.declines >= Rules.DeclineStreak then
				rt.declines = 0
				rt.rest = Rules.RestRuns
			end
		end
		S.AnalyticsService:Custom(player, "KeepRolling", run.continues + 1, { Result = "Declined" })
		run.stopDeadline = 0
	end
end

-- A Keep Rolling purchase: push the ball on from where it stopped, with a fresh stretch of
-- snow, coins and eggs past the old pickups. Returns false when there is no stopped ball
-- (the grant then gives the push to the next roll as a Lucky Roll instead, ShopService).
function RollService:Continue(player: Player): boolean
	local run = runs[player]
	if not run or run.phase ~= "Stopped" or not run.ball then
		return false
	end
	local ball = run.ball :: Roll.Ball
	run.continues += 1
	local rt = continueRuntime(player)
	if rt then
		rt.declines = 0
	end
	ball.D = math.min(endAt, ball.s + extraFor(ball))
	ball.v = Roll.PushSpeed
	ball.done = false
	local from = math.max(run.limit, ball.s + 20)
	local limit = math.min(spline.Length, ball.D * 1.15 + Pickups.Margin)
	local seed = rng:NextInteger(1, 2 ^ 30)
	local idBase = 100_000 * run.continues
	if limit > from then
		for _, p in Pickups.generate(seed, limit, RollMath.widthAt, false, from, idBase) do
			table.insert(run.pickups, p)
		end
		run.limit = limit
	end
	setPhase(player, run, "Rolling")
	Net.fireAll("RunContinued", player.UserId, {
		S = ball.s,
		X = ball.x,
		D = ball.D,
		V = ball.v,
		Seed = seed,
		From = from,
		Limit = limit,
		IdBase = idBase,
	})
	S.AnalyticsService:Custom(player, "KeepRolling", run.continues, { Result = "Bought" })
	return true
end

-- Only the ROLL button starts a launch (Dev 2026-11-20: "don't make it start roll
-- automatically when we go near the launch zone"). BaseService's Teleport("Deck") puts you
-- on your lane pad and calls this.
function RollService:StartPack(player: Player): (boolean, string?)
	if S.TrainService and S.TrainService:IsTraining(player) then
		return false, nil
	end
	return startPack(player)
end

local function simulate(dt: number)
	for player, run in runs do
		if run.phase == "Packing" then
			-- The meter swings for up to MaxPackSeconds; no tap = a Weak pack.
			if Workspace:GetServerTimeNow() - run.packStart > RollMath.MaxPackSeconds + 0.5 then
				launch(player, run, "Weak")
			end
		elseif run.phase == "Rolling" and run.ball then
			Roll.step(run.ball, dt, spline, endAt)
			setFocus(player, spline:position(math.min(run.ball.s + 120, spline.Length), run.ball.x))
			checkHits(player, run)
			if run.ball.done then
				local miss = nearMiss(player, run)
				if miss then
					stopForContinue(player, run, miss)
				else
					finish(player, run)
				end
			end
		elseif run.phase == "Stopped" and os.clock() >= run.stopDeadline then
			finish(player, run)
		end
	end
end

-- Snapshot of every rolling ball: u8 count, then per ball f64 userId, f32 s, x, v, vx, r.
local BALL_BYTES = 28
local function snapshot()
	local list = {}
	for player, run in runs do
		if run.phase == "Rolling" and run.ball then
			table.insert(list, { player.UserId, run.ball })
		end
	end
	if #list == 0 then
		return
	end
	local buf = buffer.create(1 + #list * BALL_BYTES)
	buffer.writeu8(buf, 0, #list)
	for i, item in list do
		local o = 1 + (i - 1) * BALL_BYTES
		local ball = item[2]
		buffer.writef64(buf, o, item[1])
		buffer.writef32(buf, o + 8, ball.s)
		buffer.writef32(buf, o + 12, ball.x)
		buffer.writef32(buf, o + 16, ball.v)
		buffer.writef32(buf, o + 20, ball.vx)
		buffer.writef32(buf, o + 24, ball.r)
	end
	Net.fireAll("RunSnapshot", buf)
end

-- Admin / tests: set Power directly.
function RollService:SetPower(player: Player, power: number)
	local data = S.DataService:GetData(player)
	if data then
		data.Power = BigNum.from(power)
		S.StateService:Mark(player)
	end
end

function RollService:Init(services)
	S = services
	spline = Spline.main()
	endAt = math.min(Zones.VillageWall, spline.Length - 5)
	obstacles = Obstacles.layout(spline.Length, RollMath.widthAt, Zones.VillageWall - 40)
	table.sort(obstacles, function(a, b)
		return a.s < b.s
	end)
	Net.onInvoke("StartPack", startPack)
	Net.onInvoke("CancelPack", cancelPack)
	Net.onEvent("PackTap", onPackTap)
	Net.onEvent("Steer", onSteer)
	Net.onEvent("DeclineContinue", function(player)
		RollService:ContinueDeclined(player)
	end)
	S.DataService.ProfileReleasing:Connect(function(player)
		runs[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		setFocus(player, nil)
		runs[player] = nil
	end)
end

function RollService:Start()
	task.spawn(function()
		local last = os.clock()
		local snapAcc = 0
		while true do
			task.wait(1 / SIM_HZ)
			local now = os.clock()
			local dt = math.min(0.2, now - last)
			last = now
			simulate(dt)
			snapAcc += dt
			if snapAcc >= 1 / SNAP_HZ then
				snapAcc = 0
				snapshot()
			end
		end
	end)
end

return RollService
