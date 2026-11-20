--!nocheck
-- Dumps the GUIs of a .rbxl place (StarterGui ScreenGuis plus any ScreenGui/Frame kept in
-- ReplicatedStorage) to JSON for render.py. Scripts in the place are never run.
--   lune run tools/ui_render/rbxl.luau <place.rbxl> <out.json>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Dump = require("./dump")

local game = roblox.deserializePlace(fs.readFile(process.args[1]))
local function get(x, k)
	return x[k]
end
local screens = {}
local function collect(root)
	for _, d in root:GetDescendants() do
		if d.ClassName == "ScreenGui" then
			table.insert(screens, Dump.node(d, typeof, get))
		end
	end
end
for _, svc in { "StarterGui", "ReplicatedStorage", "StarterPlayer", "Workspace" } do
	local s = game:FindFirstChild(svc)
	if s then
		collect(s)
	end
end
-- Loose templates (Frames in ReplicatedStorage) go in a fake ScreenGui each.
local rs = game:FindFirstChild("ReplicatedStorage")
if rs then
	for _, d in rs:GetDescendants() do
		if (d.ClassName == "Frame" or d.ClassName == "ImageLabel") and d.Parent and not d.Parent:IsA("GuiObject") and not d:FindFirstAncestorWhichIsA("ScreenGui") then
			local node = Dump.node(d, typeof, get)
			table.insert(screens, { c = "ScreenGui", n = "Template_" .. d.Name, p = { Enabled = false }, k = { node } })
		end
	end
end
fs.writeFile(process.args[2], serde.encode("json", screens))
print(`{#screens} screens`)
