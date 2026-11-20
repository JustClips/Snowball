--!strict
-- What's on the track for you (GAME_PLAN §5.5): the fixed obstacles (graybox until the
-- Blender obstacle models are uploaded; ones your ball smashed hide for you only) and your
-- run's pickups, rebuilt from the run seed exactly like the server does. Pooled parts,
-- only the stretch near your ball is shown.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)
local Obstacles = require(Shared.Config.Obstacles)
local Pickups = require(Shared.Config.Pickups)
local Roll = require(Shared.Roll)
local RollMath = require(Shared.RollMath)
local Spline = require(Shared.Spline)
local Zones = require(Shared.Config.Zones)
local Fx = require(script.Parent.Parent.Fx)
local Ui = require(script.Parent.Parent.Ui)

local TrackFxController = {}

local C: any
local spline: Spline.Spline
local folder: Folder
local obstacleParts: { [number]: BasePart } = {}
local obstacleList: { Obstacles.Obstacle } = {}
local pickups: { Pickups.Pickup } = {}
local pickupParts: { [number]: BasePart } = {}
local taken: { [number]: boolean } = {}
local pool: { [string]: { BasePart } } = {}
local combo = 0
local lastSmash = 0
local AHEAD = 520
local BEHIND = 40

local PICKUP_LOOK: { [string]: { Size: Vector3, Color: Color3, Shape: Enum.PartType, Material: Enum.Material } } = {
	Snow = {
		Size = Vector3.new(6, 2.5, 6),
		Color = Color3.fromRGB(250, 252, 255),
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Snow,
	},
	Coin = {
		Size = Vector3.new(0.6, 3, 3),
		Color = Color3.fromRGB(255, 205, 50),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
	},
	Egg = {
		Size = Vector3.new(3, 4, 3),
		Color = Color3.fromRGB(170, 230, 255),
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Glass,
	},
	Present = {
		Size = Vector3.new(3, 3, 3),
		Color = Color3.fromRGB(235, 60, 70),
		Shape = Enum.PartType.Block,
		Material = Enum.Material.SmoothPlastic,
	},
	Ramp = {
		Size = Vector3.new(14, 1, 10),
		Color = Color3.fromRGB(110, 200, 255),
		Shape = Enum.PartType.Block,
		Material = Enum.Material.Ice,
	},
}

-- The Blender model for a track thing (art/blender/track.py), shared by the server in
-- ReplicatedStorage.Assets. Its CFrame there is its offset from the model origin.
local function asset(name: string, wait: number?): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets and wait then
		assets = ReplicatedStorage:WaitForChild("Assets", wait)
	end
	if not assets then
		return nil
	end
	local found = if wait then assets:WaitForChild(name, wait) else assets:FindFirstChild(name)
	return if found and found:IsA("BasePart") then found else nil
end

local badges: { [number]: { gui: BillboardGui, label: TextLabel, s: number, need: number } } = {}
local badgeAcc = 0

local function hideBadges()
	for _, b in badges do
		b.gui.Enabled = false
	end
end

local function buildObstacles()
	obstacleList = Obstacles.layout(spline.Length, RollMath.widthAt, Zones.VillageWall - 40)
	for _, o in obstacleList do
		local kind = Obstacles.ById[o.Kind]
		local template = asset("Obs_" .. kind.Id, 30)
		local p: BasePart
		if template then
			p = template:Clone()
			p.CFrame = spline:cframe(o.s, o.x) * template.CFrame
		else
			local np = Instance.new("Part")
			np.Material = Enum.Material.SmoothPlastic
			np.Size = Vector3.new(kind.Radius * 2, kind.Height, kind.Radius * 2)
			np.CFrame = spline:cframe(o.s, o.x) * CFrame.new(0, kind.Height / 2, 0)
			p = np
		end
		p.Name = o.Kind
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Color = kind.Color -- debris colour when smashed
		p.Parent = folder
		-- Size badge so players learn the SMASH rule: only while your own ball rolls and
		-- only on obstacles just ahead of it (Dev 2026-11-20: random numbers floated over
		-- the track). Green SMASH! = big enough, red number = the size you need.
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(84, 30)
		gui.StudsOffsetWorldSpace = Vector3.new(0, p.Size.Y / 2 + 2, 0)
		gui.MaxDistance = 160
		gui.Enabled = false
		local l = Ui.label({ Name = "Text", Size = UDim2.fromScale(1, 1), Text = tostring(kind.SizeNeeded) })
		l.Parent = gui
		gui.Parent = p
		badges[o.Id] = { gui = gui, label = l, s = o.s, need = kind.SizeNeeded }
		obstacleParts[o.Id] = p
	end
