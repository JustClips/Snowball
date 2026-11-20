--!strict
-- The egg rescue on screen (EggRescueService, Config/Rescue; Dev 2026-11-20, Throw Food's
-- carry-home): the goal pill at the top ("Grab an egg!" / "Run to the flag!") with the eggs
-- left in the pile and the time, the ground arrows + bouncing marker to the pile or the
-- flag (TutorialController:Guide), a SAFE! sign over the flag with the distance, the Robux
-- buttons at the bottom (SLED HOME, YETI SPRAY) and LEAVE, big words (RUN! / OUCH! /
-- SAVED!), a fade when you're taken back to the pile, and the yeti itself: the Blender
-- model from ReplicatedStorage.Assets.Yeti (12 parts), following the server's YetiPos and
-- posed through a real joint hierarchy: idle (breathing, looking round, head scratch), walk,
-- gallop, roar + chest pound, the grab slam, and a victory hop.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Rescue = require(Shared.Config.Rescue)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local RescueController = {}

local C: any

-- The yeti's skeleton (art/blender/yeti.py v2: 12 parts). Joint pivots are model-local
-- (floor centre at the origin, front = -Z); every part sits unrotated in the model, so a
-- joint's rotation is about the model's own axes: +X swings a hanging limb FORWARD, +X on
-- the torso leans it BACK, -X on the jaw opens the mouth, -Z/+Z lifts the left/right arm
-- out to the side.
local JOINTS: { [string]: Vector3 } = {
	Torso = Vector3.new(0, 4.4, 0.1),
	Head = Vector3.new(0, 8.0, -0.2),
	Jaw = Vector3.new(0, 8.7, -0.9),
	UpperArmL = Vector3.new(-3.0, 7.3, 0.2),
	LowerArmL = Vector3.new(-3.5, 5.0, 0.0),
	UpperArmR = Vector3.new(3.0, 7.3, 0.2),
	LowerArmR = Vector3.new(3.5, 5.0, 0.0),
	ThighL = Vector3.new(-1.35, 3.6, 0.1),
	ShinL = Vector3.new(-1.45, 1.9, -0.1),
	ThighR = Vector3.new(1.35, 3.6, 0.1),
	ShinR = Vector3.new(1.45, 1.9, -0.1),
}
-- Where the Hips mesh's bounding-box centre sits in the model (from art/out/Yeti.glb).
local HIPS_CENTRE = Vector3.new(0.084, 3.769, 0.098)
-- Parents first, so a child always reads its parent's finished frame.
local BONES: { { string } } = {
	{ "Torso", "Hips" },
	{ "Head", "Torso" },
	{ "Jaw", "Head" },
	{ "UpperArmL", "Torso" },
	{ "LowerArmL", "UpperArmL" },
	{ "UpperArmR", "Torso" },
	{ "LowerArmR", "UpperArmR" },
	{ "ThighL", "Hips" },
	{ "ShinL", "ThighL" },
	{ "ThighR", "Hips" },
	{ "ShinR", "ThighR" },
}

-- A pose: joint -> (pitch X, yaw Y, roll Z) in radians, plus the body's lift and pitch.
type Pose = { [string]: Vector3 }

local gui: ScreenGui
local top: Frame
local goalIcon: ImageLabel
local goalText: TextLabel
local leftText: TextLabel
local timeText: TextLabel
local bottom: Frame
local sledButton: TextButton
local sprayButton: TextButton
local leaveButton: TextButton
local fade: Frame

type Yeti = {
	model: Model,
	parts: { [string]: { part: BasePart, base: CFrame } },
	pos: Vector3,
	yaw: number,
	phase: number,
	lastStomp: number,
	shown: boolean,
	pose: Pose, -- what's on screen (eases toward each frame's target)
	swipeAt: number, -- os.clock() of the last grab/swipe (one-shot)
	state: string,
	stateAt: number,
}
local yeti: Yeti? = nil
-- One thing on screen at a time (Dev 2026-11-20 "tf is this ui spam"): the run's result
-- card first, then the rescue HUD; and the HUD goes the moment the rescue is over
-- (last egg saved, sled bought) instead of flashing "Grab an egg!" for a second.
local quietUntil = 0
local ending = false
local sawCard = false
local flagSign: BillboardGui? = nil

