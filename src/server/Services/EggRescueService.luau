--!strict
-- Egg rescue after a roll (Dev 2026-11-20, Throw Food For Animals' carry-home; rules in
-- Config/Rescue). RollService hands over the eggs the ball collected when it cracks:
--   * a snow pile at the crack site with the eggs frozen in it,
--   * a green flag uphill (farther rolls = a longer way),
--   * a yeti that sleeps in its den below the pile.
-- Walk into the pile: you grab the best egg left (two with the Carry 2 pass), held in your
-- arms (a "HeldEgg" model, so HoldPoseController poses the arms) and slower. The yeti
-- roars and chases you. Reach the flag: the egg goes in your bag and you're taken back to
-- the pile for the next one. Caught: you fall and the egg goes back to the pile. When the
-- pile is empty (or you LEAVE / time runs out / you sled home) you go back to the deck.
--
-- Everything is server side. Clients draw from Workspace.Rescue.<UserId> (a Folder):
--   attributes Owner, Phase ("Grab"|"Carry"), Left (eggs in the pile), Held (count),
--   YetiPos (Vector3), YetiState ("Den"|"Wake"|"Chase"|"Return"|"Stun"|"Asleep"),
--   YetiYaw (radians), FlagPos, PilePos, EndsAt (os.time()),
--   HeldList / PileList / SavedList (comma-separated rarities, for RescueEggsController's
--   egg strip: tap a held egg to drop it back, tap a pile egg to grab that one next)
--   children Pile (snow + egg models named Egg<i>), Flag.
-- and the owner gets RescueEvent (kind, data) for sounds and words (RescueController).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggLook = require(Shared.EggLook)
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)
local Rescue = require(Shared.Config.Rescue)
local Spline = require(Shared.Spline)
local ModelLoader = require(script.Parent.Parent.Lib.ModelLoader)

local EggRescueService = {}

local S: any

type Egg = { Rarity: string, Zone: string }
type State = {
	folder: Folder,
	pile: Model,
	lane: number,
	s: number,
	x: number,
	pileCf: CFrame,
	flagPos: Vector3,
	eggs: { Egg }, -- still in the pile
	held: { Egg },
	saved: { string },
	yetiPos: Vector3,
	denPos: Vector3,
	yeti: string,
	yetiTimer: number,
	knockedUntil: number,
	endsAt: number,
	busy: boolean, -- teleporting back to the pile
	grabAfter: number, -- os.clock(): no auto grab before this (just dropped an egg)
	result: any?, -- the run's result: offers wait for the rescue (OfferService:AfterRun)
}

local states: { [Player]: State } = {}
local root: Folder
local groundParams: RaycastParams

local function order(rarity: string): number
	local def = Eggs.ByName[rarity]
	return if def then def.Order else 1
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- The track surface under a point (the yeti walks on it).
local function ground(pos: Vector3): Vector3
	local hit = Workspace:Raycast(pos + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), groundParams)
	return if hit then hit.Position else pos
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function repelled(player: Player): boolean
	local data = S.DataService:GetData(player)
	return data ~= nil and (data.Flags.RepelUntil or 0) > os.time()
end

-- Sits on top of the snow pile so it's never buried (Dev 2026-11-20: "can't see what's
-- there to pick up"): rarity tag above it, a glow in the rarity colour, and an outline
-- that shows through the snow.
local function decorate(model: Model, rarity: string, top: boolean)
	local def = Eggs.ByName[rarity]
	local color = if def then def.Color else Color3.new(1, 1, 1)
	local _, size = model:GetBoundingBox()
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not anchor then
		return
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.fromOffset(150, 40)
	tag.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 1.6, 0)
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.MaxDistance = 260
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = string.upper(rarity)
	label.TextColor3 = if rarity == "Secret" then Color3.new(1, 1, 1) else color
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label
	label.Parent = tag
	tag.Adornee = anchor
	tag.Parent = model
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = if top then 14 else 9
	light.Brightness = 3
	light.Parent = anchor
	local outline = Instance.new("Highlight")
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.FillTransparency = 1
	outline.OutlineColor = color
	outline.OutlineTransparency = 0.1
	outline.Parent = model
end

-- The egg models on the pile match st.eggs (Egg1..EggN): the best one sits on the top,
-- the rest in a ring on the shoulders of the pile.
-- What the egg strip (RescueEggsController) shows: held, still in the pile, saved.
local function publish(st: State)
	local function list(eggs: { any }): string
		local names = {}
		for _, e in eggs do
			table.insert(names, if type(e) == "string" then e else e.Rarity)
		end
		return table.concat(names, ",")
	end
	st.folder:SetAttribute("HeldList", list(st.held))
	st.folder:SetAttribute("PileList", list(st.eggs))
	st.folder:SetAttribute("SavedList", list(st.saved))
