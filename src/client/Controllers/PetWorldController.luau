--!strict
-- Pets and eggs in every base's pet park (Steal an Egg / Sweep the World): the server
-- publishes each player's pets as Folders in base.Pets (PetId / Mutation / Huge / Weight /
-- Income / X / Z). Every client builds the models itself and lets them wander inside the
-- fence with Idle / Walk animations (Config/Anims Pet_<Model>_Idle/_Walk/_Happy from the
-- pet animation thread; a procedural hop until a pet has clips), a little "+$/s" tag, and
-- a Pick Up prompt on your own pets (picking one up puts it straight in your arms).
-- Eggs growing in a park get a timer that turns into READY!. Only parks near the camera
-- are simulated.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Anims = require(Shared.Config.Anims)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local PetLook = require(Shared.PetLook)
local PetStats = require(Shared.PetStats)
local Pets = require(Shared.Config.Pets)
local World = require(Shared.Config.World)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local ACTIVE_DISTANCE = 220 -- camera focus to base centre
local MARGIN = 3 -- keep this far from the fence
local WALK_SPEED = 5 -- studs per second (bigger pets walk a bit faster)
local TURN_SPEED = 6
local IDLE_TIME = NumberRange.new(2, 6)
local HAPPY_EVERY = NumberRange.new(18, 40)

local player = Players.LocalPlayer

local PetWorldController = {}

local C: any

type Pet = {
	key: string,
	uid: string,
	model: Model,
	position: Vector2,
	yaw: number,
	target: Vector2?,
	waitUntil: number,
	nextHappy: number,
	speed: number,
	phase: number,
	idle: AnimationTrack?,
	walk: AnimationTrack?,
	happy: AnimationTrack?,
	walking: boolean,
	animated: boolean,
}

type Park = {
	index: number,
	cframe: CFrame,
	pets: { [string]: Pet },
	active: boolean,
	folder: Folder,
}

local parks: { [number]: Park } = {}
local root: Folder
local rng = Random.new()
local eggLabels: { [BasePart]: { text: TextLabel, rarity: TextLabel } } = {}

local function lerpAngle(a: number, b: number, t: number): number
	local diff = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + diff * t
end

local function clearAt(p: Vector2, pad: number): boolean
	for _, prop in World.ParkProps do
		if (p - Vector2.new(prop.Position.X, prop.Position.Z)).Magnitude < prop.Radius + pad then
			return false
		end
	end
	return true
end

local function clearPath(a: Vector2, b: Vector2, pad: number): boolean
	local ab = b - a
	local len2 = ab:Dot(ab)
	for _, prop in World.ParkProps do
		local c = Vector2.new(prop.Position.X, prop.Position.Z)
		local t = if len2 > 0 then math.clamp((c - a):Dot(ab) / len2, 0, 1) else 0
		if (a + ab * t - c).Magnitude < prop.Radius + pad then
			return false
		end
	end
	return true
end

local function randomSpot(from: Vector2?): Vector2?
	local min, max = World.ParkMin, World.ParkMax
	for _ = 1, 10 do
		local p =
			Vector2.new(rng:NextNumber(min.X + MARGIN, max.X - MARGIN), rng:NextNumber(min.Y + MARGIN, max.Y - MARGIN))
		local near = if from then (p - from).Magnitude < 22 else true
		if near and clearAt(p, 1.5) and (not from or clearPath(from, p, 1)) then
			return p
		end
	end
	return nil
end

-- Bone clips for this pet's pack model, if the animation thread made them.
local function loadTrack(model: Model, petModel: string, state: string): AnimationTrack?
	local id = (Anims :: any)[`Pet_{petModel}_{state}`]
	if not id then
		return nil
	end
	local controller = model:FindFirstChildWhichIsA("AnimationController", true)
	if not controller then
		local ac = Instance.new("AnimationController")
		ac.Parent = model
		controller = ac
	end
	local animator = (controller :: AnimationController):FindFirstChildOfClass("Animator")
	if not animator then
		local a = Instance.new("Animator")
		a.Parent = controller
		animator = a
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if not ok then
		return nil
	end
	local t = track :: AnimationTrack
	t.Priority = if state == "Idle"
		then Enum.AnimationPriority.Idle
		elseif state == "Walk" then Enum.AnimationPriority.Movement
		else Enum.AnimationPriority.Action
	t.Looped = state ~= "Happy"
	return t
end

