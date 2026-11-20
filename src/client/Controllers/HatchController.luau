--!strict
-- Eggs growing in the pet parks, and opening them: Sweep the World's hatch show, ported
-- step for step (Dev 2026-11-20: "rebuild their systems with everything") with the egg
-- bursting into ice instead of bricks. Also the welcome-back card for offline cash.
--
-- Growing (every park, every player): an egg starts smaller and grows until it's ready.
-- It wobbles now and then, more often and harder as it gets close; a ready egg keeps
-- wobbling hard.
--
-- Opening, when you're near the egg: the egg floats up over a glowing ring and wobbles, ice
-- chips off it and a rarity name over it climbs up the rarities (one step per wobble) until
-- it reaches what's inside. Then it charges (swells, turns white, light leaks out of the
-- cracks, sparks get sucked in), bursts into flying ice with a shockwave, the pets roll
-- (case-opening style), and the real one pops out with a sunburst behind it and its card.
-- The rarer the pet, the bigger the show (TIERS): a star flash from Rare, an energy swirl
-- from Epic, a light pillar and orbiting stars from Legendary, an ice crown, confetti rain
-- and a dimmed world from Mythic. Meshes are ours (art/blender/hatch_vfx.py, HatchFx).
-- Far from your base the same show plays in a window. Click or tap to skip ahead.
-- Others near a hatch see a short version at that base (HatchShown).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local HatchFx = require(Client.HatchFx)
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggLook = require(Shared.EggLook)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local PetLook = require(Shared.PetLook)
local PetStats = require(Shared.PetStats)
local Pets = require(Shared.Config.Pets)
local Products = require(Shared.Config.Products)
local World = require(Shared.Config.World)

local WORLD_RANGE = 140 -- studs from the egg to open it in the world (else in a window)
local GROW_RANGE = 220 -- studs from the camera to animate growing eggs
local REVEAL_SECONDS = 2.6
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 214, 90)

local HatchController = {}

local C: any
local gui: ScreenGui
local stage: Frame
local stageScale: UIScale
local viewport: ViewportFrame
local worldModel: WorldModel
local rays: ImageLabel
local glow: ImageLabel
local flash: Frame
local card: Frame
local cardScale: UIScale
local rarityLabel: TextLabel
local nameLabel: TextLabel
local infoLabel: TextLabel
local newBadge: GuiObject
local hintLabel: TextLabel
local confetti: Frame
local welcome: Frame
local welcomeText: TextLabel
local queue = {}
local playing = false
-- Eggs opened while another show plays: the server takes them out of the park right away,
-- so a stand-in egg keeps sitting (and wobbling) on the spot until its own show starts.
local waiting: { [any]: Model } = {}
local skipRequested = false
-- Undo steps for the show that's playing, so a show that errors halfway doesn't leave the
-- camera rig, the dimmed world or its effects behind.
local cleanups: { () -> () } = {}

local function cleanUp()
	for i = #cleanups, 1, -1 do
		pcall(cleanups[i])
	end
	table.clear(cleanups)
end

local function screenScale(): number
	local cam = Workspace.CurrentCamera
	if not cam then
		return 1
	end
	local v = cam.ViewportSize
	return math.clamp(math.min(v.X / 1280, v.Y / 720) * 1.05, 0.62, 1.25)
end

------------------------------------------------------------------ small helpers

local function waitOrSkip(seconds: number)
	local deadline = os.clock() + seconds
	while os.clock() < deadline and not skipRequested do
		task.wait()
	end
end

-- Runs fn(alpha 0-1) every frame for `seconds` (cut short by a skip unless `always`).
local function animate(seconds: number, fn: (number) -> (), always: boolean?)
	local start = os.clock()
	while true do
		local alpha = math.clamp((os.clock() - start) / math.max(seconds, 0.001), 0, 1)
		if skipRequested and not always then
			alpha = 1
		end
		fn(alpha)
		if alpha >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

local function backOut(t: number): number
	local s = 1.9
	t -= 1
	return t * t * ((s + 1) * t + s) + 1
end

type PartLook = { part: BasePart, color: Color3, material: Enum.Material, texture: string? }

-- Remembers each part's look, so an egg can fade to white.
local function looks(model: Model): { PartLook }
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			table.insert(list, {
				part = d,
				color = d.Color,
				material = d.Material,
				texture = if d:IsA("MeshPart") then d.TextureID else nil,
			})
		end
	end
	return list
end

local function whiten(list: { PartLook }, t: number)
	for _, look in list do
		look.part.Color = look.color:Lerp(WHITE, t)
		if t > 0.55 and look.part.Material ~= Enum.Material.Neon then
			look.part.Material = Enum.Material.Neon
			look.part.Transparency = 0
			if look.texture and look.part:IsA("MeshPart") then
				look.part.TextureID = ""
			end
			-- Painted-on looks would hide the white glow.
			for _, child in look.part:GetChildren() do
				if child:IsA("SurfaceAppearance") or child:IsA("Decal") or child:IsA("Texture") then
					child:Destroy()
				end
			end
		end
	end
end

local function rarityOf(name: string?): Eggs.RarityDef
	return Eggs.ByName[name or ""] or Eggs.Rarities[1]
end

-- The show's glow colour: Secret's near-black reads as a bright violet light instead.
local SECRET_GLOW = Color3.fromRGB(205, 150, 255)
local function col(def: Eggs.RarityDef): Color3
	return if def.Name == "Secret" then SECRET_GLOW else def.Color
end

local function orderOf(name: string?): number
	return rarityOf(name).Order
end

-- A pet model from PetLook with its feet as the pivot (an invisible PrimaryPart box keeps
-- it, like PetWorldController), so ScaleTo / PivotTo keep it standing on the ground.
local function petModel(info): Model?
	local model = PetLook.make(
		info.PetId,
		info.Mutation,
		info.Huge,
		PetStats.sizeMult({
			Id = info.PetId,
			Weight = info.Weight,
			Huge = info.Huge,
		})
	)
	if not model then
		return nil
	end
	model:PivotTo(CFrame.new())
	local cf, size = model:GetBoundingBox()
	local box = Instance.new("Part")
	box.Name = "Hit"
	box.Size = size
	box.CFrame = cf
	box.Transparency = 1
	box.Parent = model
	model.PrimaryPart = box
	box.PivotOffset = box.CFrame:ToObjectSpace(CFrame.new(cf.X, cf.Y - size.Y / 2, cf.Z))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	return model
end