end

local function drawPile(st: State)
	for _, c in st.pile:GetChildren() do
		if string.sub(c.Name, 1, 3) == "Egg" then
			c:Destroy()
		end
	end
	local n = #st.eggs
	for i, egg in st.eggs do
		local model = EggLook.make(egg.Rarity)
		model.Name = "Egg" .. i
		model:ScaleTo(model:GetScale() * 0.85)
		local cf
		if i == 1 then
			cf = st.pileCf * CFrame.new(0, 4.6, 0) * CFrame.Angles(0, math.rad(20), 0)
		else
			-- Ring facing the player first (they stand uphill = +Z of the pile frame).
			local a = math.pi / 2 + (i - 2) / math.max(n - 1, 1) * math.pi * 2
			cf = st.pileCf
				* CFrame.new(math.cos(a) * 3.1, 2.9, math.sin(a) * 3.1)
				* CFrame.Angles(math.rad(12), a, math.rad(8))
		end
		model:PivotTo(cf)
		decorate(model, egg.Rarity, i == 1)
		model.Parent = st.pile
	end
	st.folder:SetAttribute("Left", n)
	publish(st)
end

local function clearHeld(player: Player)
	local character = player.Character
	local m = character and character:FindFirstChild("HeldEgg")
	if m then
		m:Destroy()
	end
end

local function holdModels(player: Player, st: State)
	clearHeld(player)
	if #st.held == 0 then
		return
	end
	-- One model in the arms: the best egg held (two eggs: the second sits on top).
	local model = Instance.new("Model")
	for i, egg in st.held do
		local m = EggLook.make(egg.Rarity)
		m:PivotTo(CFrame.new(0, (i - 1) * EggLook.Height * 0.85, 0))
		for _, d in m:GetChildren() do
			d.Parent = model
		end
		m:Destroy()
	end
	S.CarryService:WeldModel(player, model, "HeldEgg")
end

local function setSpeed(player: Player, st: State?)
	local hum = humanoidOf(player)
	if hum then
		hum.WalkSpeed = if st and #st.held > 0 then Rescue.CarrySpeed else Rescue.WalkSpeed
	end
end

local function event(player: Player, kind: string, data: any?)
	Net.fire("RescueEvent", player, kind, data)
end

