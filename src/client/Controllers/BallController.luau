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
}
local balls: { [number]: Drawn } = {}
local cameraBall: Drawn? = nil
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

local function step(dt: number)
	local now = os.clock()
	for _, d in balls do
		local ball = d.ball
		local snap = d.snap
		if d.isLocal then
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
		-- Roll: spin around the side axis by distance / radius.
		d.spin = CFrame.fromAxisAngle(Vector3.xAxis, -(ball.v * dt) / math.max(ball.r, 1)) * d.spin
		local facing = CFrame.lookAt(center, center + smp.Forward)
		d.part.Size = Vector3.one * (ball.r * 2)
		d.part.CFrame = facing * d.spin
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
		local want = CFrame.lookAt(center - flat * back + Vector3.yAxis * up, center + flat * 14)
		if cam then
			cam.CFrame = cam.CFrame:Lerp(want, math.min(1, dt * 8))
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
	RunService:BindToRenderStep("SnowballBalls", Enum.RenderPriority.Camera.Value + 1, step)
end

return BallController
