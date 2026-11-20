--!strict
-- Draws every rolling ball (GAME_PLAN §5.5). Your own ball is predicted locally with the
-- shared Roll math (so steering answers right away) and eased toward the server's 10 Hz
-- snapshots; other players' balls are ghosts extrapolated from their snapshots. Also runs
-- the roll camera and the crack.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Roll = require(Shared.Roll)
local Spline = require(Shared.Spline)
local Zones = require(Shared.Config.Zones)
local Fx = require(script.Parent.Parent.Fx)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local BallController = {}

local C: any
local spline: Spline.Spline
local endAt = 0
local folder: Folder

type Snap = { s: number, x: number, v: number, vx: number, r: number, at: number }
type Drawn = {
	part: BasePart,
	ball: Roll.Ball,
	snap: Snap?,
	isLocal: boolean,
	spin: CFrame,
	golden: boolean,
	stopped: boolean?, -- KEEP ROLLING? is up: hold still until it's bought or cracks
}
local balls: { [number]: Drawn } = {}
local cameraBall: Drawn? = nil

-- Juice for your own roll (Dev 2026-11-20: "rolling is hella boring"): screen shake, a
-- speed FOV, speed lines at the screen edges, a snow spray behind the ball, a bouncy
-- "grow" pop when it picks up snow and a real hop off ramps.
local BASE_FOV = 70
local JUMP_TIME = 1.1
local shake = 0
local jumpAt = -10
local jumpHeight = 0
local landed = true
local pop = 0
local lastR = 0
local spray: Part? = nil
local sprayEmitter: ParticleEmitter? = nil
local lines: { Frame } = {}
local linesGui: ScreenGui? = nil

-- Things you roll over stick to your ball (coins, presents, bits of what you smashed),
-- so the ball visibly changes as the run goes on. Each piece keeps a spot on the ball's
-- surface and turns with it.
type Stuck = { part: BasePart, dir: Vector3, rot: CFrame }
local stuck: { Stuck } = {}
local MAX_STUCK = 28

function BallController:Stick(templateName: string, size: number)
	local cb = cameraBall
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild(templateName)
	if not cb or not template or not template:IsA("BasePart") then
		return
	end
	local part = template:Clone()
	local big = math.max(part.Size.X, part.Size.Y, part.Size.Z)
	part.Size = part.Size * (size / big)
	part.CastShadow = false
	part.Parent = folder
	-- Somewhere on the front/top/sides (where the camera can see it).
	local dir = Vector3.new(math.random() * 2 - 1, math.random() * 1.4 - 0.4, math.random() * 2 - 1).Unit
	table.insert(stuck, {
		part = part,
		dir = cb.spin:Inverse() * dir,
		rot = CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28),
	})
	if #stuck > MAX_STUCK then
		local old = table.remove(stuck, 1)
		if old then
			old.part:Destroy()
		end
	end
end

local function clearStuck()
	for _, s in stuck do
		s.part:Destroy()
	end
	stuck = {}
end

function BallController:Shake(amount: number)
	shake = math.max(shake, amount)
end

function BallController:Jump()
	local cb = cameraBall
	jumpAt = os.clock()
	jumpHeight = 7 + (if cb then cb.ball.r * 1.2 else 0)
	landed = false
end

local function makeSpray()
	if spray then
		return
	end
	local p = Instance.new("Part")
	p.Name = "Spray"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	local e = Instance.new("ParticleEmitter")
	e.Texture = Ui.Images.Fx_SnowPuff or ""
	e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	e.Lifetime = NumberRange.new(0.5, 0.8)
	e.Speed = NumberRange.new(8, 16)
	e.SpreadAngle = Vector2.new(35, 20)
	e.Drag = 3
	e.Acceleration = Vector3.new(0, -10, 0)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Rotation = NumberRange.new(0, 360)
	e.LightEmission = 0.1
	e.Rate = 0
	e.EmissionDirection = Enum.NormalId.Front
	e.Parent = p
	p.Parent = folder
	spray = p
	sprayEmitter = e
end

local function makeLines()
	if linesGui then
		return
	end
	local gui = Ui.screen("SpeedLines", 2)
	for k = 1, 18 do
		local f = Instance.new("Frame")
		f.Name = "Line" .. k
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundTransparency = 1
		f.Parent = gui
		lines[k] = f
	end
	linesGui = gui
end

