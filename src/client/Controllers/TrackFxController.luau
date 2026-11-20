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

local function buildObstacles()
	obstacleList = Obstacles.layout(spline.Length, RollMath.widthAt, Zones.VillageWall - 40)
	for _, o in obstacleList do
		local kind = Obstacles.ById[o.Kind]
		local p = Instance.new("Part")
		p.Name = o.Kind
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Material = if kind.Id == "IceBlock" or kind.Id == "Crystal"
			then Enum.Material.Ice
			else Enum.Material.SmoothPlastic
		p.Color = kind.Color
		p.Size = Vector3.new(kind.Radius * 2, kind.Height, kind.Radius * 2)
		p.CFrame = spline:cframe(o.s, o.x) * CFrame.new(0, kind.Height / 2, 0)
		p.Parent = folder
		-- Size badge so players learn the SMASH rule.
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(60, 26)
		gui.StudsOffset = Vector3.new(0, kind.Height / 2 + 2, 0)
		gui.MaxDistance = 140
		local l = Ui.label({ Size = UDim2.fromScale(1, 1), Text = tostring(kind.SizeNeeded) })
		l.Parent = gui
		gui.Parent = p
		obstacleParts[o.Id] = p
	end
end

local function take(kind: string): BasePart
	local list = pool[kind]
	local p = list and table.remove(list)
	if p then
		return p
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
	local list = Pickups.generate(info.Seed, info.Limit, RollMath.widthAt, info.FirstEgg == true)
	for _, p in list do
		pickups[p.Id] = p
	end
	for _, part in obstacleParts do
		part.Transparency = 0
	end
end

function TrackFxController:EndRun()
	clearPickups()
end

-- Shows pickups near the ball, hides the ones behind (every frame, cheap: pooled).
function TrackFxController:Update(ball: Roll.Ball)
	for id, p in pickups do
		local near = p.s > ball.s - BEHIND and p.s < ball.s + AHEAD and not taken[id]
		local part = pickupParts[id]
		if near and not part then
			local np = take(p.Kind)
			local look = PICKUP_LOOK[p.Kind] or PICKUP_LOOK.Snow
			local base = spline:cframe(p.s, p.x)
			np.CFrame = if p.Kind == "Coin"
				then base * CFrame.new(0, 2.5, 0) * CFrame.Angles(0, math.rad(90), 0)
				else base * CFrame.new(0, look.Size.Y / 2, 0)
			np.Parent = folder
			pickupParts[id] = np
		elseif not near and part then
			give(p.Kind, part)
			pickupParts[id] = nil
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
		end
		Ui.sound("Smash")
		C.ResultsController:Flash("SMASH!", Ui.Colors.Green)
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
		Ui.sound("Smash", 0.6)
		C.ResultsController:Flash("BONK!", Ui.Colors.Red)
		local cam = Workspace.CurrentCamera
		if cam then
			cam.CFrame *= CFrame.Angles(0, 0, math.rad(4))
		end
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
			elseif p.Kind == "Coin" then
				Ui.sound("Coin", 1.3)
			end
		end
		if kind == "Egg" then
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