local function myFolder(): Folder?
	local rescue = Workspace:FindFirstChild("Rescue")
	return rescue and rescue:FindFirstChild(tostring(player.UserId)) :: Folder?
end

local function rootPos(): Vector3?
	local character = player.Character
	local r = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return r and r.Position
end

-------------------------------------------------------------------------- yeti

local function makeYeti(folder: Folder): Yeti?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Yeti") :: Model?
	if not template then
		return nil
	end
	local model = template:Clone()
	local parts = {}
	-- Stand it on the ground whatever the import did to the pivot (Dev 2026-11-20: "yeti
	-- seems to be on air"): the lowest mesh point goes to y = 0, centred on x/z.
	local minY, n = math.huge, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "RootPart" or d:IsA("Part") then
				d.Transparency = 1
			else
				local cf, size = d.CFrame, d.Size
				local half = (cf.RightVector * size.X):Abs()
					+ (cf.UpVector * size.Y):Abs()
					+ (cf.LookVector * size.Z):Abs()
				minY = math.min(minY, cf.Position.Y - half.Y / 2)
				n += 1
			end
		end
	end
	-- Best: put the Hips mesh where Blender had it (its bounding-box centre, model-local);
	-- else just drop the lowest point to the floor.
	local hipsPart = model:FindFirstChild("Hips", true) :: BasePart?
	local shift = if hipsPart
		then CFrame.new(HIPS_CENTRE - hipsPart.Position)
		elseif n > 0 then CFrame.new(0, -minY, 0)
		else CFrame.identity
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts[d.Name] = { part = d, base = shift * d.CFrame }
		end
	end
	local missing = {}
	for name in JOINTS do
		if not parts[name] then
			table.insert(missing, name)
		end
	end
	if not parts.Hips or #missing > 0 then
		local found = {}
		for name in parts do
			table.insert(found, name)
		end
		warn(`[Rescue] yeti model is missing parts {table.concat(missing, ",")}; has {table.concat(found, ",")}`)
	end
	model.Parent = folder
	return {
		model = model,
		parts = parts,
		pos = folder:GetAttribute("YetiPos") or Vector3.zero,
		yaw = folder:GetAttribute("YetiYaw") or 0,
		phase = 0,
		lastStomp = 0,
		shown = true,
		pose = {},
		swipeAt = -10,
		state = "Den",
		stateAt = os.clock(),
	}
end

local function v(x: number, y: number?, z: number?): Vector3
	return Vector3.new(x, y or 0, z or 0)
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- The animation clips. Each returns the target pose for this frame. `p` is the gait
-- phase (advances with speed), `t` the clock, `age` seconds in this state.
local function idlePose(t: number): Pose
	local breathe = math.sin(t * 1.7)
	local look = math.sin(t * 0.45) * 0.55 + math.sin(t * 1.3) * 0.1
	-- Every few seconds it scratches its head with the right paw.
	local scratch = smooth((math.sin(t * 0.5) - 0.75) * 5)
	local rub = math.sin(t * 16) * 0.12 * scratch
	return {
		Body = v(0, 0.05 * breathe, 0), -- lift, pitch
		Torso = v(-0.06 + breathe * 0.04, look * 0.25, math.sin(t * 0.9) * 0.04),
		Head = v(0.05 + breathe * 0.03, look * 0.6, scratch * 0.2),
		Jaw = v(-0.06 - breathe * 0.05),
		UpperArmL = v(0.12 + breathe * 0.05, 0, -0.14 - breathe * 0.04),
		LowerArmL = v(0.25),
		UpperArmR = v(0.12 + breathe * 0.05 + scratch * 2.4, 0, 0.14 + breathe * 0.04 + scratch * 0.35),
		LowerArmR = v(0.25 + scratch * 1.9 + rub, 0, scratch * -0.4),
		ThighL = v(0.05),
		ShinL = v(-0.08),
		ThighR = v(0.05),
		ShinR = v(-0.08),
	}
end

local function walkPose(p: number, amount: number, run: boolean): Pose
	local s, c = math.sin(p), math.cos(p)
	local legs = if run then 0.95 else 0.6
	local arms = if run then 1.05 else 0.5
	local lean = if run then -0.42 else -0.12
	return {
		Body = v(math.abs(s) * (if run then 0.75 else 0.3), 0),
		Torso = v(lean + math.abs(s) * 0.06, s * (if run then 0.22 else 0.12), c * 0.05),
		-- Head up against the lean so it keeps glaring at you; mouth open while it runs.
		Head = v(-lean * 0.8 + s * 0.05, -s * 0.15, 0),
		Jaw = v(if run then -0.42 + math.abs(c) * 0.12 else -0.08),
		UpperArmL = v(-s * arms + (if run then 0.35 else 0.05), 0, -0.22),
		LowerArmL = v(0.35 + math.max(0, s) * 0.6),
		UpperArmR = v(s * arms + (if run then 0.35 else 0.05), 0, 0.22),
		LowerArmR = v(0.35 + math.max(0, -s) * 0.6),
		ThighL = v(s * legs - lean * 0.6),
		ShinL = v(-math.max(0, -c) * legs * 1.1 - 0.1),
		ThighR = v(-s * legs - lean * 0.6),
		ShinR = v(-math.max(0, c) * legs * 1.1 - 0.1),
	}
end

-- Wake: it rears up, throws its head back and pounds its chest with both fists.
local function roarPose(t: number, age: number): Pose
	local up = smooth(age / 0.35)
	local pound = math.sin(t * 15)
	local shake = math.sin(t * 40) * 0.04
	return {
		Body = v(0.35 * up, 0),
		Torso = v(0.22 * up, shake, 0),
		Head = v(0.55 * up + shake, 0, shake),
		Jaw = v(-0.75 * up),
		UpperArmL = v(1.25 * up + math.max(0, pound) * 0.35, 0.5 * up, -0.35 * up),
		LowerArmL = v(1.55 * up),
		UpperArmR = v(1.25 * up + math.max(0, -pound) * 0.35, -0.5 * up, 0.35 * up),
		LowerArmR = v(1.55 * up),
		ThighL = v(0, 0, -0.18 * up),
		ShinL = v(-0.15 * up),
		ThighR = v(0, 0, 0.18 * up),
		ShinR = v(-0.15 * up),
	}
end

-- Grab: both arms come up over its head and slam down in front (one-shot, 0.7 s).
local function swipePose(age: number): Pose
	local raise = smooth(age / 0.22)
	local slam = smooth((age - 0.22) / 0.14)
	local arm = 2.9 * raise - 2.1 * slam
	return {
		Body = v(0.4 * raise - 0.55 * slam, 0),
		Torso = v(0.25 * raise - 0.75 * slam),
		Head = v(0.3 * raise + 0.35 * slam),
		Jaw = v(-0.9 * raise + 0.3 * slam),
		UpperArmL = v(arm, 0, -0.25),
		LowerArmL = v(0.4 - 0.3 * slam),
		UpperArmR = v(arm, 0, 0.25),
		LowerArmR = v(0.4 - 0.3 * slam),
		ThighL = v(0.35 * slam),
		ShinL = v(-0.55 * slam),
		ThighR = v(-0.2 * slam),
		ShinR = v(-0.2 * slam),
	}
end

-- Stun (after it got you): hops about with both fists in the air, mouth wide.
local function cheerPose(t: number): Pose
	local hop = math.abs(math.sin(t * 7))
	local wave = math.sin(t * 7)
	return {
		Body = v(hop * 0.8, 0),
		Torso = v(0.12, wave * 0.15, wave * 0.08),
		Head = v(0.35, wave * 0.3, 0),
		Jaw = v(-0.6 - hop * 0.15),
		UpperArmL = v(2.7 + wave * 0.15, 0, -0.45),
		LowerArmL = v(0.3 + hop * 0.4),
		UpperArmR = v(2.7 - wave * 0.15, 0, 0.45),
		LowerArmR = v(0.3 + hop * 0.4),
		ThighL = v(0.3 * hop),
		ShinL = v(-0.5 * hop),
		ThighR = v(0.3 * hop),
		ShinR = v(-0.5 * hop),
	}
end

local function rot(a: Vector3?): CFrame
	if not a then
		return CFrame.identity
	end
	return CFrame.Angles(a.X, a.Y, a.Z)
end

local function drawYeti(y: Yeti, folder: Folder, dt: number)
	local target = folder:GetAttribute("YetiPos") :: Vector3? or y.pos
	local state = folder:GetAttribute("YetiState") or "Den"
	local asleep = state == "Asleep"
	if y.shown ~= not asleep then
		y.shown = not asleep
		for name, entry in y.parts do
			if JOINTS[name] or name == "Hips" then
				entry.part.Transparency = if asleep then 1 else 0
			end
		end
	end
	if asleep then
		return
	end
	local t = os.clock()
	if state ~= y.state then
		y.state = state
		y.stateAt = t
	end
	local age = t - y.stateAt
	local before = y.pos
	y.pos = y.pos:Lerp(target, math.min(1, dt * 10))
	local yawTarget = folder:GetAttribute("YetiYaw") or y.yaw
	local dy = (yawTarget - y.yaw + math.pi) % (math.pi * 2) - math.pi
	y.yaw += dy * math.min(1, dt * 8)
	local speed = (Vector3.new(y.pos.X, 0, y.pos.Z) - Vector3.new(before.X, 0, before.Z)).Magnitude / math.max(dt, 1e-3)
	local moving = math.clamp(speed / 6, 0, 1)
	y.phase += dt * (2 + speed * 0.62)

	-- Pick the clip for this frame.
	local goal: Pose
	local swipeAge = t - y.swipeAt
	if swipeAge < 0.75 then
		goal = swipePose(swipeAge)
	elseif state == "Wake" then
		goal = roarPose(t, age)
	elseif state == "Stun" then
		goal = cheerPose(t)
	elseif moving > 0.15 then
		goal = walkPose(y.phase, moving, state == "Chase" or speed > 9)
	else
		goal = idlePose(t)
	end
	-- Ease toward it, fast enough that a gait still reads, slow enough to blend clips.
	local k = math.min(1, dt * (if swipeAge < 0.75 then 30 else 14))
	for name, a in goal do
		local cur = y.pose[name]
		y.pose[name] = if cur then cur:Lerp(a, k) else a
	end

	local body = y.pose.Body or Vector3.zero
	local root = CFrame.new(y.pos + Vector3.new(0, body.X, 0)) * CFrame.Angles(0, y.yaw, 0)
	local frames: { [string]: CFrame } = { Hips = root }
	local hips = y.parts.Hips
	if hips then
		hips.part.CFrame = root * hips.base
	end
	for _, bone in BONES do
		local name, parent = bone[1], bone[2]
		local j = JOINTS[name]
		local frame = (frames[parent] or root) * CFrame.new(j) * rot(y.pose[name]) * CFrame.new(-j)
		frames[name] = frame
		local entry = y.parts[name]
		if entry then
			entry.part.CFrame = frame * entry.base
		end
	end
	-- Anything else in the model (an unexpected name) rides along with the hips.
	for name, entry in y.parts do
		if name ~= "Hips" and not JOINTS[name] then
			entry.part.CFrame = root * entry.base
		end
	end
	-- Heavy steps you can hear (and feel) while it runs.
	if moving > 0.5 and math.floor(y.phase / math.pi) ~= y.lastStomp then
		y.lastStomp = math.floor(y.phase / math.pi)
		Ui.sound("Stomp", 0.9 + math.random() * 0.2)
	end
end

-------------------------------------------------------------------------- HUD

local function setGoal(icon: string, text: string, color: Color3?)
	goalIcon.Image = Ui.Images[icon] or ""
	goalText.Text = text
	goalText.TextColor3 = color or Color3.new(1, 1, 1)
end

local function pop(object: GuiObject)
	local sc = object:FindFirstChild("Pop") :: UIScale?
	if not sc then
		local n = Instance.new("UIScale")
		n.Name = "Pop"
		n.Parent = object
		sc = n
	end
	(sc :: UIScale).Scale = 1.25
	TweenService:Create(sc :: UIScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

local function priceOf(key: string): string
	local def = Products.ProductByKey[key]
	return if def then `{Ui.ROBUX}{def.Price}` else ""
end

local function buildHud()
	gui = Ui.screen("Rescue", 8)
	gui.Enabled = false
	local root = Ui.root(gui)
	top = Ui.frame({
		Name = "Goal",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(460, 58),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
	})
	Ui.corner(top, 29)
	Ui.autoScale(top)
	top.Parent = root
	goalIcon = Ui.icon("Egg", {
		Size = UDim2.fromOffset(72, 72),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 22, 0.5, 0),
		ZIndex = 3,
	})
	goalIcon.Parent = top
	goalText = Ui.label({
		Name = "Text",
		Size = UDim2.new(1, -86, 0, 40),
		Position = UDim2.fromOffset(62, 9),
		Text = "",
	})
	goalText.Parent = top
	-- Under the pill: eggs left in the pile and the clock.
	local info = Ui.frame({
		Name = "Info",
		Size = UDim2.fromOffset(300, 40),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		BackgroundTransparency = 1,
	})
	info.Parent = top
	Ui.icon("Egg", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(40, 0) }).Parent = info
	leftText = Ui.label({
		Name = "Left",
		Size = UDim2.fromOffset(80, 32),
		Position = UDim2.fromOffset(84, 4),
		Text = "x0",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	leftText.Parent = info
	Ui.icon("Clock", { Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(160, 2) }).Parent = info
	timeText = Ui.label({
		Name = "Time",
		Size = UDim2.fromOffset(90, 32),
		Position = UDim2.fromOffset(200, 4),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	timeText.Parent = info

	-- Bottom centre: the Robux helpers (purple = Robux, like Steal an Egg).
	bottom = Ui.frame({
		Name = "Bottom",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -98), -- above the bag hotbar, where ROLL sits
		Size = UDim2.fromOffset(520, 84),
		BackgroundTransparency = 1,
	})
	Ui.autoScale(bottom)
	bottom.Parent = root
	local purple = Color3.fromRGB(150, 70, 240)
	sledButton = Ui.bigButton("Sled", "Sled", "SLED HOME", purple, function()
		local ok, msg = Net.func("Rescue"):InvokeServer("Sled")
		if not ok and msg then
			Ui.toast(msg, "Bad")
		end
	end, Vector2.new(270, 78))
	sledButton.Position = UDim2.fromOffset(0, 0)
	sledButton.Parent = bottom
	sprayButton = Ui.bigButton("Spray", "YetiSpray", "NO YETI", purple, function()
		local ok, msg = Net.func("Rescue"):InvokeServer("Repel")
		if not ok and msg then
			Ui.toast(msg, "Bad")
		end
	end, Vector2.new(230, 78))
	sprayButton.Position = UDim2.new(1, -230, 0, 0)
	sprayButton.Parent = bottom
	for _, pair in { { sledButton, "SledHome" }, { sprayButton, "YetiRepellent" } } do
		local price = Ui.label({
			Name = "Price",
			Size = UDim2.fromOffset(110, 30),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 30, 0, -4),
			BackgroundTransparency = 0,
			BackgroundColor3 = Ui.Colors.Green,
			Text = priceOf(pair[2]),
			ZIndex = 6,
		})
		Ui.corner(price, 15)
		Ui.stroke(price, 3)
		price.Parent = pair[1]
	end
	-- LEAVE (top-left): go home now, the eggs left in the pile melt.
	local leaveHolder = Ui.frame({
		Name = "LeaveHolder",
		Position = UDim2.fromOffset(24, 18),
		Size = UDim2.fromOffset(150, 56),
		BackgroundTransparency = 1,
	})
	Ui.autoScale(leaveHolder)
	leaveHolder.Parent = root
	leaveButton = Ui.button(
		{
			Name = "Leave",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Ui.Colors.Red,
		},
		"LEAVE",
		function()
			Net.func("Rescue"):InvokeServer("Leave")
		end
	)
	leaveButton.Parent = leaveHolder

	fade = Ui.frame({
		Name = "Fade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(235, 245, 255),
		BackgroundTransparency = 1,
		ZIndex = 50,
	})
	fade.Parent = gui
end

local function fadeOutIn()
	TweenService:Create(fade, TweenInfo.new(0.5), { BackgroundTransparency = 0 }):Play()
	task.delay(1.1, function()
		TweenService:Create(fade, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	end)
end

-- SAFE! over the flag with how far it is.
local function updateFlagSign(folder: Folder, flagPos: Vector3?, me: Vector3?)
	local flag = folder:FindFirstChild("Flag") :: Model?
	if not flag or not flagPos then
		return
	end
	local sign = flagSign
	if not sign or sign.Parent ~= flag then
		local b = Instance.new("BillboardGui")
		b.Name = "Safe"
		b.Size = UDim2.fromOffset(220, 110)
		b.StudsOffsetWorldSpace = Vector3.new(0, 26, 0)
		b.AlwaysOnTop = true
		b.LightInfluence = 0
		b.MaxDistance = 1000
		local word = Ui.label({
			Name = "Word",
			Size = UDim2.new(1, 0, 0, 62),
			Text = "SAFE!",
			TextColor3 = Color3.fromRGB(110, 235, 90),
		})
		word.Parent = b
		Ui.label({
			Name = "Dist",
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, 64),
			Text = "",
		}).Parent =
			b
		b.Adornee = flag.PrimaryPart or flag:FindFirstChildWhichIsA("BasePart", true)
		b.Parent = flag
		flagSign = b
		sign = b
	end
	local dist = sign and sign:FindFirstChild("Dist") :: TextLabel?
	if dist and me then
		dist.Text = `{math.floor((me - flagPos).Magnitude)}m`
	end
end

-------------------------------------------------------------------------- events

local function onEvent(kind: string, data: any)
	if kind == "Start" then
		-- The result card gets the screen to itself for a moment, then the rescue starts.
		ending = false
		quietUntil = os.clock() + 2.2
		sawCard = false
		task.delay(2.2, function()
			sawCard = false
			C.ResultsController:Close()
			Ui.word(`{data.Eggs} EGG{if data.Eggs > 1 then "S" else ""} TO SAVE!`, Ui.Colors.Yellow, 1.4)
			Ui.sound("Pop")
		end)
	elseif kind == "Grab" then
		Ui.sound("Egg")
		Ui.word(if data.Count > 1 then "GOT 2!" else "GOT IT!", Ui.Colors.Ice, 0.6)
	elseif kind == "Wake" then
		Ui.sound("Roar")
		Ui.word("RUN!", Ui.Colors.Red, 0.9, 1.3)
		if C.BallController and C.BallController.Shake then
			C.BallController:Shake(0.6)
		end
	elseif kind == "Knocked" then
		if yeti then
			yeti.swipeAt = os.clock()
		end
		-- Your character's physics run here, so the hit that throws you is applied here too.
		local character = player.Character
		local r = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if r and hum and typeof(data.From) == "Vector3" then
			local away = Vector3.new(r.Position.X - data.From.X, 0, r.Position.Z - data.From.Z)
			away = if away.Magnitude > 0.1 then away.Unit else Vector3.zAxis
			hum.PlatformStand = true
			r.AssemblyLinearVelocity = away * 38 + Vector3.new(0, 34, 0)
			r.AssemblyAngularVelocity = Vector3.new(away.Z, 0, -away.X) * 8
			task.delay(Rescue.KnockSeconds, function()
				if hum.Parent then
					hum.PlatformStand = false
					hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
			end)
		end
		Ui.sound("Fall")
		Ui.sound("Roar", 1.15)
		Ui.word("OUCH!", Ui.Colors.Red, 0.9, 1.3)
		if C.BallController and C.BallController.Shake then
			C.BallController:Shake(1)
		end
	elseif kind == "Saved" then
		Ui.sound("Reveal")
		Ui.word(if data.Left > 0 then "SAVED!" else "ALL SAVED!", Ui.Colors.Green, 1, 1.3)
		if data.Left > 0 then
			fadeOutIn()
		else
			ending = true
		end
	elseif kind == "Sled" then
		ending = true
		Ui.sound("Reveal")
		Ui.word(`{#data.Eggs} EGGS SLEDDED HOME!`, Ui.Colors.Green, 1.4)
	elseif kind == "Repelled" then
		Ui.sound("Upgrade")
		Ui.word("NO YETI!", Ui.Colors.Green, 1)
	elseif kind == "Ended" then
		ending = false
		local saved = #data.Saved
		if data.Reason == "Time" then
			Ui.toast("Time's up! The rest of the eggs froze.", "Bad")
		elseif data.Reason ~= "Sled" and saved > 0 then
			Ui.toast(`You saved {saved} egg{if saved > 1 then "s" else ""}! Put them on your base.`, "Good")
		end
	end
end

-------------------------------------------------------------------------- loop

local function step(dt: number)
	local folder = myFolder()
	local phase = player:GetAttribute("Rescue")
	local on = phase ~= nil and folder ~= nil
	if os.clock() < quietUntil then
		if C.ResultsController:IsOpen() then
			sawCard = true
		elseif sawCard then
			quietUntil = 0 -- tapped the card away: start now
		end
	end
	gui.Enabled = on and not ending and os.clock() >= quietUntil
	if not on or not folder or ending then
		C.TutorialController:Guide(nil)
	end
	if not on or not folder then
		if yeti then
			yeti.model:Destroy()
			yeti = nil
		end
		flagSign = nil
		C.TutorialController:Guide(nil)
		return
	end
	local f = folder :: Folder
	if not yeti or yeti.model.Parent ~= f then
		yeti = makeYeti(f)
	end
	if yeti then
		drawYeti(yeti, f, dt)
	end
	local me = rootPos()
	local flagPos = f:GetAttribute("FlagPos") :: Vector3?
	local pilePos = f:GetAttribute("PilePos") :: Vector3?
	local carrying = phase == "Carry"
	local state = f:GetAttribute("YetiState")
	if carrying then
		if state == "Chase" or state == "Wake" then
			setGoal("Yeti", "RUN to the flag!", Color3.fromRGB(255, 120, 110))
		else
			setGoal("Pin", "Run to the flag!", Color3.fromRGB(110, 235, 90))
		end
		C.TutorialController:Guide(flagPos)
	elseif not ending then
		setGoal("Egg", "Grab an egg!")
		C.TutorialController:Guide(pilePos)
	end
	leftText.Text = `x{f:GetAttribute("Left") or 0}`
	local endsAt = f:GetAttribute("EndsAt") or 0
	local left = math.max(0, endsAt - Workspace:GetServerTimeNow())
	timeText.Text = Format.time(left)
	timeText.TextColor3 = if left < 30 then Ui.Colors.Red else Color3.new(1, 1, 1)
	if ending then
		return
	end
	-- The Robux helpers only when they help: SLED HOME (every egg home now) once there's an
	-- egg in your arms or more than one left, NO YETI (cheap, 10 minutes) only while the
	-- yeti is up and coming for you.
	local awake = state == "Wake" or state == "Chase" or state == "Return"
	sprayButton.Visible = awake
	sledButton.Visible = carrying or (f:GetAttribute("Left") or 0) > 1
	sledButton.Position = if sprayButton.Visible then UDim2.fromOffset(0, 0) else UDim2.new(0.5, -135, 0, 0)
	updateFlagSign(f, flagPos, me)
end

function RescueController:Init(controllers)
	C = controllers
	buildHud()
end

function RescueController:Start()
	Net.event("RescueEvent").OnClientEvent:Connect(function(kind, data)
		onEvent(kind, data or {})
		if kind == "Grab" or kind == "Saved" then
			pop(top)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return RescueController