local function petName(info): string
	return PetStats.name({ Id = info.PetId, Mutation = info.Mutation, Huge = info.Huge })
end

-- Sparkles flying out from a point on screen.
local function burstConfetti(at: Vector2, color: Color3, count: number)
	local sc = screenScale()
	for i = 1, count do
		local piece = Instance.new("ImageLabel")
		piece.BackgroundTransparency = 1
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Image = if i % 2 == 0 then Ui.Images.Fx_Sparkle else Ui.Images.Fx_Flake
		piece.Position = UDim2.fromOffset(at.X, at.Y)
		local size = math.random(16, 36) * sc
		piece.Size = UDim2.fromOffset(size, size)
		local pick = i % 3
		piece.ImageColor3 = if pick == 0 then color elseif pick == 1 then WHITE else GOLD
		piece.Rotation = math.random(0, 90)
		piece.Parent = confetti
		local angle = math.random() * math.pi * 2
		local dist = math.random(140, 380) * sc
		local goal = at + Vector2.new(math.cos(angle) * dist, math.sin(angle) * dist * 0.8 + 60)
		local time = math.random(55, 95) / 100
		TweenService:Create(piece, TweenInfo.new(time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(goal.X, goal.Y),
			Rotation = piece.Rotation + math.random(-180, 180),
		}):Play()
		TweenService:Create(
			piece,
			TweenInfo.new(time * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, time * 0.5),
			{
				ImageTransparency = 1,
				Size = UDim2.fromOffset(size * 0.3, size * 0.3),
			}
		):Play()
		task.delay(time + 0.1, function()
			piece:Destroy()
		end)
	end
end

local function flashScreen(strength: number, seconds: number)
	flash.BackgroundTransparency = 1 - strength
	TweenService:Create(flash, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end

local function myBaseIndex(): number?
	local index = Players.LocalPlayer:GetAttribute("BaseIndex")
	return if type(index) == "number" and index > 0 then index else nil
end

-- Where your pet park is on screen (the window-mode pet flies there after the reveal).
local function parkScreenPosition(): UDim2
	local camera = Workspace.CurrentCamera
	local index = myBaseIndex()
	if camera and index then
		local center = (World.ParkMin + World.ParkMax) / 2
		local world = World.baseCFrame(index) * Vector3.new(center.X, 2, center.Y)
		local point, visible = camera:WorldToViewportPoint(world)
		if visible then
			return UDim2.fromOffset(point.X, point.Y)
		end
	end
	return UDim2.fromScale(0.5, 1.2)
end

-- Where an egg sat in a park.
local function spotOf(index: number?, info): CFrame?
	if not index or type(info.X) ~= "number" or type(info.Z) ~= "number" then
		return nil
	end
	return World.baseCFrame(index) * CFrame.new(info.X, World.ParkTop, info.Z)
end

------------------------------------------------------------------ the card

local function showCard(info)
	local rarity = rarityOf(info.Rarity)
	local lucky = info.EggRarity and orderOf(info.Rarity) > orderOf(info.EggRarity)
	rarityLabel.Text = (if lucky then "LUCKY! " else "")
		.. string.upper((if info.Huge then "Huge " else "") .. info.Rarity)
	C.InventoryController.colorText(rarityLabel, info.Rarity)
	nameLabel.Text = "You hatched " .. petName(info) .. "!"
	C.InventoryController.colorText(nameLabel, info.Rarity)
	local kg = PetStats.kgText(info.Weight)
	infoLabel.Text =
		`<font color="#9FE0FF">{kg}</font>   <font color="#5CE07A">+{Format.cash(info.Income or 0)}/s</font>`
	newBadge.Visible = info.IsNew == true
	hintLabel.Text = if UserInputService.GamepadEnabled
		then "Press A to skip"
		elseif UserInputService.TouchEnabled then "Tap to skip"
		else "Click to skip"
	card.Visible = true
	local s = screenScale()
	cardScale.Scale = s * 0.6
	TweenService:Create(cardScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = s,
	}):Play()
	-- The ring glow behind the card takes the rarity colour.
	local strokeObj = card:FindFirstChild("Edge") :: UIStroke?
	if strokeObj then
		strokeObj.Color = if rarity.Name == "Secret" then WHITE else col(rarity)
	end
end

local function hideCard()
	local tween = TweenService:Create(cardScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Scale = 0.01,
	})
	tween:Play()
	tween.Completed:Wait()
	card.Visible = false
end

------------------------------------------------------------------ the show

type Scene = {
	world: boolean,
	parent: Instance,
	camera: Camera,
	origin: CFrame, -- where the egg rests (pivot at its bottom)
	fx: Folder?,
}

-- Spinning sunburst + glow behind the pet (world: a billboard just behind it).
local function worldRays(
	scene: Scene,
	center: Vector3,
	size: number,
	color: Color3
): (BillboardGui, ImageLabel, ImageLabel)
	local anchor = Instance.new("Part")
	anchor.Name = "RaysAnchor"
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	local back = (center - scene.camera.CFrame.Position).Unit
	anchor.CFrame = CFrame.new(center + back * size * 0.6)
	anchor.Parent = scene.parent
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(size * 2.6, size * 2.6)
	board.LightInfluence = 0
	board.Adornee = anchor
	board.Parent = anchor
	local g = Instance.new("ImageLabel")
	g.BackgroundTransparency = 1
	g.Size = UDim2.fromScale(0.8, 0.8)
	g.Position = UDim2.fromScale(0.5, 0.5)
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Image = Ui.Images.Fx_Glow
	g.ImageColor3 = color
	g.ImageTransparency = 1
	g.Parent = board
	local r = Instance.new("ImageLabel")
	r.BackgroundTransparency = 1
	r.Size = UDim2.fromScale(1, 1)
	r.Image = Ui.Images.Fx_Rays
	r.ImageColor3 = color
	r.ImageTransparency = 1
	r.Parent = board
	return board, r, g
end

local function sparkleBurst(scene: Scene, at: Vector3, color: Color3, count: number)
	local anchor = Instance.new("Part")
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = scene.parent
	local holder = Instance.new("Attachment")
	holder.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = Ui.Images.Fx_Sparkle
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.4, color),
		ColorSequenceKeypoint.new(1, color),
	})
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.3) })
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(10, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -18, 0)
	emitter.Drag = 2
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-200, 200)
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(count)
	task.delay(1.6, function()
		anchor:Destroy()
	end)
end

