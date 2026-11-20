--!strict
-- Builds the graybox world at server start (GAME_PLAN §8 step 5): summit plaza, 8 base
-- pads, the launch deck and the track strip from Config/Track. Everything here is a
-- placeholder for the Blender models (art thread) and keeps their spots and names, so
-- swapping in the real meshes only changes what gets parented under these folders.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Spline = require(Shared.Spline)
local World = require(Shared.Config.World)
local ModelLoader = require(script.Parent.Parent.Lib.ModelLoader)
local Zones = require(Shared.Config.Zones)

local WorldService = {}

local SEGMENT = 20 -- studs of track per graybox part
local WALL_HEIGHT = 6
local SNOW = Color3.fromRGB(240, 246, 255)

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Snow
	p.Color = SNOW
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function folder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function buildSummit(root: Folder)
	local summit = folder("Summit", root)
	part({
		Name = "Plaza",
		Size = World.Plaza.Size,
		CFrame = CFrame.new(World.Plaza.Center - Vector3.yAxis * World.Plaza.Size.Y / 2),
		Parent = summit,
	})
	-- A wide snowy shoulder under the plaza so the summit doesn't float.
	part({
		Name = "Peak",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(700, 700, 700),
		CFrame = CFrame.new(World.Plaza.Center - Vector3.yAxis * 352),
		Parent = summit,
	})
	part({
		Name = "Deck",
		Size = World.Deck.Size,
		CFrame = CFrame.new(World.Deck.Center - Vector3.yAxis * (World.Deck.Size.Y / 2 - 0.05)),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(165, 120, 80),
		Parent = summit,
	})
	for lane = 1, World.LaneCount do
		part({
			Name = "Lane" .. lane,
			Size = Vector3.new(1, 0.2, World.Deck.Size.Z),
			CFrame = CFrame.new(World.Deck.Center + Vector3.new(World.laneX(lane) + World.LaneSpacing / 2, 0.1, 0)),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(110, 75, 50),
			CanCollide = false,
			Parent = summit,
		})
	end
	-- Lucky Wheel stand (graybox): the client opens the wheel window from its prompt.
	local wheel = part({
		Name = "LuckyWheel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 22, 22),
		CFrame = CFrame.new(World.WheelStand + Vector3.yAxis * 14) * CFrame.Angles(0, math.pi / 2, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(255, 194, 46),
		Parent = summit,
	})
	part({
		Name = "LuckyWheelPost",
		Size = Vector3.new(3, 4, 3),
		CFrame = CFrame.new(World.WheelStand + Vector3.yAxis * 2),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 110, 70),
		Parent = summit,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WheelPrompt"
	prompt.ActionText = "Lucky Wheel"
	prompt.ObjectText = "Spin"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = wheel
	local bases = folder("Bases", summit)
	for i = 1, World.BaseCount do
		local cf = World.baseCFrame(i)
		local base = Instance.new("Model")
		base.Name = "Base" .. i
		local pad = part({
			Name = "Pad",
			Size = World.BaseSize,
			CFrame = cf * CFrame.new(0, 0.5, 0),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(200, 225, 245),
			Parent = base,
		})
		base.PrimaryPart = pad
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn"
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Enabled = false -- BaseService spawns players at their own base
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.CFrame = cf * CFrame.new(0, 1.5, -2)
		spawn.Parent = base
		local roller = part({
			Name = "RollerPad",
			Size = Vector3.new(16, 1, 16),
			CFrame = CFrame.new(World.rollerSpot(i) + Vector3.yAxis * 0.5) * cf.Rotation,
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(150, 110, 70),
			Parent = base,
		})
		roller:SetAttribute("Base", i)
		base:SetAttribute("Index", i)
		base.Parent = bases
	end
end

local function buildTrack(root: Folder)
	local spline = Spline.main()
	local track = folder("Track", root)
	local s = 0
	while s < spline.Length do
		local len = math.min(SEGMENT, spline.Length - s)
		local mid = s + len / 2
		local smp = spline:sample(mid)
		local cf = CFrame.lookAt(smp.Pos, smp.Pos + smp.Forward)
		local zone = Zones.at(mid)
		local color = if smp.Surface == "Ice" then Color3.fromRGB(185, 225, 250) else zone.GroundColor
		part({
			Name = "Ground",
			Size = Vector3.new(smp.Width + 8, 4, len + 2),
			CFrame = cf * CFrame.new(0, -2, 0),
			Material = if smp.Surface == "Ice" then Enum.Material.Ice else Enum.Material.Snow,
			Color = color,
			Parent = track,
		})
		for _, side in { -1, 1 } do
			part({
				Name = "Wall",
				Size = Vector3.new(4, WALL_HEIGHT, len + 2),
				CFrame = cf * CFrame.new(side * (smp.Width / 2 + 4), WALL_HEIGHT / 2 - 1, 0),
				Color = Color3.fromRGB(225, 235, 250),
				Parent = track,
			})
		end
		s += SEGMENT
	end
	-- Zone signs (arches) at each zone start.
	for _, zone in Zones.List do
		if zone.Start > 0 then
			local smp = spline:sample(zone.Start)
			local cf = CFrame.lookAt(smp.Pos, smp.Pos + smp.Forward)
			local arch = Instance.new("Model")
			arch.Name = "ZoneSign_" .. zone.Id
			for _, side in { -1, 1 } do
				part({
					Name = "Post",
					Size = Vector3.new(3, 30, 3),
					CFrame = cf * CFrame.new(side * (smp.Width / 2 + 3), 15, 0),
					Color = zone.Color,
					Material = Enum.Material.SmoothPlastic,
					Parent = arch,
				})
			end
			local beam = part({
				Name = "Beam",
				Size = Vector3.new(smp.Width + 10, 6, 2),
				CFrame = cf * CFrame.new(0, 31, 0),
				Color = zone.Color,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				Parent = arch,
			})
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Back
			gui.PixelsPerStud = 20
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
			label.TextScaled = true
			label.TextColor3 = Color3.new(1, 1, 1)
			label.Text = string.upper(zone.Name)
			label.Parent = gui
			gui.Parent = beam
			arch.Parent = track
		end
	end
	-- The Village wall at the bottom.
	local wallS = Zones.VillageWall
	local smp = spline:sample(wallS)
	part({
		Name = "VillageWall",
		Size = Vector3.new(smp.Width + 10, 24, 6),
		CFrame = CFrame.lookAt(smp.Pos, smp.Pos + smp.Forward) * CFrame.new(0, 12, -8),
		Color = Color3.fromRGB(250, 250, 255),
		CanCollide = false,
		Parent = track,
	})
end

local function setLighting()
	Lighting.ClockTime = 13
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(150, 165, 190)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 185, 210)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.3
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(215, 230, 250)
	atmosphere.Decay = Color3.fromRGB(150, 175, 215)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting
end

-- The Blender base model (art/blender/base.py, tools/upload_models.py) on every base. Its
-- floor top is 0.5 above the model origin, so the origin sits at the pad's centre and the
-- floor lands on the pad top. The pad stays as the invisible floor; the fence gets plain
-- invisible walls with a gate gap.
local function fenceWalls(base: Model, cf: CFrame)
	local hx, hz = World.BaseSize.X / 2 - 1, World.BaseSize.Z / 2 - 1
	local walls = {
		{ Vector3.new(hx * 2, 6, 1), Vector3.new(0, 3, hz) },
		{ Vector3.new(1, 6, hz * 2), Vector3.new(hx, 3, 0) },
		{ Vector3.new(1, 6, hz * 2), Vector3.new(-hx, 3, 0) },
		{ Vector3.new(hx - 7, 6, 1), Vector3.new((hx + 7) / 2, 3, -hz) },
		{ Vector3.new(hx - 7, 6, 1), Vector3.new(-(hx + 7) / 2, 3, -hz) },
	}
	for i, w in walls do
		part({
			Name = "FenceWall" .. i,
			Size = w[1],
			CFrame = cf * CFrame.new(w[2] + Vector3.new(0, 1, 0)),
			Transparency = 1,
			Parent = base,
		})
	end
end

local function dressBases(bases: Folder)
	if not ModelLoader.get("Base") then
		return
	end
	for i = 1, World.BaseCount do
		local base = bases:FindFirstChild("Base" .. i) :: Model?
		local cf = World.baseCFrame(i)
		local look = base and ModelLoader.clone("Base", cf * CFrame.new(0, 0.5, 0))
		if base and look then
			look.Name = "Look"
			for _, d in look:GetDescendants() do
				if d:IsA("BasePart") then
					-- Only the cabin is solid; the pad is the floor and the fence uses plain walls.
					d.CanCollide = d.Name == "Cabin"
					d.CanQuery = d.Name == "Cabin"
				end
			end
			look.Parent = base
			local pad = base:FindFirstChild("Pad") :: BasePart?
			if pad then
				pad.Transparency = 1
			end
			fenceWalls(base, cf)
		end
	end
end

-- The launch deck model (art/blender/deck.py): origin = deck centre at deck-top height.
local function dressDeck(summit: Folder)
	local look = ModelLoader.clone("Deck", CFrame.new(World.Deck.Center))
	if not look then
		return
	end
	look.Name = "DeckLook"
	for _, d in look:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	look.Parent = summit
	local deck = summit:FindFirstChild("Deck") :: BasePart?
	if deck then
		deck.Transparency = 1
	end
	for lane = 1, World.LaneCount do
		local mark = summit:FindFirstChild("Lane" .. lane) :: BasePart?
		if mark then
			mark.Transparency = 1
		end
	end
end

-- Summit props (art/blender/props.py) from World.plazaProps().
local function dressPlaza(summit: Folder)
	local props = folder("Props", summit)
	for _, spot in World.plazaProps() do
		local m = ModelLoader.clone("Prop_" .. spot.Name, spot.CFrame, spot.Scale)
		if m then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = spot.Name ~= "Bench"
				end
			end
			m.Parent = props
		end
	end
end

function WorldService:Init()
	local root = folder("Mountain", Workspace)
	buildSummit(root)
	buildTrack(root)
	local summit = root:FindFirstChild("Summit") :: Folder
	task.spawn(dressBases, summit:FindFirstChild("Bases"))
	task.spawn(dressDeck, summit)
	task.spawn(dressPlaza, summit)
	setLighting()
	-- Spare the default template's baseplate/spawn if the place still has them.
	for _, name in { "Baseplate", "SpawnLocation" } do
		local old = Workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
end

function WorldService:GetBase(i: number): Model?
	local mountain = Workspace:FindFirstChild("Mountain")
	local bases = mountain and mountain:FindFirstChild("Summit") and (mountain :: any).Summit:FindFirstChild("Bases")
	return bases and bases:FindFirstChild("Base" .. i) :: Model?
end

return WorldService