-- Small always-on tag: +$/s in green (the full card shows on hover, HoverController).
local function tag(model: Model, income: number)
	local _, size = model:GetBoundingBox()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Tag"
	billboard.Size = UDim2.fromOffset(110, 26)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, size.Y + 0.9, 0)
	billboard.MaxDistance = 45
	billboard.LightInfluence = 0
	billboard.Adornee = model.PrimaryPart
	local cash = Ui.label({ Name = "Cash", Size = UDim2.fromScale(1, 1), Text = "", TextColor3 = Ui.Colors.Green })
	cash.Text = `+{Format.cash(income)}/s`
	cash.Parent = billboard
	billboard.Parent = model
end

local function pivot(park: Park, pet: Pet, hop: number)
	pet.model:PivotTo(
		park.cframe * CFrame.new(pet.position.X, World.ParkTop + hop, pet.position.Y) * CFrame.Angles(0, pet.yaw, 0)
	)
end

local function setWalking(pet: Pet, walking: boolean)
	if pet.walking == walking then
		return
	end
	pet.walking = walking
	if pet.walk then
		if walking then
			pet.walk:Play(0.2)
			pet.walk:AdjustSpeed(math.clamp(pet.speed / 10, 0.6, 2))
		else
			pet.walk:Stop(0.25)
		end
	end
end

local function addPickup(model: Model, uid: string)
	local part = model.PrimaryPart
	if not part then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickUp"
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = model:GetAttribute("DisplayName") or ""
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = part
	prompt.Triggered:Connect(function()
		local ok, why = Net.func("Pets"):InvokeServer("PickUp", uid)
		if ok then
			-- Straight into your arms, like Steal an Egg.
			C.PlacementController:Hold("Pet", uid)
		elseif why then
			Ui.toast(why, "Bad")
		end
	end)
end

-- An invisible box around the pet: the model's PrimaryPart (moved by PivotTo), what the
-- mouse hovers and where the prompt sits.
local function hitBox(model: Model)
	local cf, size = model:GetBoundingBox()
	local box = Instance.new("Part")
	box.Name = "Hit"
	box.Size = size + Vector3.new(0.4, 0.4, 0.4)
	box.CFrame = cf
	box.Transparency = 1
	box.Anchored = true
	box.CanCollide = false
	box.CanTouch = false
	box.CanQuery = true
	box.Parent = model
	local pivotCf = model:GetPivot()
	model.PrimaryPart = box
	model.WorldPivot = pivotCf
end

local function spawnPet(park: Park, key: string, entry: Folder, fresh: boolean, owned: boolean)
	local petId = entry:GetAttribute("PetId") :: string
	local def = Pets.ById[petId]
	if not def then
		return
	end
	local info = {
		Id = petId,
		Mutation = entry:GetAttribute("Mutation"),
		Huge = entry:GetAttribute("Huge") == true,
		Weight = entry:GetAttribute("Weight"),
	}
	local model = PetLook.make(petId, info.Mutation, info.Huge, PetStats.sizeMult(info))
	if not model then
		return
	end
	model:PivotTo(CFrame.new())
	hitBox(model)
	model:SetAttribute("DisplayName", PetStats.name(info))
	-- Read by HoverController for the hover card.
	model:SetAttribute("PetId", petId)
	model:SetAttribute("Mutation", info.Mutation)
	model:SetAttribute("Huge", info.Huge)
	model:SetAttribute("Weight", info.Weight)
	model:SetAttribute("Income", entry:GetAttribute("Income") or 0)
	model:SetAttribute("Owner", if owned then player.Name else "")
	local x, z = entry:GetAttribute("X"), entry:GetAttribute("Z")
	local start = if type(x) == "number" and type(z) == "number"
		then Vector2.new(x, z)
		else randomSpot(nil) or (World.ParkMin + World.ParkMax) / 2
	local _, size = model:GetBoundingBox()
	local pet: Pet = {
		key = key,
		uid = entry.Name,
		model = model,
		position = start,
		yaw = rng:NextNumber(0, math.pi * 2),
		target = nil,
		waitUntil = os.clock() + rng:NextNumber(0.5, 2.5),
		nextHappy = os.clock() + rng:NextNumber(HAPPY_EVERY.Min, HAPPY_EVERY.Max),
		speed = WALK_SPEED * math.clamp(size.Y / 3.6, 0.8, 1.6),
		phase = rng:NextNumber(0, 6),
		idle = nil,
		walk = nil,
		happy = nil,
		walking = false,
		animated = false,
	}
	tag(model, entry:GetAttribute("Income") or 0)
	if owned then
		addPickup(model, entry.Name)
	end
	pivot(park, pet, 0)
	model.Parent = park.folder
	pet.idle = loadTrack(model, def.Model, "Idle")
	pet.walk = loadTrack(model, def.Model, "Walk")
	pet.happy = loadTrack(model, def.Model, "Happy")
	pet.animated = pet.idle ~= nil or pet.walk ~= nil
	if pet.idle then
		pet.idle:Play()
	end
	if fresh then
		-- Just let out or hatched: a little pop (and a cheer when it has the clip).
		local s = model:GetScale()
		model:ScaleTo(s * 0.3)
		task.spawn(function()
			for i = 1, 8 do
				task.wait(1 / 60)
				if model.Parent then
					model:ScaleTo(s * (0.3 + 0.7 * i / 8 + math.sin(i / 8 * math.pi) * 0.25))
				end
			end
			if model.Parent then
				model:ScaleTo(s)
			end
		end)
		if pet.happy then
			pet.happy:Play(0.1)
			pet.waitUntil = os.clock() + 1.2
		end
	end
	park.pets[key] = pet
