--!strict
-- Carrying something from your bag and putting it down yourself (Steal an Egg / Sweep the
-- World). Hold(kind, id) asks the server to put it in your arms (CarryService welds the
-- model, HoldPoseController poses the arms). While you're at your base a see-through ghost
-- of it follows the mouse (or sits where you last tapped on a phone) with a ring: green =
-- it can go there, red = not there (Shared/EggSpots, the same rules the server checks for
-- eggs). Click / tap to put it down. Far from your base a big HOME button shows instead.
-- The red X at the left of the hotbar (or Q) puts it back in the bag.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggLook = require(Shared.EggLook)
local EggSpots = require(Shared.EggSpots)
local Net = require(Shared.Net)
local PetLook = require(Shared.PetLook)
local PetStats = require(Shared.PetStats)
local World = require(Shared.Config.World)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local GOOD = Color3.fromRGB(61, 220, 90)
local BAD = Color3.fromRGB(255, 77, 94)
local NEAR_BASE = 60 -- studs from the park centre to put things down
local SNAP_REACH = 5
local SNAP_PAD = 0.1
local TAP_SLOP = 14

local player = Players.LocalPlayer

local PlacementController = {}

local C: any
local gui: ScreenGui
local homeButton: TextButton

local heldKind: string? = nil
local heldId: string? = nil
local ghost: Model? = nil
local ring: BasePart? = nil
local spotOk = false
local spotWorld: Vector3? = nil
local spotProblem: string? = nil
local pointer: Vector2? = nil
local touchStart: Vector2? = nil
local busy = false
local heldAt = 0 -- os.clock() when we took it (the bag update can lag a moment)

local function baseCFrame(): CFrame?
	local index = player:GetAttribute("BaseIndex")
	if type(index) ~= "number" or index == 0 then
		return nil
	end
	return World.baseCFrame(index)
end

local function parkCentre(cf: CFrame): Vector3
	local c = (World.ParkMin + World.ParkMax) / 2
	return cf * Vector3.new(c.X, 0, c.Y)
end

local function nearBase(): boolean
	local cf = baseCFrame()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not cf or not root then
		return false
	end
	local centre = parkCentre(cf)
	return (Vector3.new(root.Position.X, centre.Y, root.Position.Z) - centre).Magnitude <= NEAR_BASE
end

local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	if ring then
		ring:Destroy()
		ring = nil
	end
end

local function makeGhost()
	clearGhost()
	local model: Model?
	if heldKind == "Egg" and heldId then
		model = EggLook.make(heldId)
	elseif heldKind == "Pet" and heldId then
		local pet = State.data and State.data.Pets and State.data.Pets[heldId]
		if pet then
			model = PetLook.make(pet.Id, pet.Mutation, pet.Huge, PetStats.sizeMult(pet))
		end
	end
	if not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Transparency = math.max(d.Transparency, 0.4)
		end
	end
	model.Parent = Workspace
	ghost = model
	local r = Instance.new("Part")
	r.Name = "PlaceRing"
	r.Shape = Enum.PartType.Cylinder
	r.Size = Vector3.new(0.15, EggSpots.Spacing, EggSpots.Spacing)
	r.Anchored = true
	r.CanCollide = false
	r.CanQuery = false
	r.CanTouch = false
	r.CastShadow = false
	r.Material = Enum.Material.Neon
	r.Transparency = 0.4
	r.Parent = Workspace
	ring = r
end

local function screenPoint(): Vector2?
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return pointer
	end
	return UserInputService:GetMouseLocation()
end