end

local function take(kind: string): BasePart
	local list = pool[kind]
	local p = list and table.remove(list)
	if p then
		return p
	end
	local template = asset("Pick_" .. kind)
	if template then
		local clone = template:Clone()
		clone.Name = kind
		return clone
	end
	local look = PICKUP_LOOK[kind] or PICKUP_LOOK.Snow
	local np = Instance.new("Part")
	np.Name = kind
	np.Anchored = true
	np.CanCollide = false
	np.CanQuery = false
	np.CanTouch = false
	np.Shape = look.Shape
	np.Size = look.Size
	np.Color = look.Color
	np.Material = look.Material
	return np
end

local function give(kind: string, p: BasePart)
	p.Parent = nil
	pool[kind] = pool[kind] or {}
	table.insert(pool[kind], p)
end

local function clearPickups()
	for id, p in pickupParts do
		local pk = pickups[id]
		give(if pk then pk.Kind else p.Name, p)
	end
	pickupParts = {}
	pickups = {}
	taken = {}
end

function TrackFxController:BeginRun(info)
	clearPickups()
	combo = 0
	local list = Pickups.generate(info.Seed, info.Limit, RollMath.widthAt, info.FirstEgg == true)
	for _, p in list do
		pickups[p.Id] = p
	end
	for _, part in obstacleParts do
		part.Transparency = 0
	end
end

-- A Keep Rolling push: the new stretch's pickups, made from its own seed like the server.
function TrackFxController:AddPickups(info)
	if type(info.Seed) ~= "number" or type(info.Limit) ~= "number" or info.Limit <= (info.From or 0) then
		return
	end
	local list = Pickups.generate(info.Seed, info.Limit, RollMath.widthAt, false, info.From, info.IdBase)
	for _, p in list do
		pickups[p.Id] = p
	end
end

function TrackFxController:EndRun()
	clearPickups()
	hideBadges()
end

-- Shows pickups near the ball, hides the ones behind (every frame, cheap: pooled).
function TrackFxController:Update(ball: Roll.Ball)
	badgeAcc += 1
	if badgeAcc >= 6 then
		badgeAcc = 0
		for _, b in badges do
			local on = b.s > ball.s and b.s < ball.s + 110
			b.gui.Enabled = on
			if on then
				local can = ball.r >= b.need
				b.label.Text = if can then "SMASH!" else tostring(b.need)
				b.label.TextColor3 = if can then Color3.fromRGB(110, 235, 90) else Color3.fromRGB(255, 90, 90)
			end
		end
	end
	for id, p in pickups do
		local near = p.s > ball.s - BEHIND and p.s < ball.s + AHEAD and not taken[id]
		local part = pickupParts[id]
		if near and not part then
			local np = take(p.Kind)
			local look = PICKUP_LOOK[p.Kind] or PICKUP_LOOK.Snow
			local base = spline:cframe(p.s, p.x)
			local template = asset("Pick_" .. p.Kind)
			np.CFrame = if template
				then base * template.CFrame
				elseif p.Kind == "Coin" then base * CFrame.new(0, 2.5, 0) * CFrame.Angles(0, math.rad(90), 0)
				else base * CFrame.new(0, look.Size.Y / 2, 0)
			np.Parent = folder
			pickupParts[id] = np
		elseif not near and part then
			give(p.Kind, part)
			pickupParts[id] = nil
		elseif part and (p.Kind == "Coin" or p.Kind == "Egg" or p.Kind == "Present") then
			-- Coins spin, eggs and presents bob: things to grab read as alive.
			local t = os.clock() + id
			local base = spline:cframe(p.s, p.x)
			local template = asset("Pick_" .. p.Kind)
			local offset = if template then template.CFrame else CFrame.new(0, 2.5, 0)
			if p.Kind == "Coin" then
				part.CFrame = base * CFrame.new(0, 0.6 + math.sin(t * 3) * 0.4, 0) * CFrame.Angles(0, t * 4, 0) * offset
			else
				part.CFrame = base * CFrame.new(0, 0.5 + math.abs(math.sin(t * 2.5)) * 1.2, 0) * offset
			end
		end
	end
