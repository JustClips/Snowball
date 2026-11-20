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
local Net = require(Shared.Net)
local Obstacles = require(Shared.Config.Obstacles)
local Pickups = require(Shared.Config.Pickups)
local PowerCurve = require(Shared.PowerCurve)
local Roll = require(Shared.Roll)
local RollMath = require(Shared.RollMath)
local Spline = require(Shared.Spline)
local Upgrades = require(Shared.Config.Upgrades)
local World = require(Shared.Config.World)
local Zones = require(Shared.Config.Zones)

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
	startedAt: number,
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

local function standAtDeck(player: Player, lane: number)
	local root = rootOf(player)
	local character = player.Character
	if root and character then
		local pos = World.DeckStand + Vector3.new(World.laneX(lane), 0, 0)
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
	}
	runs[player] = run
	setPhase(player, run, "Packing")
	standAtDeck(player, run.lane)
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
	-- Per-roll charges: Super Lucky (x100 luck), Lucky Roll (x10 luck, +50% distance),
	-- Luck Pop (x3 luck), Golden Snowball rentals.
	local luck = S.BoostService:GetLuck(player)
	if data.Charges.SuperLucky > 0 then
		data.Charges.SuperLucky -= 1
		luck *= 100
	elseif data.Charges.LuckyRoll > 0 then
		data.Charges.LuckyRoll -= 1
		luck *= 10
		run.lucky = true
	end
	if (data.Charges.LuckPop or 0) > 0 then
		data.Charges.LuckPop -= 1
		luck *= 3
	end
	run.golden = data.Gamepasses.GoldenSnowball == true
	if not run.golden and data.Charges.GoldenRuns > 0 then
		data.Charges.GoldenRuns -= 1
		run.golden = true
	end
	run.luck = luck
	local D = PowerCurve.distance(data.Power) * (PowerCurve.PackMult[quality] or 0.7)
	if run.lucky then
		D *= 1.5
	end
	local core = Upgrades.Cores[data.Core] or Upgrades.Cores[1]
	local x = World.laneX(run.lane)
	run.ball = Roll.new(x, D, core.Growth)
	local firstEgg = data.Stats.Runs == 0 and data.Stats.EggsFound == 0
	local limit = math.min(spline.Length, D * 1.15 + Pickups.Margin)
	run.pickups = Pickups.generate(run.seed, limit, RollMath.widthAt, firstEgg)
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
	local eggsAdded = {}
	for _, egg in run.eggs do
		local uid = S.InventoryService:AddEgg(player, egg.Rarity, egg.Zone, "Run")
		if uid then
			table.insert(eggsAdded, egg.Rarity)
		end
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
	if S.OfferService then
		S.OfferService:AfterRun(player, result)
	end
	task.delay(CRACK_SECONDS, function()
		if runs[player] == run then
			setPhase(player, run, "Idle")
			runs[player] = nil
			standAtDeck(player, run.lane)
			setAnchored(player, false)
		end
	end)
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
			checkHits(player, run)
			if run.ball.done then
				finish(player, run)
			end
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
	S.DataService.ProfileReleasing:Connect(function(player)
		runs[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
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