end

local function entryKey(entry: Instance): string
	return `{entry.Name}:{entry:GetAttribute("PetId")}`
end

local function sync(park: Park, base: Instance, initial: boolean)
	local folder = base:FindFirstChild("Pets")
	local owned = folder ~= nil and folder:GetAttribute("OwnerUserId") == player.UserId
	local wanted: { [string]: Folder } = {}
	if folder then
		for _, entry in folder:GetChildren() do
			if entry:IsA("Folder") and entry:GetAttribute("PetId") then
				wanted[entryKey(entry)] = entry
			end
		end
	end
	for key, pet in park.pets do
		if not wanted[key] then
			pet.model:Destroy()
			park.pets[key] = nil
		end
	end
	for key, entry in wanted do
		local pet = park.pets[key]
		if not pet then
			spawnPet(park, key, entry, not initial, owned)
		else
			local income = entry:GetAttribute("Income") or 0
			if pet.model:GetAttribute("Income") ~= income then
				pet.model:SetAttribute("Income", income)
				local t = pet.model:FindFirstChild("Tag")
				local cash = t and t:FindFirstChild("Cash") :: TextLabel?
				if cash then
					cash.Text = `+{Format.cash(income)}/s`
				end
			end
		end
	end
end

local function watchBase(index: number, base: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Park" .. index
	folder.Parent = root
	local park: Park = { index = index, cframe = World.baseCFrame(index), pets = {}, active = true, folder = folder }
	parks[index] = park
	local pending = false
	local function schedule()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			sync(park, base, false)
		end)
	end
	local function hook(pets: Instance)
		pets.ChildAdded:Connect(schedule)
		pets.ChildRemoved:Connect(schedule)
		pets:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			-- A new owner: rebuild so prompts follow ownership.
			for key, pet in park.pets do
				pet.model:Destroy()
				park.pets[key] = nil
			end
			schedule()
		end)
		for _, e in pets:GetChildren() do
			e:GetAttributeChangedSignal("Income"):Connect(schedule)
		end
		pets.ChildAdded:Connect(function(e)
			e:GetAttributeChangedSignal("Income"):Connect(schedule)
		end)
	end
	sync(park, base, true)
	base.ChildAdded:Connect(function(child)
		if child.Name == "Pets" then
			hook(child)
			schedule()
		end
	end)
	base.ChildRemoved:Connect(function(child)
		if child.Name == "Pets" then
			schedule()
		end
	end)
	local current = base:FindFirstChild("Pets")
	if current then
		hook(current)
	end
end

local function setActive(park: Park, active: boolean)
	if park.active == active then
		return
	end
	park.active = active
	park.folder.Parent = if active then root else nil
	if active then
		for _, pet in park.pets do
			pet.walking = false
			if pet.idle then
				pet.idle:Play()
			end
		end
	end
end

