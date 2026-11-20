--!strict
-- Particle bursts with the Blender-rendered textures (art/blender/vfx.py -> Images.Fx_*).
-- Fx.burst("Puff" | "Sparkle" | "Shatter" | "Ring" | "Flakes", position, scale?)
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Images = require(ReplicatedStorage:WaitForChild("Shared").Config.Images)

local Fx = {}

type Spec = {
	Texture: string,
	Count: number,
	Size: NumberSequence,
	Life: NumberRange,
	Speed: NumberRange,
	Color: ColorSequence?,
	Transparency: NumberSequence?,
	Flipbook: boolean?,
	Spread: number?,
	Rot: NumberRange?,
	Accel: Vector3?,
	Light: number?,
	Drag: number?,
}

local function seq(a: number, b: number): NumberSequence
	return NumberSequence.new(a, b)
end

local SPECS: { [string]: { Spec } } = {
	Puff = {
		{
			Texture = Images.Fx_SnowPuff,
			Flipbook = true,
			Count = 7,
			Size = seq(1.6, 4.2),
			Life = NumberRange.new(0.6, 0.9),
			Speed = NumberRange.new(5, 11),
			Accel = Vector3.new(0, -6, 0),
			Drag = 3,
			Rot = NumberRange.new(0, 360),
		},
	},
	Sparkle = {
		{
			Texture = Images.Fx_Sparkle,
			Count = 10,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.25, 1.6),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Life = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(4, 10),
			Light = 1,
			Drag = 4,
			Rot = NumberRange.new(0, 45),
		},
	},
	Flakes = {
		{
			Texture = Images.Fx_Flake,
			Count = 12,
			Size = seq(0.8, 0.4),
			Life = NumberRange.new(0.8, 1.4),
			Speed = NumberRange.new(6, 14),
			Accel = Vector3.new(0, -10, 0),
			Rot = NumberRange.new(0, 360),
			Light = 0.4,
		},
	},
	Ring = {
		{
			Texture = Images.Fx_Ring,
			Count = 1,
			Size = seq(1, 14),
			Life = NumberRange.new(0.45, 0.45),
			Speed = NumberRange.new(0, 0),
			Transparency = seq(0.1, 1),
			Light = 0.6,
		},
	},
}
SPECS.Shatter = {
	SPECS.Puff[1],
	{
		Texture = Images.Fx_Shard,
		Count = 18,
		Size = seq(1.4, 0.6),
		Life = NumberRange.new(0.8, 1.3),
		Speed = NumberRange.new(14, 28),
		Accel = Vector3.new(0, -40, 0),
		Rot = NumberRange.new(0, 360),
		Light = 0.3,
	},
	SPECS.Ring[1],
	SPECS.Sparkle[1],
}

local holder: Folder? = nil
local function folder(): Folder
	if holder and holder.Parent then
		return holder
	end
	local f = Instance.new("Folder")
	f.Name = "Fx"
	f.Parent = Workspace
	holder = f
	return f
end

function Fx.burst(kind: string, position: Vector3, scale: number?)
	local specs = SPECS[kind]
	if not specs then
		return
	end
	local s = scale or 1
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = CFrame.new(position)
	part.Parent = folder()
	local longest = 0
	for _, spec in specs do
		if spec.Texture == nil or spec.Texture == "" then
			continue
		end
		local e = Instance.new("ParticleEmitter")
		e.Texture = spec.Texture
		e.Enabled = false
		e.Rate = 0
		e.Lifetime = spec.Life
		e.Speed = NumberRange.new(spec.Speed.Min * s, spec.Speed.Max * s)
		local keys = {}
		for _, k in spec.Size.Keypoints do
			table.insert(keys, NumberSequenceKeypoint.new(k.Time, k.Value * s))
		end
		e.Size = NumberSequence.new(keys)
		e.SpreadAngle = Vector2.new(spec.Spread or 180, spec.Spread or 180)
		e.Acceleration = (spec.Accel or Vector3.zero) * s
		e.Drag = spec.Drag or 0
		e.Rotation = spec.Rot or NumberRange.new(0, 0)
		e.LightEmission = spec.Light or 0
		e.Transparency = spec.Transparency
			or NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.7, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			})
		if spec.Color then
			e.Color = spec.Color
		end
		if spec.Flipbook then
			e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
			e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		end
		e.Parent = part
		e:Emit(spec.Count)
		longest = math.max(longest, spec.Life.Max)
	end
	Debris:AddItem(part, longest + 0.2)
end

return Fx