-- Finds the park spot under the pointer and colours the ring.
local function update()
	if not heldKind then
		return
	end
	local near = nearBase()
	homeButton.Visible = not near
	local camera = Workspace.CurrentCamera
	local cf = baseCFrame()
	local data = State.data
	if not near or not camera or not cf or not data then
		spotOk, spotWorld = false, nil
		if ghost then
			clearGhost()
		end
		return
	end
	if not ghost then
		makeGhost()
	end
	local g, r = ghost, ring
	if not g or not r then
		return
	end
	local point = screenPoint()
	local aim: Vector3
	if point then
		local ray = camera:ViewportPointToRay(point.X, point.Y)
		local origin = cf:PointToObjectSpace(ray.Origin)
		local direction = cf:VectorToObjectSpace(ray.Direction)
		if direction.Y > -0.02 then
			spotOk, spotWorld = false, nil
			r.Transparency = 1
			return
		end
		local t = (World.ParkTop - origin.Y) / direction.Y
		aim = origin + direction * t
	else
		-- Phone before the first tap: a few studs in front of you.
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		aim = cf:PointToObjectSpace(root.Position + root.CFrame.LookVector * 7)
	end
	local lx, lz
	if heldKind == "Egg" then
		local x, z, why = EggSpots.nearest(data.Hatching or {}, aim.X, aim.Z, SNAP_REACH, SNAP_PAD)
		spotOk = x ~= nil
		spotProblem = why
		lx, lz = x or aim.X, z or aim.Z
	else
		local min, max = World.ParkMin, World.ParkMax
		local inside = aim.X > min.X + 1 and aim.X < max.X - 1 and aim.Z > min.Y + 1 and aim.Z < max.Y - 1
		spotOk = inside
		spotProblem = if inside then nil else "Put it inside your base"
		lx, lz = math.clamp(aim.X, min.X + 3, max.X - 3), math.clamp(aim.Z, min.Y + 3, max.Y - 3)
	end
	local snapped = cf * CFrame.new(lx, World.ParkTop, lz)
	spotWorld = if spotOk then snapped.Position else nil
	r.Transparency = 0.4
	r.Color = if spotOk then GOOD else BAD
	r.CFrame = snapped * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90))
	local bob = math.sin(os.clock() * 4) * 0.25
	g:PivotTo(snapped * CFrame.new(0, 0.4 + bob, 0) * CFrame.Angles(0, os.clock() * 0.8, 0))
end

function PlacementController:HeldKey(): string?
	return if heldKind and heldId then `{heldKind}:{heldId}` else nil
end

local function refresh()
	if C.InventoryController then
		C.InventoryController:Refresh()
	end
end

function PlacementController:Stop(silent: boolean?)
	if not heldKind then
		return
	end
	heldKind, heldId = nil, nil
	pointer = nil
	clearGhost()
	C.InventoryController:ShowPutAway(false)
	homeButton.Visible = false
	if not silent then
		task.spawn(function()
			Net.func("Pets"):InvokeServer("StopHolding")
		end)
	end
	refresh()
end

function PlacementController:Hold(kind: string, id: string)
	if C.HudController:Mode() ~= "Normal" then
		return
	end
	if kind == "Egg" then
		local data = State.data
		if data and #(data.Hatching or {}) >= World.HatchSpots then
			Ui.toast(`Only {World.HatchSpots} eggs can hatch at once! Open one first.`, "Bad")
			return
		end
	end
	PlacementController:Stop(true)
	heldKind, heldId = kind, id
	heldAt = os.clock()
	pointer = nil
	C.InventoryController:ShowPutAway(true)
	Ui.sound("Click")
	refresh()
	task.spawn(function()
		local ok, why = Net.func("Pets"):InvokeServer("Hold", kind, id)
		if not ok and heldKind == kind and heldId == id then
			PlacementController:Stop(true)
			if why then
				Ui.toast(why, "Bad")
			end
		end
	end)
end