-- Speed lines: thin white streaks around the edges, more and brighter the faster you go.
local function drawLines(speed01: number)
	makeLines()
	local cam = Workspace.CurrentCamera
	local vs = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	for k, f in lines do
		local on = speed01 > 0.35 and math.random() < speed01
		if not on then
			f.BackgroundTransparency = 1
		else
			local a = (k / #lines) * math.pi * 2 + math.random() * 0.3
			local dir = Vector2.new(math.cos(a), math.sin(a))
			local r = 0.42 + math.random() * 0.12
			local pos = vs / 2 + Vector2.new(dir.X * vs.X * r, dir.Y * vs.Y * r)
			local len = 60 + speed01 * 160 * math.random()
			f.Position = UDim2.fromOffset(pos.X, pos.Y)
			f.Size = UDim2.fromOffset(len, 3)
			f.Rotation = math.deg(a)
			f.BackgroundTransparency = 1 - 0.55 * speed01
		end
	end
end

local function hideJuice()
	shake = 0
	pop = 0
	jumpAt = -10
	landed = true
	if sprayEmitter then
		sprayEmitter.Rate = 0
	end
	for _, f in lines do
		f.BackgroundTransparency = 1
	end
	local cam = Workspace.CurrentCamera
	if cam then
		cam.FieldOfView = BASE_FOV
	end
end
local debrisPool: { BasePart } = {}

local SNOW = Color3.fromRGB(245, 249, 255)
local GOLD = Color3.fromRGB(255, 205, 60)

local function makePart(golden: boolean): BasePart
	local p = Instance.new("Part")
	p.Name = "Snowball"
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Material = if golden then Enum.Material.Foil else Enum.Material.Snow
	p.Color = if golden then GOLD else SNOW
	p.Size = Vector3.one * 4
	p.Parent = folder
	return p
end

local function onStarted(userId: number, info)
	local old = balls[userId]
	if old then
		old.part:Destroy()
	end
	local isLocal = userId == player.UserId
	local d: Drawn = {
		part = makePart(info.Golden == true),
		ball = Roll.new(info.X, info.D, info.Growth),
		snap = nil,
		isLocal = isLocal,
		spin = CFrame.identity,
		golden = info.Golden == true,
	}
	balls[userId] = d
	if isLocal then
		cameraBall = d
		C.SteerController:SetActive(true)
		C.TrackFxController:BeginRun(info)
		C.HudController:ShowZoneBar(true, info)
		hideJuice()
		clearStuck()
		makeSpray()
		lastR = 0
		BallController:Shake(1.2)
		Ui.sound("Launch")
		Ui.loop("Roll", true)
		local cam = Workspace.CurrentCamera
		if cam then
			cam.CameraType = Enum.CameraType.Scriptable
		end
	end
end

local function onSnapshot(buf: buffer)
	local count = buffer.readu8(buf, 0)
	local now = os.clock()
	for i = 1, count do
		local o = 1 + (i - 1) * 28
		local userId = buffer.readf64(buf, o)
		local d = balls[userId]
		if d then
			d.snap = {
				s = buffer.readf32(buf, o + 8),
				x = buffer.readf32(buf, o + 12),
				v = buffer.readf32(buf, o + 16),
				vx = buffer.readf32(buf, o + 20),
				r = buffer.readf32(buf, o + 24),
				at = now,
			}
		end
	end
end

local function debris(at: Vector3, radius: number, color: Color3, count: number)
	for _ = 1, count do
		local p = table.remove(debrisPool)
		if not p then
			local np = Instance.new("Part")
			np.Anchored = true
			np.CanCollide = false
			np.CanQuery = false
			np.CanTouch = false
			np.Material = Enum.Material.Snow
			p = np
		end
		local piece = p :: BasePart
		local size = math.max(0.6, radius * (0.25 + math.random() * 0.25))
		piece.Size = Vector3.one * size
		piece.Color = color
		piece.Transparency = 0
		piece.CFrame =
			CFrame.new(at + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * radius)
		piece.Parent = folder
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.3, math.random() - 0.5).Unit
		TweenService:Create(piece, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = piece.CFrame + dir * (radius * 2 + 8),
			Transparency = 1,
			Size = piece.Size * 0.4,
		}):Play()
		task.delay(0.95, function()
			piece.Parent = nil
			table.insert(debrisPool, piece)
		end)
	end
end

function BallController:Debris(at: Vector3, radius: number, color: Color3, count: number)
	debris(at, radius, color, count)
end

-- The local ball's world position (for FX), or nil.
function BallController:LocalBall(): Roll.Ball?
	return if cameraBall then cameraBall.ball else nil