-- Case-opening roll in 3D: pets of the egg's rarity (plus a few teasers from the rarities
-- around it) pop in and out where the egg opened, each a bit longer than the last, with a
-- tick. A click jumps to the end. The real pet comes right after.
local function rollPick(rarity: string): string?
	local order = orderOf(rarity)
	local r = math.random()
	local target = rarity
	if r < 0.2 and Eggs.Rarities[order + 1] then
		target = Eggs.Rarities[order + 1].Name
	elseif r < 0.35 and Eggs.Rarities[order - 1] then
		target = Eggs.Rarities[order - 1].Name
	end
	local bucket = Pets.ByRarity[target] or Pets.ByRarity[rarity]
	if not bucket or #bucket == 0 then
		return nil
	end
	return bucket[math.random(1, #bucket)].Id
end

local function rollPets(scene: Scene, info, face: CFrame, count: number, onPet: ((Color3) -> ())?)
	local light = Instance.new("Part")
	light.Anchored = true
	light.CanCollide = false
	light.CanQuery = false
	light.Transparency = 1
	light.Size = Vector3.new(0.2, 0.2, 0.2)
	light.CFrame = face * CFrame.new(0, 2, 0)
	light.Parent = scene.parent
	local glowLight = Instance.new("PointLight")
	glowLight.Brightness = 4
	glowLight.Range = 12
	glowLight.Parent = light
	local last: string? = nil
	for k = 1, count do
		if skipRequested then
			break
		end
		local id = rollPick(info.Rarity) or info.PetId
		if id == last then
			id = rollPick(info.Rarity) or id
		end
		last = id
		local def = Pets.ById[id]
		local color = col(rarityOf(if def then def.Rarity else info.Rarity))
		glowLight.Color = color
		if onPet then
			onPet(color)
		end
		local pet = petModel({ PetId = id, Mutation = info.Mutation })
		if pet then
			local h = Instance.new("Highlight")
			h.FillTransparency = 1
			h.OutlineColor = color
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Parent = pet
			local turn = CFrame.Angles(0, math.rad(math.random(-25, 25)), 0)
			pet:PivotTo(face * turn)
			pet.Parent = scene.parent
			local base = pet:GetScale()
			Ui.sound("Tap", 0.85 + k / count * 0.6)
			-- Each pet stays a little longer than the one before (fast flicker, then slow).
			local hold = 0.06 + 0.3 * (k / count) ^ 2.2
			local pop = math.min(0.08, hold * 0.5)
			animate(pop, function(t)
				pet:ScaleTo(math.max(0.05, base * (0.6 + 0.4 * backOut(t))))
			end, true)
			waitOrSkip(hold - pop)
			pet:Destroy()
		end
	end
	light:Destroy()
end

-- How big a show each pet rarity gets (Eggs order 1-7). Huge pets and mutations get one more.
type Tier = {
	wobbles: number, -- shakes before the burst (the rarity climb steps through them)
	shards: number, -- ice pieces the egg bursts into
	rings: number, -- shockwaves at the burst
	swirl: boolean, -- energy ribbon around the egg
	star: boolean, -- star flash at the burst
	pillar: boolean, -- light pillar to the sky
	crown: boolean, -- ice crown out of the ground
	darken: boolean, -- the world goes dim while it charges
	stars: number, -- stars orbiting the revealed pet
	rain: boolean, -- confetti rain over the pet
	charge: number, -- seconds of charging
}
-- Same tiers as Sweep the World (toned down there on 2026-10-29).
local TIERS: { Tier } = {
	{
		wobbles = 3,
		shards = 8,
		rings = 1,
		swirl = false,
		star = false,
		pillar = false,
		crown = false,
		darken = false,
		stars = 0,
		rain = false,
		charge = 0.5,
	},
	{
		wobbles = 3,
		shards = 9,
		rings = 1,
		swirl = false,
		star = false,
		pillar = false,
		crown = false,
		darken = false,
		stars = 0,
		rain = false,
		charge = 0.55,
	},
	{
		wobbles = 3,
		shards = 11,
		rings = 1,
		swirl = false,
		star = true,
		pillar = false,
		crown = false,
		darken = false,
		stars = 0,
		rain = false,
		charge = 0.65,
	},
	{
		wobbles = 4,
		shards = 13,
		rings = 2,
		swirl = true,
		star = true,
		pillar = false,
		crown = false,
		darken = false,
		stars = 0,
		rain = false,
		charge = 0.75,
	},
	{
		wobbles = 4,
		shards = 15,
		rings = 2,
		swirl = true,
		star = true,
		pillar = true,
		crown = false,
		darken = false,
		stars = 3,
		rain = false,
		charge = 0.9,
	},
	{
		wobbles = 5,
		shards = 17,
		rings = 2,
		swirl = true,
		star = true,
		pillar = true,
		crown = true,
		darken = true,
		stars = 4,
		rain = true,
		charge = 1.05,
	},
	{
		wobbles = 5,
		shards = 19,
		rings = 3,
		swirl = true,
		star = true,
		pillar = true,
		crown = true,
		darken = true,
		stars = 5,
		rain = true,
		charge = 1.2,
	},
}

-- A rarity name floating over the egg that climbs up the rarities while it shakes.
local function climbLabel(scene: Scene, at: Vector3, width: number): (Part, TextLabel)
	local anchor = Instance.new("Part")
	anchor.Name = "ClimbAnchor"
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = scene.parent
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(width, width * 0.22)
	board.LightInfluence = 0
	board.AlwaysOnTop = true
	board.Adornee = anchor
	board.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.FontFace = Ui.FontBlack
	label.TextScaled = true
	label.Text = ""
	label.TextColor3 = WHITE
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(22, 20, 38)
	stroke.Parent = label
	label.Parent = board
	return anchor, label
end

local function play(info)
	playing = true
	Ui.closeOpenWindow()
	local standIn = waiting[info]
	if standIn then
		waiting[info] = nil
		standIn:Destroy()
	end
	skipRequested = false
	local rarity = rarityOf(info.Rarity)
	local eggRarity = info.EggRarity or info.Rarity
	local order = rarity.Order
	local special = info.Huge == true or info.Mutation ~= nil
	local power = math.clamp(order + (if special then 1 else 0), 1, #TIERS)
	local tier = TIERS[power]
	local big = special or order >= rarityOf("Epic").Order
	local quick = #queue > 0 -- more eggs waiting: a shorter show
	local tempo = if quick then 0.55 else 1

	-- World or window?
	local camera = Workspace.CurrentCamera :: Camera
	local spot = spotOf(myBaseIndex(), info)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local inWorld = spot ~= nil
		and root ~= nil
		and (root.Position - spot.Position).Magnitude < WORLD_RANGE
		and not Ui.reducedMotion()

	local scene: Scene
	if inWorld then
		local fx = Instance.new("Folder")
		fx.Name = "HatchShow"
		fx.Parent = Workspace
		table.insert(cleanups, function()
			fx:Destroy()
		end)
		scene = { world = true, parent = fx, camera = camera, origin = spot :: CFrame, fx = fx }
		stage.Visible = false
	else
		worldModel:ClearAllChildren()
		scene = { world = false, parent = worldModel, camera = viewport.CurrentCamera :: Camera, origin = CFrame.new() }
		stage.Visible = true
		stage.Position = UDim2.fromScale(0.5, 0.45)
		stageScale.Scale = screenScale() * 0.3
		TweenService:Create(stageScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = screenScale() }):Play()
		rays.ImageColor3 = col(rarity)
		glow.ImageColor3 = col(rarity)
		rays.ImageTransparency = 1
		glow.ImageTransparency = 1
	end
	card.Visible = false
	gui.Enabled = true

	-- 1. The egg (a local copy where the real one sat; the server already took that away).
	local egg = EggLook.make(eggRarity)
	egg.Name = "OpeningEgg"
	local eggLooks = looks(egg)
	egg:PivotTo(scene.origin)
	egg.Parent = scene.parent
	local eggScale = egg:GetScale()
	local _, eggSize = egg:GetBoundingBox()
	local eggHeight = math.max(eggSize.Y, 1.5)
	local eggWidth = math.max(eggSize.X, eggSize.Z, 1)
	local shardScale = eggHeight / 3.5
	local hover = eggHeight * 0.22 -- the egg floats up this far before it bursts
	local lifted = scene.origin * CFrame.new(0, hover, 0)
	local focus = scene.origin.Position + Vector3.new(0, hover + eggHeight * 0.5, 0)
	local floorY = scene.origin.Position.Y
	local light = Instance.new("PointLight")
	light.Color = col(rarityOf(eggRarity))
	light.Brightness = 0
	light.Range = eggHeight * 5
	light.Parent = egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
	local highlight: Highlight? = nil
	if scene.world then
		local h = Instance.new("Highlight")
		h.FillColor = WHITE
		h.FillTransparency = 1
		h.OutlineTransparency = 1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Adornee = egg
		h.Parent = egg
		highlight = h
	end

	-- The camera stays yours (Sweep: Dev didn't want it taken away); it only shakes.
	local rig: HatchFx.Rig? = nil
	if scene.world and not Ui.reducedMotion() then
		local ignore: { Instance } = { scene.parent }
		if character then
			table.insert(ignore, character)
		end
		local r = HatchFx.cameraRig(focus, math.clamp(eggHeight * 3.1, 9, 22), ignore)
		rig = r
		table.insert(cleanups, r.stop)
		r.weight(0, 0.01)
	else
		scene.camera.CFrame =
			CFrame.lookAt(Vector3.new(0, eggHeight * 0.85, -eggHeight * 2.9), Vector3.new(0, eggHeight * 0.6, 0))
	end

	-- 2. Lift off: snow puffs, a glowing ring on the ground, the egg floats up.
	local groundRing = HatchFx.mesh("VfxHatchRing")
	if groundRing then
		groundRing.Material = Enum.Material.Neon
		groundRing.Color = col(rarityOf("Common"))
		groundRing.Transparency = 1
		groundRing.Parent = scene.parent
	end
	local ringColor = col(rarityOf("Common"))
	local ringSpin = 0
	local ringPulse = 0
	local ringFade = 0
	HatchFx.run(function(dt)
		if not groundRing or not groundRing.Parent then
			return false
		end
		ringSpin += dt * 1.5
		ringPulse = math.max(0, ringPulse - dt * 3)
		local r = eggWidth * (0.85 + 0.25 * ringPulse)
		groundRing.Size = Vector3.new(r * 2, 0.35, r * 2)
		groundRing.CFrame = scene.origin * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, ringSpin, 0)
		groundRing.Color = ringColor
		groundRing.Transparency = 0.15 + 0.85 * ringFade
		return true
	end)
	if scene.world then
		HatchFx.dust(scene.parent, scene.origin.Position + Vector3.new(0, 0.2, 0), eggWidth * 0.6, 10)
	end
	Ui.sound("HatchLift")
	animate(0.45 * tempo, function(t)
		local up = backOut(t)
		egg:PivotTo(scene.origin * CFrame.new(0, hover * up, 0) * CFrame.Angles(0, t * math.pi * 0.5, 0))
	end, true)
	egg:PivotTo(lifted)

	-- 3. Wobbles, each harder than the last. Ice chips off and the name climbs up the
	-- rarities, one step per wobble, until it reaches what's inside.
	local setLeak, removeLeak = HatchFx.lightLeak(scene.parent, focus, eggHeight * 0.75)
	local setSwirl: ((number, number, Color3) -> ())? = nil
	local removeSwirl: (() -> ())? = nil
	local climbAnchor: Part? = nil
	local climbText: TextLabel? = nil
	if scene.world then
		climbAnchor, climbText =
			climbLabel(scene, focus + Vector3.new(0, eggHeight * 0.85, 0), math.max(6, eggWidth * 2.6))
	end
	local wobbles = if quick then 2 else tier.wobbles
	local climbColor = col(rarityOf("Common"))
	for i = 1, wobbles do
		if skipRequested then
			break
		end
		local step = math.max(1, math.ceil(i / wobbles * order))
		local stepDef = Eggs.Rarities[step] or rarity
		climbColor = col(stepDef)
		ringColor = climbColor
		ringPulse = 1
		light.Color = climbColor
		light.Brightness = 1 + 4 * i / wobbles
		if climbText then
			local label = climbText :: TextLabel
			label.Text = string.upper(stepDef.Name) .. (if i < wobbles then "?" else "!")
			label.TextColor3 = climbColor
			label.TextTransparency = 0
			label.Rotation = math.random(-6, 6)
			label.Size = UDim2.fromScale(1.35, 1.35)
			TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.fromScale(1, 1),
			}):Play()
		end
		Ui.sound("Wobble", 0.9 + i * 0.1)
		Ui.sound("HatchTier", 0.75 + step * 0.12)
		Ui.sound("HatchChip", 0.9 + math.random() * 0.3)
		HatchFx.shockwave(scene.parent, scene.origin, climbColor, eggWidth * (1.1 + i * 0.12), 0.4, 0.25)
		HatchFx.shards(scene.parent, focus, floorY, eggRarity, if i >= 2 then 1 else 0, 12 + i * 2, shardScale * 0.8)
		if tier.swirl and i == 2 then
			setSwirl, removeSwirl = HatchFx.swirl(scene.parent, scene.origin, eggWidth * 0.95, eggHeight * 1.5)
		end
		if setSwirl then
			setSwirl(2 + i * 1.2, 0, climbColor)
		end
		if rig then
			rig.shake(0.02 + 0.01 * i, 0.25)
		end
		local amp = math.rad(8 + i * 5)
		local length = 0.36 * tempo
		animate(length, function(t)
			local fade = 1 - t
			local angle = math.sin(t * math.pi * 6) * amp * fade
			local hop = math.sin(t * math.pi) * eggHeight * 0.06 * i
			egg:PivotTo(lifted * CFrame.new(0, hop, 0) * CFrame.Angles(angle * 0.4, 0, angle))
		end)
		egg:PivotTo(lifted)
		waitOrSkip((0.24 - math.min(i, 5) * 0.025) * tempo)
	end
	if climbText then
		local label = climbText :: TextLabel
		label.Text = (if order > orderOf(eggRarity) then "LUCKY " else "") .. string.upper(rarity.Name) .. "!"
		label.TextColor3 = col(rarity)
		label.TextTransparency = 0
	end
	climbColor = col(rarity)
	ringColor = climbColor

	-- 4. Charge: swells up, shakes, turns white, light pours out of the cracks, sparks get
	-- sucked in. Legendary and up: a pillar of light to the sky; Mythic and up: the world dims.
	Ui.sound("Charge")
	Ui.sound("HatchRise")
	local stopSuck: (() -> ())? = nil
	local undim: (() -> ())? = nil
	local endPillar: (() -> ())? = nil
	if scene.world then
		stopSuck = HatchFx.suckIn(scene.parent, focus, eggHeight * 1.4, climbColor, 12 + power * 5)
		if tier.darken and not quick then
			local u = HatchFx.darken(climbColor, tier.charge)
			undim = u
			table.insert(cleanups, u)
		end
	end
	if tier.pillar and not quick then
		Ui.sound("HatchSuck")
		-- Thin (narrower than the egg) so the egg turning white stays visible around it.
		endPillar = HatchFx.pillar(
			scene.parent,
			scene.origin,
			eggWidth * 0.22,
			if scene.world then 120 else eggHeight * 4,
			climbColor
		)
	end
	if tier.crown and not quick then
		HatchFx.crown(scene.parent, scene.origin, eggWidth * 1.15, eggHeight * 0.7, climbColor)
	end
	animate(tier.charge * tempo, function(t)
		local shake = math.rad(4 + power) * t
		egg:ScaleTo(eggScale * (1 + 0.38 * t * t))
		egg:PivotTo(
			lifted
				* CFrame.Angles(math.random(-100, 100) / 100 * shake, t * t * 6, math.random(-100, 100) / 100 * shake)
		)
		whiten(eggLooks, t)
		light.Brightness = 5 + 6 * t
		setLeak(0.3 + 0.6 * t, climbColor)
		if setSwirl then
			setSwirl(6 + 14 * t, t, climbColor)
		end
		if highlight then
			highlight.FillTransparency = 1 - t * 0.9
		end
		if rig then
			rig.shake(0.03 + 0.08 * t * (power / 7), 0.2)
		end
		if not scene.world then
			glow.ImageTransparency = 1 - t * 0.7
		end
	end, true)

	-- 5. Burst! The egg shatters into ice: shockwaves, a star flash, sparks, snowflakes.
	Ui.sound("HatchShatter")
	Ui.sound("Shatter")
	Ui.sound("Hatch")
	if power >= 3 then
		Ui.sound("HatchBoom")
	end
	flashScreen(if big then 0.7 else 0.45, if big then 0.7 else 0.45)
	if stopSuck then
		stopSuck()
	end
	-- The beam closes at the burst so it never covers the pet roll or the reveal.
	if endPillar then
		endPillar()
		endPillar = nil
	end
	removeLeak()
	if removeSwirl then
		removeSwirl()
	end
	if climbAnchor then
		climbAnchor:Destroy()
	end
	ringPulse = 1.5
	local screenPoint = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y * 0.45)
	if scene.world then
		local point, visible = camera:WorldToViewportPoint(focus)
		if visible then
			screenPoint = Vector2.new(point.X, point.Y)
		end
		HatchFx.burst(scene.parent, focus, col(rarity), 14 + power * 5, 22 + power * 2)
	end
	for k = 1, tier.rings do
		local radius = math.max(8, eggHeight * 3) * (1 + (k - 1) * 0.4)
		task.delay((k - 1) * 0.09, function()
			HatchFx.shockwave(
				scene.parent,
				scene.origin,
				if k % 2 == 0 then WHITE else col(rarity),
				radius,
				0.55 + k * 0.08
			)
		end)
	end
	HatchFx.shards(scene.parent, focus, floorY, eggRarity, if quick then 6 else tier.shards, 18 + power * 2, shardScale)
	if tier.star then
		HatchFx.starFlash(scene.parent, focus, eggHeight * (0.9 + power * 0.1), col(rarity), scene.camera)
	end
	burstConfetti(screenPoint, col(rarity), if big then 18 else 10)
	if rig then
		rig.shake(0.12 + power * 0.03, 0.35)
	end
	egg:Destroy()

	local face: CFrame
	if scene.world then
		local look = Vector3.new(camera.CFrame.Position.X, scene.origin.Position.Y, camera.CFrame.Position.Z)
		face = CFrame.lookAt(scene.origin.Position, look)
	else
		face = CFrame.new() -- the window camera sits at -Z, in front of the pet
	end

	-- 5b. The roll: pets flick through where the egg was, slowing down, then the real one.
	if not quick and not Ui.reducedMotion() then
		rollPets(scene, info, face, if big then 18 else 13, function(color: Color3)
			ringColor = color
			ringPulse = 0.8
		end)
	end

	-- 6. The pet pops out, faces you and cheers.
	ringColor = col(rarity)
	ringPulse = 1.2
	local model = petModel(info) or Instance.new("Model")
	model:PivotTo(face)
	model.Parent = scene.parent
	local petScale = model:GetScale()
	local _, size3 = model:GetBoundingBox()
	model:ScaleTo(petScale * 0.05)
	local happy = C.PetWorldController.loadTrack(model, info.PetId, "Happy")
	local idle = C.PetWorldController.loadTrack(model, info.PetId, "Idle")
	if idle then
		idle:Play()
	end
	if happy then
		happy.Looped = true
		happy:Play(0.05)
	end
	HatchFx.shockwave(scene.parent, scene.origin, col(rarity), math.max(5, eggHeight * 1.8), 0.4, 0.25)
	animate(0.42, function(t)
		model:ScaleTo(math.max(petScale * 0.05, petScale * backOut(t)))
		model:PivotTo(face * CFrame.new(0, math.sin(t * math.pi) * 1.2, 0))
	end, true)
	model:PivotTo(face)
	local petSize = math.max(size3.X, size3.Y, size3.Z, 1.5)
	Ui.sound(if big then "RareReveal" else "Reveal")
	Ui.sound("Sparkle")
	if power >= 4 then
		Ui.sound("HatchShimmer")
	end
	if power >= 6 then
		Ui.sound("HatchGong")
	end

	-- Rays behind the pet; stars around it and confetti for the rare ones.
	local raysImage: ImageLabel
	local glowImage: ImageLabel
	local petCenter = scene.origin.Position + Vector3.new(0, size3.Y * 0.5, 0)
	if scene.world then
		local _, r, g = worldRays(scene, petCenter, petSize, col(rarity))
		raysImage, glowImage = r, g
		if tier.rain and not quick then
			HatchFx.confettiRain(
				scene.parent,
				petCenter + Vector3.new(0, petSize * 2.5 + 6, 0),
				petSize * 1.4,
				{ col(rarity), WHITE, GOLD },
				REVEAL_SECONDS
			)
		end
	else
		raysImage, glowImage = rays, glow
		scene.camera.CFrame =
			CFrame.lookAt(Vector3.new(petSize * 0.35, petSize * 0.7, -petSize * 2.4), Vector3.new(0, size3.Y * 0.45, 0))
	end
	local endStars: (() -> ())? = nil
	if tier.stars > 0 then
		endStars =
			HatchFx.orbitStars(scene.parent, petCenter, petSize * 0.85, col(rarity), if quick then 3 else tier.stars)
	end
	TweenService:Create(raysImage, TweenInfo.new(0.3), { ImageTransparency = if big then 0.15 else 0.35 }):Play()
	TweenService:Create(glowImage, TweenInfo.new(0.3), { ImageTransparency = 0.3 }):Play()
	local spin = RunService.RenderStepped:Connect(function(dt)
		raysImage.Rotation = (raysImage.Rotation + dt * 25) % 360
	end)

	skipRequested = false
	showCard(info)
	waitOrSkip(REVEAL_SECONDS * tempo)

	-- 7. Wrap up: the pet hops into the park (or your bag), the camera comes back.
	TweenService:Create(raysImage, TweenInfo.new(0.3), { ImageTransparency = 1 }):Play()
	TweenService:Create(glowImage, TweenInfo.new(0.3), { ImageTransparency = 1 }):Play()
	if endStars then
		endStars()
	end
	if undim then
		undim()
	end
	if rig then
		rig.orbit(0)
		rig.weight(0, 0.45)
	end
	HatchFx.over(0.4, function(a)
		ringFade = a
	end, function()
		if groundRing then
			groundRing:Destroy()
		end
	end)
	task.spawn(hideCard)
	if scene.world then
		Ui.sound("Pop")
		animate(0.3, function(t)
			model:ScaleTo(math.max(petScale * 0.02, petScale * (1 - t)))
			model:PivotTo(face * CFrame.new(0, t * 2, 0))
		end, true)
		model:Destroy()
		if info.Uid then
			C.PetWorldController:HidePet(info.Uid, false)
		end
		if info.Placed then
			sparkleBurst(scene, scene.origin.Position + Vector3.new(0, 1, 0), col(rarity), 12)
		end
		task.wait(0.2)
		task.delay(1.7, function()
			if scene.fx then
				scene.fx:Destroy()
			end
		end)
	else
		if info.Uid then
			C.PetWorldController:HidePet(info.Uid, false)
		end
		local fly = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(stage, fly, { Position = parkScreenPosition() }):Play()
		local shrink = TweenService:Create(stageScale, fly, { Scale = 0.05 })
		shrink:Play()
		shrink.Completed:Wait()
		worldModel:ClearAllChildren()
	end
	if not info.Placed then
		Ui.toast("Your base is full, so it went in your bag!", "Info")
	end
	if rig then
		local r = rig :: HatchFx.Rig
		task.delay(0.3, function()
			r.stop()
		end)
	end
	spin:Disconnect()
	stage.Visible = false
	gui.Enabled = false
	playing = false
