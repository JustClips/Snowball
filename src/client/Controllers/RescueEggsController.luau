--!strict
-- The egg strip during an egg rescue (Dev 2026-11-20: "we can't even see what eggs we got"):
-- where the bag hotbar sits, one tile per egg of this rescue, icon only (kids don't read):
--   * in your arms: the egg on its rarity colour with a red X badge. Tap = drop it back on
--     the pile (to go for a better one).
--   * still in the pile: dimmed; the one you'll grab next has a target badge. Tap = grab
--     that one next.
--   * saved (in your bag): green tile with a check badge.
-- Reads Workspace.Rescue.<UserId> HeldList / PileList / SavedList (EggRescueService).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggLook = require(Shared.EggLook)
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Parent.Ui)

local TILE = 64
local MAX_TILES = 9

local RescueEggsController = {}

local strip: Frame
local shownSig = ""

local function split(s: any): { string }
	local out = {}
	if type(s) == "string" and s ~= "" then
		for name in string.gmatch(s, "[^,]+") do
			table.insert(out, name)
		end
	end
	return out
end

local function rarityColor(name: string): Color3
	local def = Eggs.ByName[name]
	if not def then
		return Color3.new(1, 1, 1)
	end
	-- Secret is near-black: a deep violet tile reads better.
	return if name == "Secret" then Color3.fromRGB(90, 50, 140) else def.Color
end

local function eggView(parent: GuiObject, rarity: string, dim: boolean)
	local vp = Instance.new("ViewportFrame")
	vp.Name = "View"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.new(1, -8, 1, -12)
	vp.Position = UDim2.fromOffset(4, 3)
	vp.Ambient = Color3.fromRGB(200, 205, 220)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = Vector3.new(-1, -1, -0.6)
	vp.ImageTransparency = if dim then 0.35 else 0
	vp.ZIndex = 3
	local model = EggLook.make(rarity)
	model:PivotTo(CFrame.Angles(0, math.rad(25), 0))
	model.Parent = vp
	local cam = Instance.new("Camera")
	local box, size = model:GetBoundingBox()
	local d = math.max(size.X, size.Y, size.Z) * 1.3 + 0.6
	cam.FieldOfView = 38
	cam.CFrame = CFrame.lookAt(box.Position + Vector3.new(0, size.Y * 0.1, -d * 1.4), box.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
	vp.Parent = parent
end

local function badge(parent: GuiObject, icon: string, color: Color3)
	local b = Ui.frame({
		Name = "Badge",
		Size = UDim2.fromOffset(26, 26),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		BackgroundColor3 = color,
		ZIndex = 5,
	})
	Ui.corner(b, 13)
	Ui.stroke(b, 2.5)
	Ui.icon(icon, { Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(4, 4), ZIndex = 6 }).Parent = b
	b.Parent = parent
end

local function tile(order: number, rarity: string, kind: string, index: number, isNext: boolean)
	local b = Instance.new("TextButton")
	b.Name = kind .. index
	b.Text = ""
	b.AutoButtonColor = false
	b.Size = UDim2.fromOffset(TILE, TILE)
	b.LayoutOrder = order
	b.ZIndex = 2
	local color = rarityColor(rarity)
	if kind == "Saved" then
		color = Ui.Colors.Green
	elseif kind == "Pile" then
		color = Ui.darker(color, 0.55)
	end
	Ui.block(b, color, 3, 5)
	eggView(b, rarity, kind == "Pile")
	if kind == "Held" then
		badge(b, "Close", Ui.Colors.Red)
		-- A little bob so the eggs in your arms stand out.
		local scale = Instance.new("UIScale")
		scale.Parent = b
		TweenService:Create(
			scale,
			TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.08 }
		):Play()
	elseif kind == "Saved" then
		badge(b, "Checkmark", Ui.Colors.Green)
	elseif isNext then
		badge(b, "Target", Ui.Colors.Yellow)
	end
	b.Activated:Connect(function()
		if kind == "Saved" then
			return
		end
		Ui.sound("Tap")
		local ok, message = Net.func("Rescue"):InvokeServer(if kind == "Held" then "Drop" else "Pick", index)
		if not ok and message then
			Ui.toast(message, "Bad")
		end
	end)
	b.Parent = strip
end

local function render(folder: Instance?)
	local held = split(folder and folder:GetAttribute("HeldList"))
	local pile = split(folder and folder:GetAttribute("PileList"))
	local saved = split(folder and folder:GetAttribute("SavedList"))
	local sig = table.concat(held, ",") .. "|" .. table.concat(pile, ",") .. "|" .. table.concat(saved, ",")
	if sig == shownSig then
		return
	end
	shownSig = sig
	for _, c in strip:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local n = 0
	local function add(kind: string, list: { string })
		for i, rarity in list do
			if n >= MAX_TILES then
				return
			end
			n += 1
			tile(n, rarity, kind, i, kind == "Pile" and i == 1)
		end
	end
	add("Held", held)
	add("Pile", pile)
	add("Saved", saved)
	strip.Visible = n > 0
end

function RescueEggsController:Init()
	local gui = Ui.screen("RescueEggs", 13)
	strip = Ui.frame({
		Name = "Strip",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10), -- where the bag hotbar sits (hidden while rescuing)
		Size = UDim2.fromOffset((TILE + 8) * MAX_TILES, TILE + 6),
		Visible = false,
	})
	Ui.autoScale(strip)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = strip
	strip.Parent = gui
end

function RescueEggsController:Start()
	local root = Workspace:WaitForChild("Rescue")
	local me = tostring(Players.LocalPlayer.UserId)
	local conns: { RBXScriptConnection } = {}
	local function watch(folder: Instance?)
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		shownSig = ""
		render(folder)
		if folder then
			for _, attr in { "HeldList", "PileList", "SavedList" } do
				table.insert(
					conns,
					folder:GetAttributeChangedSignal(attr):Connect(function()
						render(folder)
					end)
				)
			end
		end
	end
	root.ChildAdded:Connect(function(child)
		if child.Name == me then
			watch(child)
		end
	end)
	root.ChildRemoved:Connect(function(child)
		if child.Name == me then
			watch(nil)
		end
	end)
	watch(root:FindFirstChild(me))
end

return RescueEggsController
