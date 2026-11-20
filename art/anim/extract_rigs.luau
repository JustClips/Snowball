--[[
Rebuilds art/anim/pet_rigs.json (bones, part size, mesh + texture ids of every pack animal)
from the StudAnimalPack file. From the repo root:
  python3 art/anim/strip_tags.py <StudAnimalPack_100.rbxm> /tmp/pack.rbxm
  lune run art/anim/extract_rigs.luau /tmp/pack.rbxm
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local root = roblox.deserializeModel(fs.readFile(process.args[1]))[1]
local out = {}
local function round(x: number): number
	return math.floor(x * 1e6 + 0.5) / 1e6
end
for _, m in root:GetChildren() do
	if m:IsA("Model") then
		local mp = m:FindFirstChildWhichIsA("MeshPart")
		if mp then
			local bones = {}
			local function walk(b, parent)
				for _, c in b:GetChildren() do
					if c:IsA("Bone") then
						local cf = {}
						for _, v in { c.CFrame:GetComponents() } do
							table.insert(cf, round(v))
						end
						table.insert(bones, { name = c.Name, parent = parent, cf = cf })
						walk(c, c.Name)
					end
				end
			end
			walk(mp, mp.Name)
			local sa = mp:FindFirstChildWhichIsA("SurfaceAppearance")
			local function id(content): number
				return tonumber(string.match(tostring(content), "%d+")) or 0
			end
			out[m.Name] = {
				part = mp.Name,
				size = { round(mp.Size.X), round(mp.Size.Y), round(mp.Size.Z) },
				bones = bones,
				mesh = id(mp.MeshContent),
				tex = if sa then id(sa.ColorMapContent) else 0,
			}
		end
	end
end
fs.writeFile("art/anim/pet_rigs.json", serde.encode("json", out, false))
print("pets:", #root:GetChildren() - 1)
