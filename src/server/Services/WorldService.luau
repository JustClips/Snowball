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
		spawn.CFrame = cf * CFrame.new(0, 1.5, 10)
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
			label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Black)
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

function WorldService:Init()
	local root = folder("Mountain", Workspace)
	buildSummit(root)
	buildTrack(root)
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