end

local function pump()
	if playing then
		return
	end
	local info = table.remove(queue, 1)
	if info then
		task.spawn(function()
			local ok, err = pcall(play, info)
			if waiting[info] then
				waiting[info]:Destroy()
				waiting[info] = nil
			end
			if ok then
				table.clear(cleanups)
			else
				cleanUp()
				worldModel:ClearAllChildren()
				stage.Visible = false
				warn("[HatchController] " .. tostring(err))
				gui.Enabled = false
				card.Visible = false
				playing = false
				if info.Uid then
					C.PetWorldController:HidePet(info.Uid, false)
				end
			end
			pump()
		end)
	end
end

------------------------------------------------------------------ growing eggs

-- The server's egg parts (base.Eggs) grow from 60% to full size until they're ready and
-- wobble now and then: a little more often and harder as they get close, hard once ready.
type Growing = { cframe: CFrame, size: Vector3, nextWobble: number, wobbleAt: number }
local growing: { [BasePart]: Growing } = {}

local function updateGrowing()
	local camera = Workspace.CurrentCamera
	local bases = Workspace:FindFirstChild("Mountain")
	bases = bases and bases:FindFirstChild("Summit")
	bases = bases and bases:FindFirstChild("Bases")
	if not camera or not bases then
		return
	end
	local now = State.now()
	local clock = os.clock()
	local camPos = camera.CFrame.Position
	for _, base in bases:GetChildren() do
		local eggs = base:FindFirstChild("Eggs")
		if not eggs then
			continue
		end
		for _, egg in eggs:GetChildren() do
			if not egg:IsA("BasePart") then
				continue
			end
			local g = growing[egg]
			if not g then
				local entry: Growing = {
					cframe = egg.CFrame,
					size = egg.Size,
					nextWobble = clock + math.random() * 3,
					wobbleAt = -10,
				}
				growing[egg] = entry
				egg.Destroying:Once(function()
					growing[egg] = nil
				end)
				g = entry
			end
			local gg = g :: Growing
			if (gg.cframe.Position - camPos).Magnitude > GROW_RANGE then
				continue
			end
			local startsAt = egg:GetAttribute("StartsAt") or 0
			local endsAt = egg:GetAttribute("EndsAt") or 0
			local progress = if endsAt > startsAt then math.clamp((now - startsAt) / (endsAt - startsAt), 0, 1) else 1
			local grow = 0.6 + 0.4 * (1 - (1 - progress) ^ 2)
			local ready = progress >= 1
			if clock >= gg.nextWobble then
				gg.wobbleAt = clock
				local gap = if ready then 6 else 14 - 6 * progress
				gg.nextWobble = clock + gap * (0.7 + math.random() * 0.6)
			end
			local w = clock - gg.wobbleAt
			local rot = CFrame.new()
			if w < 0.5 then
				local amp = math.rad(if ready then 14 else 3 + 9 * progress)
				local angle = math.sin(w / 0.5 * math.pi * 4) * amp * (1 - w / 0.5)
				rot = CFrame.Angles(angle * 0.4, 0, angle)
			end
			local size = gg.size * grow
			local bottom = gg.cframe * CFrame.new(0, -gg.size.Y / 2, 0)
			egg.Size = size
			egg.CFrame = bottom * rot * CFrame.new(0, size.Y / 2, 0)
		end
	end