local function placeNow()
	if busy or not heldKind then
		return
	end
	if not nearBase() then
		Ui.toast("Go to your base first!", "Bad")
		return
	end
	update()
	if not spotOk or not spotWorld then
		if spotProblem then
			Ui.toast(spotProblem, "Bad")
		end
		return
	end
	busy = true
	local kind, id, at = heldKind, heldId, spotWorld
	task.spawn(function()
		local ok, why = Net.func("Pets"):InvokeServer("PlaceHeld", at)
		busy = false
		if ok then
			Ui.sound("Upgrade")
			if C.PetWorldController and at then
				C.PetWorldController:Poof(at)
			end
			-- Eggs: the server keeps the next egg of a stack in your hands.
			local data = State.data
			local more = false
			if kind == "Egg" and data then
				local left = 0
				for _, egg in data.Eggs or {} do
					if egg.Rarity == id then
						left += 1
					end
				end
				more = left > 1 and #(data.Hatching or {}) + 1 < World.HatchSpots
			end
			if heldKind == kind and heldId == id and not more then
				PlacementController:Stop(true)
			end
		elseif why then
			Ui.toast(why, "Bad")
		end
	end)
end

function PlacementController:Init(controllers)
	C = controllers
	gui = Ui.screen("Holding", 13)
	-- Far from home: one big HOME button (teleports you to your base).
	homeButton = Ui.bigButton("GoHome", "Base", "HOME", Ui.Colors.Blue, function()
		Net.func("Teleport"):InvokeServer("Base")
	end, Vector2.new(220, 70))
	homeButton.AnchorPoint = Vector2.new(0.5, 1)
	homeButton.Position = UDim2.new(0.5, 0, 1, -200) -- above ROLL
	homeButton.Visible = false
	Ui.autoScale(homeButton)
	homeButton.Parent = gui
	local scale = homeButton:FindFirstChildOfClass("UIScale")
	task.spawn(function()
		while true do
			task.wait(0.6)
			if homeButton.Visible and scale then
				scale.Scale = 1.08
				TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
		end
	end)
end

local function overGui(pos: Vector2): boolean
	local objects = player:WaitForChild("PlayerGui"):GetGuiObjectsAtPosition(pos.X, pos.Y)
	for _, o in objects do
		if o:IsA("GuiButton") and o.Visible then
			return true
		end
	end
	return false
end

function PlacementController:Start()
	RunService.RenderStepped:Connect(function()
		if heldKind then
			if C.HudController:Mode() ~= "Normal" then
				PlacementController:Stop(true)
				return
			end
			-- Something used the last egg of a stack, or the pet left the bag.
			local data = State.data
			if data and heldId and os.clock() - heldAt > 1.5 and not busy then
				local gone = if heldKind == "Pet"
					then not (data.Pets and data.Pets[heldId] and not data.Pets[heldId].Placed)
					else (function()
						for _, egg in data.Eggs or {} do
							if egg.Rarity == heldId then
								return false
							end
						end
						return true
					end)()
				if gone then
					PlacementController:Stop(true)
					return
				end
			end
			update()
		end
	end)
	-- The server dropped what we held (respawn, training...).
	player:GetAttributeChangedSignal("Holding"):Connect(function()
		task.wait(0.3)
		if heldKind and player:GetAttribute("Holding") == nil and not busy then
			PlacementController:Stop(true)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not heldKind then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Backspace then
			if not UserInputService:GetFocusedTextBox() then
				PlacementController:Stop()
			end
			return
		end
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			placeNow()
		elseif input.UserInputType == Enum.UserInputType.Touch then
			touchStart = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input, processed)
		if not heldKind or input.UserInputType ~= Enum.UserInputType.Touch or processed then
			return
		end
		local at = Vector2.new(input.Position.X, input.Position.Y)
		local start = touchStart
		touchStart = nil
		-- A drag moves the camera; only a tap places. Tap first shows the ghost there.
		if start and (at - start).Magnitude <= TAP_SLOP and not overGui(at) then
			local inset = game:GetService("GuiService"):GetGuiInset()
			local p = at + inset
			if pointer and (pointer - p).Magnitude < 40 then
				placeNow()
			else
				pointer = p
				update()
				if spotOk then
					placeNow()
				end
			end
		end
	end)
end

return PlacementController