local function setPhase(player: Player, st: State)
	local phase = if #st.held > 0 then "Carry" else "Grab"
	st.folder:SetAttribute("Phase", phase)
	st.folder:SetAttribute("Held", #st.held)
	player:SetAttribute("Rescue", phase)
	setSpeed(player, st)
	publish(st)
end

-- Stands you just uphill of the pile, facing the flag.
local function toPile(player: Player, st: State)
	local character = player.Character
	if not character then
		return
	end
	local spline = Spline.main()
	local at = spline:position(math.max(0, st.s - 7), st.x) + Vector3.new(0, 4, 0)
	character:PivotTo(CFrame.lookAt(at, Vector3.new(st.flagPos.X, at.Y, st.flagPos.Z)))
	local r = rootOf(player)
	if r then
		r.Anchored = false
		r.AssemblyLinearVelocity = Vector3.zero
	end
end

local function finish(player: Player, reason: string)
	local st = states[player]
	if not st then
		return
	end
	states[player] = nil
	clearHeld(player)
	st.folder:Destroy()
	player:SetAttribute("Rescue", nil)
	setSpeed(player, nil)
	local hum = humanoidOf(player)
	if hum then
		hum.PlatformStand = false
	end
	if player.Parent then
		event(player, "Ended", { Reason = reason, Saved = st.saved, Lost = #st.eggs + #st.held })
		S.RollService:SendToDeck(player, st.lane)
		S.StateService:Mark(player)
		-- The result card shows now; any offer comes a little after it.
		if st.result and S.OfferService then
			task.delay(3, function()
				if player.Parent then
					S.OfferService:AfterRun(player, st.result)
				end
			end)
		end
	end
	S.AnalyticsService:Custom(
		player,
		"RescueEnded",
		#st.saved,
		{ Reason = reason, Lost = tostring(#st.eggs + #st.held) }
	)
end

local function bank(player: Player, st: State, eggs: { Egg }, source: string): { string }
	local got = {}
	for _, egg in eggs do
		if S.InventoryService:AddEgg(player, egg.Rarity, egg.Zone, source) then
			table.insert(got, egg.Rarity)
			table.insert(st.saved, egg.Rarity)
		end
	end
	return got
end

-- Called by RollService when the ball has cracked. Returns false when there is nothing
-- to rescue (RollService then sends you home as before).
function EggRescueService:Begin(
	player: Player,
	s: number,
	x: number,
	eggs: { Egg },
	lane: number,
	result: any?
): boolean
	if #eggs == 0 or states[player] or not player.Character then
		return false
	end
	-- Commons go straight to the bag; only the better eggs are carried (Rescue.CarryFrom).
	local carryFrom = order(Rescue.CarryFrom)
	local light, carry = {}, {}
	for _, egg in eggs do
		table.insert(if order(egg.Rarity) < carryFrom then light else carry, egg)
	end
	local autoSaved = {}
	for _, egg in light do
		if S.InventoryService:AddEgg(player, egg.Rarity, egg.Zone, "Roll") then
			table.insert(autoSaved, egg.Rarity)
		end
	end
	if #autoSaved > 0 then
		event(player, "AutoSaved", { Eggs = autoSaved, All = #carry == 0 })
	end
	if #carry == 0 then
		return false
	end
	eggs = carry
	S.CarryService:StopHolding(player)
	local spline = Spline.main()
	s = math.clamp(s, 20, spline.Length - 8)
	local width = spline:sample(s).Width
	x = math.clamp(x, -width / 2 + 8, width / 2 - 8)
	local pileCf = spline:cframe(s, x)
	local back = math.min(Rescue.BackMax, Rescue.BackMin + s * Rescue.BackPerStud)
	local flagS = math.max(4, s - back)
	local flagPos = spline:position(flagS, 0)
	local denPos = spline:position(math.min(spline.Length - 4, s + Rescue.YetiDen), x * 0.5)

	local folder = Instance.new("Folder")
	folder.Name = tostring(player.UserId)
	folder:SetAttribute("Owner", player.UserId)
	folder:SetAttribute("FlagPos", flagPos)
	folder:SetAttribute("PilePos", pileCf.Position)
	local pile = Instance.new("Model")
	pile.Name = "Pile"
	local snow = ModelLoader.clone("Pick_Snow", pileCf * CFrame.new(0, -0.6, 0), 3.2)
	if snow then
		for _, d in snow:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
			end
		end
		snow.Name = "Snow"
		snow.Parent = pile
	end
	pile.Parent = folder
	local flag = ModelLoader.clone("RescueFlag", CFrame.new(flagPos) * pileCf.Rotation, 1.5)
	if flag then
		for _, d in flag:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
			end
		end
		flag.Name = "Flag"
		flag.Parent = folder
	end

	-- Best eggs on top of the pile (grabbed first).
	local list = table.clone(eggs)
	table.sort(list, function(a, b)
		return order(a.Rarity) > order(b.Rarity)
	end)
	local data = S.DataService:GetData(player)
	local firstRuns = data and data.Stats.Runs <= Rescue.FirstRunsNoYeti
	local st: State = {
		folder = folder,
		pile = pile,
		lane = lane,
		s = s,
		x = x,
		pileCf = pileCf,
		flagPos = flagPos,
		eggs = list,
		held = {},
		saved = autoSaved,
		yetiPos = ground(denPos),
		denPos = ground(denPos),
		yeti = if firstRuns or repelled(player) then "Asleep" else "Den",
		yetiTimer = 0,
		knockedUntil = 0,
		endsAt = os.time() + Rescue.TimeLimit,
		busy = false,
		grabAfter = 0,
		result = result,
	}
	folder:SetAttribute("YetiPos", st.yetiPos)
	folder:SetAttribute("YetiState", st.yeti)
	folder:SetAttribute("EndsAt", st.endsAt)
	drawPile(st)
	folder.Parent = root
	states[player] = st
	setPhase(player, st)
	toPile(player, st)
	event(player, "Start", {
		Eggs = #list,
		Best = list[1].Rarity,
		Distance = math.floor(s - flagS),
		Yeti = st.yeti ~= "Asleep",
	})
	S.AnalyticsService:Custom(player, "RescueStarted", #list, { Best = list[1].Rarity })
	return true
end

local function grab(player: Player, st: State)
	local data = S.DataService:GetData(player)
	local count = if data and data.Gamepasses[Rescue.CarryTwoPass] then 2 else 1
	for _ = 1, count do
		local egg = table.remove(st.eggs, 1)
		if egg then
			table.insert(st.held, egg)
		end
	end
	drawPile(st)
	holdModels(player, st)
	setPhase(player, st)
	local best = st.held[1].Rarity
	event(player, "Grab", { Rarity = best, Count = #st.held })
	if st.yeti == "Den" then
		st.yeti = "Wake"
		st.yetiTimer = Rescue.YetiWake
		event(player, "Wake")
	end
end

local function deliver(player: Player, st: State)
	local got = bank(player, st, st.held, "Rescue")
	st.held = {}
	clearHeld(player)
	setPhase(player, st)
	event(player, "Saved", { Eggs = got, Left = #st.eggs })
	S.StateService:Mark(player)
	if #st.eggs == 0 then
		task.delay(0.8, function()
			if states[player] == st then
				finish(player, "Done")
			end
		end)
		return
	end
	-- Back down to the pile for the next egg (the client fades the screen).
	st.busy = true
	if st.yeti ~= "Asleep" then
		st.yeti = "Return"
	end
	task.delay(Rescue.BackSeconds, function()
		if states[player] == st then
			st.busy = false
			toPile(player, st)
		end
	end)
end

local function knock(player: Player, st: State, from: Vector3)
	local r = rootOf(player)
	local hum = humanoidOf(player)
	-- The eggs fall back into the pile (best first again).
	for _, egg in st.held do
		table.insert(st.eggs, egg)
	end
	table.sort(st.eggs, function(a, b)
		return order(a.Rarity) > order(b.Rarity)
	end)
	st.held = {}
	clearHeld(player)
	drawPile(st)
	setPhase(player, st)
	st.knockedUntil = os.clock() + Rescue.KnockSeconds
	st.yeti = "Stun"
	st.yetiTimer = Rescue.YetiStun
	if hum and r then
		hum.PlatformStand = true
		local away = flat(r.Position - from)
		away = if away.Magnitude > 0.1 then away.Unit else Vector3.zAxis
		r.AssemblyLinearVelocity = away * 38 + Vector3.new(0, 34, 0)
		r.AssemblyAngularVelocity = Vector3.new(away.Z, 0, -away.X) * 8
	end
	event(player, "Knocked", { From = from })
	S.AnalyticsService:Custom(player, "RescueKnocked", 1)
	-- Then straight back to the pile (with the client's fade), not a walk back down.
	st.busy = true
	task.delay(Rescue.KnockSeconds, function()
		local h = humanoidOf(player)
		if h then
			h.PlatformStand = false
			h:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		if states[player] ~= st then
			return
		end
		event(player, "Back")
		task.delay(Rescue.BackSeconds, function()
			if states[player] == st then
				st.busy = false
				toPile(player, st)
			end
		end)
	end)
end

local function stepYeti(player: Player, st: State, dt: number, playerPos: Vector3)
	local state = st.yeti
	if state == "Asleep" then
		return
	end
	if repelled(player) then
		st.yeti = "Asleep"
		st.folder:SetAttribute("YetiState", "Asleep")
		return
	end
	local target: Vector3? = nil
	local speed = Rescue.YetiSpeed
	if state == "Wake" or state == "Stun" then
		st.yetiTimer -= dt
		if st.yetiTimer <= 0 then
			st.yeti = if state == "Wake" then "Chase" else "Return"
		end
	elseif state == "Chase" then
		if #st.held == 0 then
			st.yeti = "Return"
		else
			local best = 1
			for _, egg in st.held do
				best = math.max(best, order(egg.Rarity))
			end
			speed = math.min(Rescue.YetiMax, Rescue.YetiSpeed + best * Rescue.YetiPerRarity)
			target = playerPos
			if os.clock() > st.knockedUntil and flat(playerPos - st.yetiPos).Magnitude < Rescue.CatchRadius then
				knock(player, st, st.yetiPos)
				target = nil
			end
		end
	elseif state == "Return" then
		target = st.denPos
		if flat(st.denPos - st.yetiPos).Magnitude < 2 then
			st.yeti = "Den"
			target = nil
		elseif #st.held > 0 and not st.busy then
			st.yeti = "Chase"
		end
	elseif state == "Den" and #st.held > 0 and not st.busy then
		st.yeti = "Wake"
		st.yetiTimer = Rescue.YetiWake * 0.5
		event(player, "Wake")
	end
	if target then
		local d = flat(target - st.yetiPos)
		local step = math.min(d.Magnitude, speed * dt)
		if d.Magnitude > 0.05 then
			local dir = d.Unit
			st.yetiPos = ground(st.yetiPos + dir * step)
			st.folder:SetAttribute("YetiYaw", math.atan2(-dir.X, -dir.Z))
		end
	elseif st.yeti ~= "Den" then
		-- Face the player while roaring / celebrating.
		local d = flat(playerPos - st.yetiPos)
		if d.Magnitude > 0.1 then
			st.folder:SetAttribute("YetiYaw", math.atan2(-d.X, -d.Z))
		end
	end
	st.folder:SetAttribute("YetiPos", st.yetiPos)
	st.folder:SetAttribute("YetiState", st.yeti)
end

local function step(dt: number)
	for player, st in states do
		local r = rootOf(player)
		local hum = humanoidOf(player)
		if not r or not hum or hum.Health <= 0 then
			finish(player, "Died")
			continue
		end
		if os.time() >= st.endsAt then
			finish(player, "Time")
			continue
		end
		local p = r.Position
		if not st.busy and os.clock() > st.knockedUntil then
			if
				#st.held == 0
				and #st.eggs > 0
				and os.clock() > st.grabAfter
				and (p - st.pileCf.Position).Magnitude < Rescue.GrabRadius
			then
				grab(player, st)
			elseif #st.held > 0 and flat(p - st.flagPos).Magnitude < Rescue.FlagRadius then
				deliver(player, st)
			end
		end
		if states[player] == st then
			stepYeti(player, st, dt, p)
		end
	end
end

-------------------------------------------------------------------------- Robux

function EggRescueService:IsRescuing(player: Player): boolean
	return states[player] ~= nil
end

function EggRescueService:CanSled(player: Player): boolean
	local st = states[player]
	return st ~= nil and (#st.eggs + #st.held) > 0
end

-- Sled Home: every egg still in the pile or in your arms goes in your bag now.
function EggRescueService:SledHome(player: Player): boolean
	local st = states[player]
	if not st or (#st.eggs + #st.held) == 0 then
		return false
	end
	local all = table.clone(st.held)
	for _, egg in st.eggs do
		table.insert(all, egg)
	end
	st.held = {}
	st.eggs = {}
	clearHeld(player)
	drawPile(st)
	local got = bank(player, st, all, "SledHome")
	event(player, "Sled", { Eggs = got })
	S.StateService:Mark(player)
	task.delay(2.2, function()
		if states[player] == st then
			finish(player, "Sled")
		end
	end)
	return true
end

function EggRescueService:Repel(player: Player)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	data.Flags.RepelUntil = math.max(os.time(), data.Flags.RepelUntil or 0) + Rescue.RepelMinutes * 60
	local st = states[player]
	if st then
		st.yeti = "Asleep"
		st.folder:SetAttribute("YetiState", "Asleep")
	end
	event(player, "Repelled", { Until = data.Flags.RepelUntil })
	S.StateService:Mark(player)
end

function EggRescueService:Init(services)
	S = services
	root = Instance.new("Folder")
	root.Name = "Rescue"
	root.Parent = Workspace
	groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Include
	task.spawn(function()
		local mountain = Workspace:WaitForChild("Mountain")
		groundParams.FilterDescendantsInstances = { mountain:WaitForChild("Track") }
	end)
	Net.onInvoke("Rescue", function(player, action, arg)
		if action == "Leave" then
			if states[player] then
				finish(player, "Left")
				return true, nil
			end
		elseif action == "Drop" then
			-- Put a held egg back on the pile (last in line), e.g. to go for a better one.
			local st = states[player]
			local i = tonumber(arg)
			if st and not st.busy and i and st.held[i] then
				local egg = table.remove(st.held, i)
				table.insert(st.eggs, egg)
				st.grabAfter = os.clock() + 2
				drawPile(st)
				holdModels(player, st)
				setPhase(player, st)
				event(player, "Dropped", { Rarity = egg.Rarity })
				return true, nil
			end
		elseif action == "Pick" then
			-- Choose which pile egg you grab next (it goes to the top of the pile).
			local st = states[player]
			local i = tonumber(arg)
			if st and i and st.eggs[i] then
				local egg = table.remove(st.eggs, i)
				table.insert(st.eggs, 1, egg)
				drawPile(st)
				return true, nil
			end
		elseif action == "Sled" then
			return S.ShopService:Prompt(player, "SledHome")
		elseif action == "Repel" then
			return S.ShopService:Prompt(player, "YetiRepellent")
		end
		return false, nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		local st = states[player]
		if st then
			states[player] = nil
			st.folder:Destroy()
		end
	end)
end

function EggRescueService:Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			step(acc)
			acc = 0
		end
	end)
end

return EggRescueService