end

------------------------------------------------------------------ someone else's hatch

-- Someone else's hatch (Sweep: everyone should see hatches). A short, light version at
-- their base: the egg shakes and rises, bursts with a few shards and a ring (a light
-- pillar for Legendary+), and the pet pops out with its name for a moment. Only near you,
-- and at most a few at once, so it stays easy on phones.
local OTHER_RANGE = 70
local OTHER_MAX = 3
local othersPlaying = 0

local function playOther(info)
	local owner = Players:GetPlayerByUserId(info.UserId)
	local camera = Workspace.CurrentCamera
	if not owner or owner == Players.LocalPlayer or not camera or othersPlaying >= OTHER_MAX then
		return
	end
	local index = owner:GetAttribute("BaseIndex")
	local spot = spotOf(if type(index) == "number" then index else nil, info)
	if not spot then
		return
	end
	local me = Players.LocalPlayer.Character
	local myRoot = me and me:FindFirstChild("HumanoidRootPart") :: BasePart?
	local from = if myRoot then myRoot.Position else camera.CFrame.Position
	if (from - spot.Position).Magnitude > OTHER_RANGE then
		return
	end
	othersPlaying += 1
	if info.Uid then
		C.PetWorldController:HidePet(info.Uid, true)
	end
	local fx = Instance.new("Folder")
	fx.Name = "OtherHatch"
	fx.Parent = Workspace
	local ok, err = pcall(function()
		local rarity = rarityOf(info.Rarity)
		local special = info.Huge == true or info.Mutation ~= nil
		local power = math.clamp(rarity.Order + (if special then 1 else 0), 1, #TIERS)
		local tier = TIERS[power]
		local eggRarity = info.EggRarity or info.Rarity
		local egg = EggLook.make(eggRarity)
		looks(egg)
		egg:PivotTo(spot)
		egg.Parent = fx
		local ext = egg:GetExtentsSize()
		local eggHeight, eggWidth = ext.Y, ext.X
		local endPillar = if tier.pillar then HatchFx.pillar(fx, spot, eggWidth * 0.2, 50, col(rarity)) else nil
		animate(0.5 + 0.12 * power, function(t)
			local angle = math.sin(t * math.pi * 6) * math.rad(12) * (0.4 + 0.6 * t)
			egg:PivotTo(spot * CFrame.new(0, t * 1.2, 0) * CFrame.Angles(angle * 0.4, 0, angle))
		end, true)
		local focus = spot.Position + Vector3.new(0, 1.2 + eggHeight / 2, 0)
		egg:Destroy()
		HatchFx.burst(fx, focus, col(rarity), 8 + power * 2, 18)
		HatchFx.shockwave(fx, spot, col(rarity), math.max(6, eggHeight * 2.5), 0.5)
		HatchFx.shards(fx, focus, spot.Position.Y, eggRarity, math.ceil(tier.shards / 2), 16, eggHeight / 3.5)
		if endPillar then
			endPillar()
		end
		local face = CFrame.lookAt(
			spot.Position,
			Vector3.new(camera.CFrame.Position.X, spot.Position.Y, camera.CFrame.Position.Z)
		)
		local model = petModel(info)
		if not model then
			return
		end
		model:PivotTo(face)
		model.Parent = fx
		local petScale = model:GetScale()
		local _, size = model:GetBoundingBox()
		model:ScaleTo(petScale * 0.05)
		animate(0.35, function(t)
			model:ScaleTo(math.max(petScale * 0.05, petScale * backOut(t)))
		end, true)
		local board = Instance.new("BillboardGui")
		board.Size = UDim2.fromScale(7, 1.4)
		board.StudsOffsetWorldSpace = Vector3.new(0, size.Y + 1.2, 0)
		board.LightInfluence = 0
		board.MaxDistance = OTHER_RANGE
		board.Adornee = model.PrimaryPart
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.FontFace = Ui.FontBlack
		label.TextScaled = true
		label.Text = petName(info)
		C.InventoryController.colorText(label, info.Rarity)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Color = Color3.fromRGB(22, 20, 38)
		stroke.Parent = label
		label.Parent = board
		board.Parent = fx
		task.wait(2.2)
		animate(0.3, function(t)
			model:ScaleTo(math.max(petScale * 0.05, petScale * (1 - t)))
			label.TextTransparency = t
		end, true)
	end)
	if not ok then
		warn("[HatchController] other hatch: " .. tostring(err))
	end
	if info.Uid then
		C.PetWorldController:HidePet(info.Uid, false)
	end
	task.delay(1, function()
		fx:Destroy()
	end)
	othersPlaying -= 1
end

------------------------------------------------------------------ lifecycle

-- True while a hatch show is playing or more eggs are waiting for theirs.
function HatchController:IsBusy(): boolean
	return playing or #queue > 0
end

local function buildGui()
	gui = Ui.screen("Hatch", 30)
	gui.Enabled = false
	flash = Ui.frame({
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		ZIndex = 1,
	})
	flash.Parent = gui

	-- Window mode: the same show in a 3D window (far from your base).
	stage = Ui.frame({
		Name = "Stage",
		Size = UDim2.fromOffset(420, 420),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 2,
	})
	stageScale = Instance.new("UIScale")
	stageScale.Parent = stage
	glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.Image = Ui.Images.Fx_Glow
	glow.Size = UDim2.fromScale(1.1, 1.1)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.ZIndex = 2
	glow.Parent = stage
	rays = Instance.new("ImageLabel")
	rays.Name = "Rays"
	rays.BackgroundTransparency = 1
	rays.Image = Ui.Images.Fx_Rays
	rays.Size = UDim2.fromScale(1.3, 1.3)
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.ZIndex = 2
	rays.Parent = stage
	viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(200, 210, 230)
	viewport.LightColor = WHITE
	viewport.ZIndex = 3
	viewport.Parent = stage
	-- Animations only play inside a WorldModel.
	worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	stage.Parent = gui

	-- The card: rarity, "You hatched X!", kg and $/s, NEW!, and how to skip. It sits above
	-- the ROLL button and the hotbar.
	card = Ui.frame({
		Name = "Card",
		Size = UDim2.fromOffset(460, 118),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -190),
		BackgroundColor3 = Ui.Colors.PanelDark,
		BackgroundTransparency = 0.08,
		Visible = false,
		ZIndex = 5,
	})
	Ui.corner(card, 18)
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Thickness = 4
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = card
	cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	rarityLabel = Ui.label({
		Name = "Rarity",
		Size = UDim2.new(1, -24, 0, 26),
		Position = UDim2.fromOffset(12, 8),
		Text = "",
		ZIndex = 6,
	})
	rarityLabel.Parent = card
	nameLabel = Ui.label({
		Name = "Name",
		Size = UDim2.new(1, -24, 0, 36),
		Position = UDim2.fromOffset(12, 34),
		Text = "",
		ZIndex = 6,
	})
	nameLabel.Parent = card
	infoLabel = Ui.label({
		Name = "Info",
		Size = UDim2.new(1, -24, 0, 26),
		Position = UDim2.fromOffset(12, 72),
		Text = "",
		RichText = true,
		ZIndex = 6,
	})
	infoLabel.Parent = card
	hintLabel = Ui.label({
		Name = "Hint",
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 1, 4),
		Text = "",
		TextColor3 = Ui.Colors.Ice,
		ZIndex = 6,
	})
	hintLabel.Parent = card
	local new = Ui.frame({
		Name = "New",
		Size = UDim2.fromOffset(78, 32),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -18, 0, 2),
		Rotation = 12,
		BackgroundColor3 = Ui.Colors.Red,
		ZIndex = 7,
	})
	Ui.corner(new, 10)
	Ui.stroke(new, 3)
	local newText = Ui.label({ Size = UDim2.fromScale(1, 1), Text = "NEW!", ZIndex = 8 })
	newText.Parent = new
	new.Parent = card
	newBadge = new
	card.Parent = gui

	confetti = Ui.frame({ Name = "Confetti", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 9 })
	confetti.Parent = gui