local function step(park: Park, dt: number, now: number)
	for _, pet in park.pets do
		if pet.happy and pet.happy.IsPlaying then
			pivot(park, pet, 0)
			continue
		end
		if now >= pet.nextHappy and not pet.walking then
			pet.nextHappy = now + rng:NextNumber(HAPPY_EVERY.Min, HAPPY_EVERY.Max)
			if pet.happy then
				pet.happy:Play(0.1)
				continue
			end
		end
		local target = pet.target
		if target then
			local delta = target - pet.position
			local dist = delta.Magnitude
			if dist < 0.3 then
				pet.target = nil
				pet.waitUntil = now + rng:NextNumber(IDLE_TIME.Min, IDLE_TIME.Max)
				setWalking(pet, false)
			else
				local dir = delta / dist
				local want = math.atan2(-dir.X, -dir.Y)
				pet.yaw = lerpAngle(pet.yaw, want, math.min(1, dt * TURN_SPEED))
				pet.position += dir * math.min(dist, pet.speed * dt)
				setWalking(pet, true)
			end
		elseif now >= pet.waitUntil then
			pet.target = randomSpot(pet.position)
			if not pet.target then
				pet.waitUntil = now + 1
			end
		end
		-- No clips yet: a little hop while walking, a slow breathe-bob standing still.
		local hop = 0
		if not pet.animated then
			pet.phase += dt * (if pet.walking then 10 else 2)
			hop = if pet.walking then math.abs(math.sin(pet.phase)) * 0.6 else (math.sin(pet.phase) + 1) * 0.04
		end
		pivot(park, pet, hop)
	end
end

-- Egg timers in every park: rarity on top, time left (then READY!) under it.
local function eggsTick()
	local now = State.now()
	for _, park in parks do
		local base = Workspace:FindFirstChild("Mountain")
		base = base and base:FindFirstChild("Summit")
		base = base and base:FindFirstChild("Bases")
		base = base and base:FindFirstChild("Base" .. park.index)
		local eggs = base and base:FindFirstChild("Eggs")
		for _, egg in (if eggs then eggs:GetChildren() else {}) do
			if egg:IsA("BasePart") then
				local labels = eggLabels[egg]
				if not labels then
					local g = Instance.new("BillboardGui")
					g.Size = UDim2.fromOffset(120, 52)
					g.StudsOffset = Vector3.new(0, 3.4, 0)
					g.MaxDistance = 80
					g.LightInfluence = 0
					local rarity =
						Ui.label({ Size = UDim2.new(1, 0, 0.45, 0), Text = tostring(egg:GetAttribute("Rarity") or "") })
					C.InventoryController.colorText(rarity, tostring(egg:GetAttribute("Rarity") or "Common"))
					rarity.Parent = g
					local text =
						Ui.label({ Size = UDim2.new(1, 0, 0.55, 0), Position = UDim2.fromScale(0, 0.45), Text = "" })
					text.Parent = g
					g.Parent = egg
					labels = { text = text, rarity = rarity }
					eggLabels[egg] = labels
					egg.Destroying:Connect(function()
						eggLabels[egg] = nil
					end)
				end
				local left = (egg:GetAttribute("EndsAt") or 0) - now
				local l = labels :: any
				l.text.Text = if left > 0 then Format.time(left) else "READY!"
				l.text.TextColor3 = if left > 0 then Ui.Colors.Snow else Ui.Colors.Green
			end
		end
	end
end

-- A puff where something was just put down.
function PetWorldController:Poof(at: Vector3)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.2, 2, 2)
	p.CFrame = CFrame.new(at + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 255, 255)
	p.Transparency = 0.2
	p.Parent = Workspace
	TweenService
		:Create(p, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Size = Vector3.new(0.2, 9, 9), Transparency = 1 })
		:Play()
	task.delay(0.5, function()
		p:Destroy()
	end)
end

function PetWorldController:Init(controllers)
	C = controllers
	root = Instance.new("Folder")
	root.Name = "PetParks"
	root.Parent = Workspace
end

function PetWorldController:Start()
	local bases = Workspace:WaitForChild("Mountain"):WaitForChild("Summit"):WaitForChild("Bases")
	for i = 1, World.BaseCount do
		task.spawn(function()
			local base = bases:WaitForChild("Base" .. i, 60)
			if base then
				watchBase(i, base)
			end
		end)
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		local focus = if camera then camera.Focus.Position else Vector3.zero
		local now = os.clock()
		for _, park in parks do
			local near = (park.cframe.Position - focus).Magnitude < ACTIVE_DISTANCE
			setActive(park, near)
			if near then
				step(park, dt, now)
			end
		end
		acc += dt
		if acc > 0.25 then
			acc = 0
			eggsTick()
		end
	end)
end

return PetWorldController