end

local function onEnded(userId: number, result)
	local d = balls[userId]
	if not d then
		return
	end
	balls[userId] = nil
	if result and result.Distance then
		d.ball.s = result.Distance
	end
	local pos = d.part.Position
	debris(pos, d.ball.r, if d.golden then GOLD else SNOW, if d.isLocal then 18 else 8)
	d.part:Destroy()
	if d.isLocal then
		Ui.loop("Roll", false)
		Fx.burst("Shatter", pos, math.clamp(d.ball.r / 3, 1, 4))
		Ui.sound("Crack")
		Ui.sound("Shatter")
		C.SteerController:SetActive(false)
		hideJuice()
		BallController:Shake(2)
		-- The stuck bits fly off with the crack.
		for _, st in stuck do
			local p = st.part
			local dir = (p.Position - pos).Unit + Vector3.yAxis
			TweenService:Create(p, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
				CFrame = p.CFrame + dir * 12,
				Transparency = 1,
			}):Play()
		end
		local flying = stuck
		stuck = {}
		task.delay(0.9, function()
			for _, st in flying do
				st.part:Destroy()
			end
		end)
		C.TrackFxController:EndRun()
		C.ResultsController:Show(result)
		task.delay(1.6, function()
			if cameraBall == d then
				cameraBall = nil
				C.HudController:ShowZoneBar(false)
				local cam = Workspace.CurrentCamera
				if cam then
					cam.CameraType = Enum.CameraType.Custom
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					if humanoid then
						cam.CameraSubject = humanoid
					end
				end
			end
		end)
	end
end

-- Your ball stopped short and KEEP ROLLING? is up (RollService "Stopped").
local function onStopped(info)
	local d = balls[player.UserId]
	if not d then
		return
	end
	d.stopped = true
	d.snap = nil
	d.ball.v = 0
	d.ball.vx = 0
	d.ball.s = info.Distance or d.ball.s
	Ui.loop("Roll", false)
end