end

local function onEvent(kind: string, payload: any)
	local ball = C.BallController:LocalBall()
	if kind == "Smash" then
		local part = obstacleParts[payload]
		if part then
			part.Transparency = 1
			C.BallController:Debris(part.Position, 3, part.Color, 10)
		end
		if ball then
			Roll.smash(ball)
			if part then
				C.BallController:Stick("Obs_" .. part.Name, math.max(1.5, ball.r * 0.55))
			end
		end
		Ui.sound("SnowHit")
		if part then
			Fx.burst("Puff", part.Position, 1.6)
			Fx.burst("Flakes", part.Position, 1.2)
		end
		-- Combo: smashes close together count up, louder and shakier each time.
		local now = os.clock()
		combo = if now - lastSmash < 3 then combo + 1 else 1
		lastSmash = now
		Ui.sound("Smash", 1 + math.min(combo - 1, 8) * 0.07)
		C.BallController:Shake(0.7 + math.min(combo, 6) * 0.2)
		C.ResultsController:Flash(
			if combo > 1 then `SMASH! x{combo}` else "SMASH!",
			if combo >= 5 then Color3.fromRGB(255, 120, 220) elseif combo >= 3 then Ui.Colors.Gold else Ui.Colors.Green
		)
	elseif kind == "Bonk" then
		if ball then
			local o = nil
			for _, ob in obstacleList do
				if ob.Id == payload then
					o = ob
					break
				end
			end
			Roll.bonk(ball, if o then ball.x - o.x else 1)
		end
		Ui.sound("SnowHit", 0.8)
		combo = 0
		C.ResultsController:Flash("BONK!", Ui.Colors.Red)
		C.BallController:Shake(1.6)
	elseif kind == "Pickup" or kind == "Egg" then
		local id = if kind == "Egg" then payload.Id else payload
		taken[id] = true
		local p = pickups[id]
		local part = pickupParts[id]
		if part and p then
			local tween = TweenService:Create(part, TweenInfo.new(0.2), { Transparency = 1 })
			tween:Play()
			tween.Completed:Once(function()
				part.Transparency = 0
				if pickupParts[id] == part then
					pickupParts[id] = nil
					give(p.Kind, part)
				end
			end)
		end
		if ball and p then
			if p.Kind == "Snow" then
				Roll.addSnow(ball, Pickups.snowAt(p.s))
			elseif p.Kind == "Ramp" then
				Roll.ramp(ball)
				C.BallController:Jump()
				C.ResultsController:Flash("JUMP!", Ui.Colors.Blue)
				Ui.sound("Launch", 1.2)
			elseif p.Kind == "Coin" then
				Ui.sound("Coin", 1.3)
				C.BallController:Stick("Pick_Coin", 1.4)
			elseif p.Kind == "Present" then
				C.BallController:Stick("Pick_Present", 1.8)
			end
		end
		if kind == "Egg" then
			Ui.sound("Egg")
			if part then
				Fx.burst("Sparkle", part.Position, 1.5)
			end
			local def = Eggs.ByName[payload.Rarity]
			C.ResultsController:Flash(`{string.upper(payload.Rarity)} EGG!`, if def then def.Color else Ui.Colors.Snow)
		end
	elseif kind == "Full" then
		taken[payload] = true
		C.ResultsController:Flash("BALL FULL!", Ui.Colors.Red)
	elseif kind == "Zone" then
		local zone = Zones.List[payload]
		if zone then
			C.ResultsController:Flash(string.upper(zone.Name) .. "!", zone.Color)
		end
	end
end

function TrackFxController:Init(controllers)
	C = controllers
	spline = Spline.main()
	folder = Instance.new("Folder")
	folder.Name = "TrackFx"
	folder.Parent = Workspace
end

function TrackFxController:Start()
	task.spawn(buildObstacles)
	Net.event("RunEvent").OnClientEvent:Connect(onEvent)
end

return TrackFxController