end

local function buildWelcome()
	local wgui = Ui.screen("WelcomeBack", 30)
	local wbody
	welcome, wbody = Ui.window(wgui, "Welcome", "WELCOME BACK!", Vector2.new(420, 260))
	welcomeText = Ui.label({ Size = UDim2.new(1, 0, 0, 90), Text = "" })
	welcomeText.Parent = wbody
	local double = Ui.button(
		{
			Name = "Double",
			Size = UDim2.new(0.5, -6, 0, 56),
			Position = UDim2.new(0, 0, 1, -58),
			BackgroundColor3 = Ui.Colors.Robux,
		},
		`DOUBLE {Ui.ROBUX}49`,
		function()
			Net.func("PromptPurchase"):InvokeServer("DoubleOffline")
			Ui.closeWindow(welcome)
		end
	)
	double.Visible = (Products.ProductByKey.DoubleOffline and Products.ProductByKey.DoubleOffline.Id ~= 0) == true
	double.Parent = wbody
	Ui.button(
		{
			Size = UDim2.new(0.5, -6, 0, 56),
			Position = UDim2.new(0.5, 6, 1, -58),
			BackgroundColor3 = Ui.Colors.Green,
		},
		"COLLECT",
		function()
			Ui.closeWindow(welcome)
		end
	).Parent =
		wbody