-- A Keep Rolling push (anyone's ball): it rolls on from where it stopped.
local function onContinued(userId: number, info)
	local d = balls[userId]
	if not d then
		return
	end
	d.stopped = false
	d.snap = nil
	local ball = d.ball
	ball.s = info.S
	ball.x = info.X
	ball.D = info.D
	ball.v = info.V
	ball.done = false
	if d.isLocal then
		C.TrackFxController:AddPickups(info)
		Ui.sound("Launch")
		Ui.loop("Roll", true)
		Fx.burst("Ring", d.part.Position, math.clamp(ball.r / 3, 1, 4))
		C.ResultsController:Flash("KEEP ROLLING!", Color3.fromRGB(110, 235, 90))
	end
end

local function step(dt: number)
	local now = os.clock()
	for _, d in balls do
		local ball = d.ball
		local snap = d.snap
		if d.stopped then
			-- hold still (KEEP ROLLING? is up)
			ball.v = 0
		elseif d.isLocal then
			ball.steer = C.SteerController.Value
			Roll.step(ball, dt, spline, endAt)
			ball.done = false
			if snap then
				-- Server snapshot moved on since it was sent: extrapolate, then ease toward it.
				local age = now - snap.at
				local ts = snap.s + snap.v * age
				local tx = snap.x + snap.vx * age
				ball.s += (ts - ball.s) * math.min(1, dt * 6)
				ball.x += (tx - ball.x) * math.min(1, dt * 2.5)
				ball.v += (snap.v - ball.v) * math.min(1, dt * 8)
				ball.r += (snap.r - ball.r) * math.min(1, dt * 6)
			end
		elseif snap then
			local age = math.min(now - snap.at, 0.3)
			local ts = snap.s + snap.v * age
			local tx = snap.x + snap.vx * age
			ball.s += (ts - ball.s) * math.min(1, dt * 10)
			ball.x += (tx - ball.x) * math.min(1, dt * 10)
			ball.r += (snap.r - ball.r) * math.min(1, dt * 6)
			ball.v = snap.v
		end
		local smp = spline:sample(ball.s)
		local center = smp.Pos + smp.Right * ball.x + Vector3.yAxis * ball.r
		local drawR = ball.r
		if d.isLocal then
			-- Hop off ramps (a parabola), land with a thump.
			local t = (now - jumpAt) / JUMP_TIME
			if t >= 0 and t < 1 then
				center += Vector3.yAxis * (4 * jumpHeight * t * (1 - t))
			elseif not landed then
				landed = true
				BallController:Shake(1.4)
				Fx.burst("Puff", center - Vector3.yAxis * ball.r, math.clamp(ball.r / 2, 1, 4))
				Ui.sound("SnowHit", 0.7)
			end
			-- Grow pop: the ball bulges for a moment every time it picks up snow.
			if ball.r > lastR + 0.02 and lastR > 0 then
				pop = 1
			end
			lastR = ball.r
			pop = math.max(0, pop - dt * 5)
			drawR = ball.r * (1 + 0.16 * math.sin(pop * math.pi))
			-- Snow spray from where the ball touches the ground, thrown backwards.
			if spray and sprayEmitter then
				local grounded = not (t >= 0 and t < 1)
				local contact = center - Vector3.yAxis * (ball.r * 0.85)
				spray.CFrame = CFrame.lookAt(contact, contact - smp.Forward + Vector3.yAxis * 0.6)
				sprayEmitter.Rate = if grounded then math.clamp(ball.v * 0.8, 0, 60) else 0
				sprayEmitter.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, math.max(1.5, ball.r * 0.6)),
					NumberSequenceKeypoint.new(1, math.max(3, ball.r * 1.3)),
				})
			end
		end
		-- Roll: spin around the side axis by distance / radius.
		d.spin = CFrame.fromAxisAngle(Vector3.xAxis, -(ball.v * dt) / math.max(ball.r, 1)) * d.spin
		local facing = CFrame.lookAt(center, center + smp.Forward)
		d.part.Size = Vector3.one * (drawR * 2)
		d.part.CFrame = facing * d.spin
		if d.isLocal then
			local turn = facing * d.spin
			for _, st in stuck do
				local world = turn:VectorToWorldSpace(st.dir)
				st.part.CFrame = CFrame.new(turn.Position + world * drawR * 0.97) * turn.Rotation * st.rot
			end
		end
		d.part.Transparency = if d.isLocal then 0 else 0.35
	end
	local cb = cameraBall
	if cb and balls[player.UserId] == cb then
		local cam = Workspace.CurrentCamera
		local ball = cb.ball
		local smp = spline:sample(ball.s)
		local center = smp.Pos + smp.Right * ball.x + Vector3.yAxis * ball.r
		local flat = Vector3.new(smp.Forward.X, 0, smp.Forward.Z).Unit
		local back = 22 + ball.r * 2.4
		local up = 10 + ball.r * 1.3
		local t = (os.clock() - jumpAt) / JUMP_TIME
		if t >= 0 and t < 1 then
			center += Vector3.yAxis * (4 * jumpHeight * t * (1 - t) * 0.7)
		end
		local want = CFrame.lookAt(center - flat * back + Vector3.yAxis * up, center + flat * 14)
		if cam then
			local base = cam.CFrame:Lerp(want, math.min(1, dt * 8))
			-- Screen shake on top of the follow, decaying fast.
			shake = math.max(0, shake - dt * 4)
			local k = shake * shake
			local jitter = CFrame.new((math.random() - 0.5) * k * 1.2, (math.random() - 0.5) * k * 1.2, 0)
				* CFrame.Angles(0, 0, (math.random() - 0.5) * k * 0.04)
			cam.CFrame = base * jitter
			-- Faster = wider view; a ramp hop widens it more.
			local speed01 = math.clamp(ball.v / 70, 0, 1)
			local air = if t >= 0 and t < 1 then 8 else 0
			local fov = BASE_FOV + speed01 * 22 + air
			cam.FieldOfView += (fov - cam.FieldOfView) * math.min(1, dt * 4)
			drawLines(speed01)
		end
		C.HudController:SetZoneProgress(ball.s)
		C.TrackFxController:Update(ball)
	end
end

function BallController:Init(controllers)
	C = controllers
	spline = Spline.main()
	endAt = math.min(Zones.VillageWall, spline.Length - 5)
	folder = Instance.new("Folder")
	folder.Name = "Balls"
	folder.Parent = Workspace
end

function BallController:Start()
	Net.event("RunStarted").OnClientEvent:Connect(onStarted)
	Net.event("RunSnapshot").OnClientEvent:Connect(onSnapshot)
	Net.event("RunEnded").OnClientEvent:Connect(onEnded)
	Net.event("RunStopped").OnClientEvent:Connect(onStopped)
	Net.event("RunContinued").OnClientEvent:Connect(onContinued)
	RunService:BindToRenderStep("SnowballBalls", Enum.RenderPriority.Camera.Value + 1, step)
end

return BallController
