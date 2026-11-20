--!strict
-- The egg strip while rolling (Dev 2026-11-20: "drop while you are rolling as a snowball"):
-- bottom centre, under STOP, one tile per egg slot of the ball. Icon only (kids don't read):
--   * an egg the ball picked up: the egg on its rarity colour with a red X badge. Tap = drop
--     it out of the ball, so the slot is free for a better egg further down.
--   * a free slot: a dim egg outline.
--   * the ball is full and hits another egg: every tile flashes red and shakes.
-- Same look as the rescue strip (RescueEggsController). Server: RollService "DropEgg".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggLook = require(Shared.EggLook)
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local TILE = 64
local MAX_TILES = 9

local RollEggsController = {}

local player = Players.LocalPlayer
local strip: Frame
local eggs: { string } = {}
local slots = 3
local rolling = false
local stopped = false -- the KEEP ROLLING? window is up
local busy = false

local function rarityColor(name: string): Color3
	local def = Eggs.ByName[name]
	if not def then
		return Color3.new(1, 1, 1)
	end
	return if name == "Secret" then Color3.fromRGB(90, 50, 140) else def.Color
end

local function eggView(parent: GuiObject, rarity: string)
	local vp = Instance.new("ViewportFrame")
	vp.Name = "View"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.new(1, -8, 1, -12)
	vp.Position = UDim2.fromOffset(4, 3)
	vp.Ambient = Color3.fromRGB(200, 205, 220)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = Vector3.new(-1, -1, -0.6)
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

local function badge(parent: GuiObject)
	local b = Ui.frame({
		Name = "Badge",
		Size = UDim2.fromOffset(26, 26),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		BackgroundColor3 = Ui.Colors.Red,
		ZIndex = 5,
	})
	Ui.corner(b, 13)
	Ui.stroke(b, 2.5)
	Ui.icon("Close", { Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(4, 4), ZIndex = 6 }).Parent = b
	b.Parent = parent
end

local function popIn(object: GuiObject)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = object
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

local function drop(index: number)
	if busy then
		return
	end
	busy = true
	Ui.sound("Tap")
	local ok, left = Net.func("DropEgg"):InvokeServer(index)
	busy = false
	if ok and type(left) == "table" then
		Ui.sound("Pop")
		eggs = left
		RollEggsController:Render()
	end
end

local function eggTile(order: number, rarity: string, fresh: boolean)
	local b = Instance.new("TextButton")
	b.Name = "Egg" .. order
	b.Text = ""
	b.AutoButtonColor = false
	b.Size = UDim2.fromOffset(TILE, TILE)
	b.LayoutOrder = order
	b.ZIndex = 2
	Ui.block(b, rarityColor(rarity), 3, 5)
	eggView(b, rarity)
	badge(b)
	if fresh then
		popIn(b)
	end
	b.Activated:Connect(function()
		drop(order)
	end)
	b.Parent = strip
end

local function emptyTile(order: number)
	local f = Ui.frame({
		Name = "Free" .. order,
		Size = UDim2.fromOffset(TILE, TILE),
		LayoutOrder = order,
		BackgroundColor3 = Color3.fromRGB(30, 40, 60),
		BackgroundTransparency = 0.45,
		ZIndex = 2,
	})
	Ui.stroke(f, 3, Color3.fromRGB(255, 255, 255)).Transparency = 0.5
	local icon = Ui.icon("Egg", {
		Size = UDim2.fromOffset(36, 36),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ImageTransparency = 0.65,
		ZIndex = 3,
	})
	icon.Parent = f
	f.Parent = strip
end

local shown = 0
function RollEggsController:Render()
	for _, c in strip:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local n = math.min(math.max(slots, #eggs), MAX_TILES)
	for i = 1, n do
		local rarity = eggs[i]
		if rarity then
			eggTile(i, rarity, i > shown)
		else
			emptyTile(i)
		end
	end
	shown = #eggs
end

-- The ball is full: flash every tile red and shake the strip.
local function flashFull()
	Ui.sound("Wobble")
	for _, c in strip:GetChildren() do
		if c:IsA("GuiObject") then
			local flash = Ui.frame({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Ui.Colors.Red,
				BackgroundTransparency = 0.2,
				ZIndex = 7,
			})
			flash.Parent = c
			TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			task.delay(0.5, function()
				flash:Destroy()
			end)
		end
	end
	local base = strip.Position
	task.spawn(function()
		for i = 1, 6 do
			strip.Position = base + UDim2.fromOffset(if i % 2 == 0 then 6 else -6, 0)
			task.wait(0.04)
		end
		strip.Position = base
	end)
end

local function refreshVisible()
	strip.Visible = rolling and not stopped and player:GetAttribute("RollPhase") == "Rolling"
end

function RollEggsController:Init()
	local gui = Ui.screen("RollEggs", 12)
	strip = Ui.frame({
		Name = "Strip",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10), -- under STOP (HudLayout.Action sits at -98)
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

function RollEggsController:Start()
	Net.event("RunStarted").OnClientEvent:Connect(function(userId: number)
		if userId ~= player.UserId then
			return
		end
		local data = State.data :: any
		slots = if data and data.EggSlots then data.EggSlots else 3
		eggs = {}
		shown = 0
		rolling = true
		stopped = false
		RollEggsController:Render()
		refreshVisible()
	end)
	Net.event("RunEvent").OnClientEvent:Connect(function(kind: string, payload: any)
		if not rolling then
			return
		end
		if kind == "Egg" and type(payload) == "table" and type(payload.Rarity) == "string" then
			table.insert(eggs, payload.Rarity)
			RollEggsController:Render()
		elseif kind == "Full" then
			flashFull()
		end
	end)
	Net.event("RunStopped").OnClientEvent:Connect(function()
		stopped = true
		refreshVisible()
	end)
	Net.event("RunContinued").OnClientEvent:Connect(function(userId: number)
		if userId == player.UserId then
			stopped = false
			refreshVisible()
		end
	end)
	Net.event("RunEnded").OnClientEvent:Connect(function(userId: number)
		if userId == player.UserId then
			rolling = false
			refreshVisible()
		end
	end)
	player:GetAttributeChangedSignal("RollPhase"):Connect(refreshVisible)
end

return RollEggsController