end

function HatchController:Init(controllers)
	C = controllers
	buildGui()
	buildWelcome()
end

function HatchController:Start()
	Net.event("HatchShown").OnClientEvent:Connect(function(info)
		if type(info) == "table" then
			task.spawn(playOther, info)
		end
	end)
	Net.event("HatchCompleted").OnClientEvent:Connect(function(info)
		if type(info) ~= "table" then
			return
		end
		-- The pet stays out of the park until its show reveals it.
		if info.Uid then
			C.PetWorldController:HidePet(info.Uid, true)
		end
		if playing or #queue > 0 then
			-- Keep this egg visible where it sat until its turn comes.
			local spot = spotOf(myBaseIndex(), info)
			if spot then
				local egg = EggLook.make(info.EggRarity or info.Rarity)
				egg.Name = "WaitingEgg"
				looks(egg)
				egg:PivotTo(spot)
				egg.Parent = Workspace
				waiting[info] = egg
				-- An impatient little wobble while it waits.
				task.spawn(function()
					while waiting[info] == egg and egg.Parent do
						local start = os.clock()
						while os.clock() - start < 0.35 and egg.Parent do
							local t = (os.clock() - start) / 0.35
							local angle = math.sin(t * math.pi * 4) * math.rad(7) * (1 - t)
							egg:PivotTo(spot * CFrame.Angles(angle * 0.4, 0, angle))
							RunService.RenderStepped:Wait()
						end
						if egg.Parent then
							egg:PivotTo(spot)
						end
						task.wait(0.8 + math.random() * 0.6)
					end
				end)
			end
		end
		table.insert(queue, info)
		pump()
	end)
	Net.event("WelcomeBack").OnClientEvent:Connect(function(info)
		welcomeText.Text =
			`Your pets earned {Format.cash(info.Cash)} while you were away ({Format.duration(info.Seconds)})`
		Ui.openWindow(welcome)
	end)
	UserInputService.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		local pad = input.KeyCode == Enum.KeyCode.ButtonA
			or input.KeyCode == Enum.KeyCode.ButtonB
			or input.KeyCode == Enum.KeyCode.ButtonR2
		if playing and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch or pad) then
			skipRequested = true
		end
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 1 / 30 then
			accumulator = 0
			updateGrowing()
		end
	end)
end

return HatchController
