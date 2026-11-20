--!strict
-- The tutorial, copied from how Steal an Egg opens (Dev 2026-11-20, reference-study.md):
--   * ONE goal line at the top centre: an icon and a few words ("Step on your roller!").
--   * World goals: a trail of big red 3D arrows on the ground from you to the goal, and a
--     bouncing arrow over it.
--   * Button goals: the screen dims around the button (spotlight) and a pointing hand taps it.
-- The server decides the step (StateService): Train -> Roll -> Egg -> Roller -> Done.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local L = require(Shared.Config.HudLayout)
local Net = require(Shared.Net)
local World = require(Shared.Config.World)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local TutorialController = {}

local TRAIN_GOAL = 100 -- Power for step 1's bar (StateService moves on at 100)
local ARROW_GAP = 6 -- studs between ground arrows
local ARROW_MAX = 14

local C: any
local goal: Frame
local goalIcon: ImageLabel
local goalText: TextLabel
local progress: Frame
local progressFill: Frame
local action: TextButton
local actionKind: string? = nil
local spot: { Frame } = {}
local hand: ImageLabel
local marker: BillboardGui
local markerAnchor: Part
local arrows: { BasePart } = {}
local arrowFolder: Folder
local worldTarget: Vector3? = nil
local uiTarget: GuiObject? = nil

-------------------------------------------------------------------------- targets

local function baseIndex(): number?
	local i = player:GetAttribute("BaseIndex")
	return if type(i) == "number" then i else nil
end

local function rollerCFrame(i: number): CFrame
	return World.baseCFrame(i) * CFrame.new(World.RollerOffset)
end

-- What the step wants: goal words + icon, a world spot and/or a button.
local function stepGoal(data): (string?, string?, Vector3?, GuiObject?)
	local step = data.TutorialStep
	local i = baseIndex()
	local mode = C.HudController:Mode()
	if not i then
		return nil, nil, nil, nil
	end
	if step == "Train" then
		if player:GetAttribute("Training") then
			return "Power", "Train to 100 Power!", nil, nil
		end
		return "Power", "Step on your roller!", rollerCFrame(i).Position, nil
	elseif step == "Roll" then
		if mode == "Packing" then
			return "Icon_Snowball", "Tap when it's green!", nil, nil
		elseif mode == "Training" then
			return "Icon_Snowball", "Press STOP, then ROLL!", nil, C.HudController:Tile("Stop")
		end
		return "Icon_Snowball", "Roll your snowball!", nil, C.HudController:RollButton()
	elseif step == "Egg" then
		if actionKind == "OpenReady" then
			return "Egg", "Open your egg!", nil, action
		elseif actionKind == "PlaceEggs" then
			return "Egg", "Put your egg down!", nil, action
		end
		return "Egg", "Your egg is hatching!", World.eggSpot(i, 1).Position, nil
	elseif step == "Roller" then
		local post = rollerCFrame(i) * CFrame.new(10, 0, -3)
		return "Upgrade", "Upgrade your roller!", post.Position, nil
	end
	return nil, nil, nil, nil
end

-------------------------------------------------------------------------- update

local function update(data)
	if not data then
		return
	end
	local step = data.TutorialStep
	-- The Egg step's one button: put the egg on a pedestal, then open it.
	actionKind = nil
	if step == "Egg" then
		local ready = false
		for _, h in data.Hatching do
			if h.EndsAt <= State.now() then
				ready = true
			end
		end
		actionKind = if ready then "OpenReady" elseif next(data.Eggs) ~= nil then "PlaceEggs" else nil
		Ui.setText(action, if ready then "OPEN!" else "PLACE")
	end
	action.Visible = actionKind ~= nil
	local icon, words, pos, button = stepGoal(data)
	local mode = C.HudController:Mode()
	-- The top centre belongs to the LUCK readout while rolling.
	goal.Visible = words ~= nil and mode ~= "Rolling"
	if words then
		goalText.Text = words :: string
		goalIcon.Image = Ui.Images[icon :: string] or ""
	end
	progress.Visible = step == "Train" and player:GetAttribute("Training") == true
	if progress.Visible then
		local power = if data.Power then BigNum.toNumber(data.Power) else 0
		progressFill.Size = UDim2.fromScale(math.clamp(power / TRAIN_GOAL, 0, 1), 1)
	end
	worldTarget = if mode == "Normal" or mode == "Training" then pos else nil
	uiTarget = if button and button.Visible and (mode == "Normal" or mode == "Training") then button else nil
end

-------------------------------------------------------------------------- ground arrows

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundAt(p: Vector3): Vector3?
	local list: { Instance } = { arrowFolder }
	if player.Character then
		table.insert(list, player.Character)
	end
	local balls = Workspace:FindFirstChild("Balls")
	if balls then
		table.insert(list, balls)
	end
	rayParams.FilterDescendantsInstances = list
	local hit = Workspace:Raycast(p + Vector3.yAxis * 12, Vector3.yAxis * -40, rayParams)
	return hit and hit.Position
end

local function arrow(k: number): BasePart?
	local a = arrows[k]
	if a then
		return a
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Chevron") :: BasePart?
	if not template then
		return nil
	end
	local part = template:Clone()
	part.Parent = arrowFolder
	arrows[k] = part
	return part
end

local function layArrows()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local target = worldTarget
	local used = 0
	if root and target then
		local from = Vector3.new(root.Position.X, target.Y, root.Position.Z)
		local flat = target - from
		local dist = flat.Magnitude
		if dist > 10 then
			local dir = flat.Unit
			local assets = ReplicatedStorage:FindFirstChild("Assets")
			local template = assets and assets:FindFirstChild("Chevron") :: BasePart?
			local offset = if template then template.CFrame else CFrame.identity
			local t = os.clock()
			local d = 5
			while d < dist - 5 and used < ARROW_MAX do
				local p = from + dir * d
				local g = groundAt(p)
				if g then
					local part = arrow(used + 1)
					if not part then
						break
					end
					used += 1
					-- A wave runs along the trail toward the goal.
					local wave = (math.sin(t * 6 - d * 0.35) + 1) / 2
					part.CFrame = CFrame.lookAt(
						g + Vector3.yAxis * (0.05 + wave * 0.35),
						g + dir + Vector3.yAxis * (0.05 + wave * 0.35)
					) * offset
					part.Transparency = 0.25 * (1 - wave)
				end
				d += ARROW_GAP
			end
		end
	end
	for k = used + 1, #arrows do
		arrows[k].CFrame = CFrame.new(0, -500, 0)
	end
	-- The bouncing arrow over the goal.
	marker.Enabled = target ~= nil
	if target then
		markerAnchor.Position = target
		marker.StudsOffsetWorldSpace = Vector3.new(0, 9 + math.abs(math.sin(os.clock() * 4)) * 2.5, 0)
	end
end

-------------------------------------------------------------------------- spotlight

local function laySpotlight()
	local target = uiTarget
	local on = target ~= nil and target.Visible and target.AbsoluteSize.X > 0
	for _, f in spot do
		f.Visible = on
	end
	hand.Visible = on
	if not on or not target then
		return
	end
	local pad = 10
	local p = target.AbsolutePosition - Vector2.new(pad, pad)
	local s = target.AbsoluteSize + Vector2.new(pad * 2, pad * 2)
	local big = 5000
	-- top, bottom, left, right
	spot[1].Position = UDim2.fromOffset(p.X - big, p.Y - big)
	spot[1].Size = UDim2.fromOffset(s.X + big * 2, big)
	spot[2].Position = UDim2.fromOffset(p.X - big, p.Y + s.Y)
	spot[2].Size = UDim2.fromOffset(s.X + big * 2, big)
	spot[3].Position = UDim2.fromOffset(p.X - big, p.Y)
	spot[3].Size = UDim2.fromOffset(big, s.Y)
	spot[4].Position = UDim2.fromOffset(p.X + s.X, p.Y)
	spot[4].Size = UDim2.fromOffset(big, s.Y)
	-- The hand taps the button's right end (its tip is the image's top-left corner), kept
	-- clear of the words and on screen even for buttons at the bottom edge.
	local tap = math.abs(math.sin(os.clock() * 5))
	local size = math.clamp(s.Y * 0.9, 48, 96)
	hand.Size = UDim2.fromOffset(size, size)
	hand.Position = UDim2.fromOffset(p.X + s.X - pad * 2 + tap * 8, p.Y + s.Y * 0.45 + tap * 8)
end

-------------------------------------------------------------------------- build

function TutorialController:Init(controllers)
	C = controllers
	local gui = Ui.screen("Tutorial", 7)
	local root = Ui.root(gui)
	goal = Ui.frame({
		Name = "Goal",
		AnchorPoint = L.Goal.Anchor,
		Position = L.Goal.Pos,
		Size = UDim2.fromOffset(L.Goal.Size.X, L.Goal.Size.Y),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		Visible = false,
	})
	Ui.corner(goal, L.Goal.Size.Y // 2)
	Ui.autoScale(goal)
	goal.Parent = root
	goalIcon = Ui.icon("Power", {
		Size = UDim2.fromOffset(L.Goal.Size.Y + 14, L.Goal.Size.Y + 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 22, 0.5, 0),
		ZIndex = 3,
	})
	goalIcon.Parent = goal
	goalText = Ui.label({
		Name = "Text",
		Size = UDim2.new(1, -86, 0, 40),
		Position = UDim2.fromOffset(62, 9),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
	})
	goalText.Parent = goal
	progress = Ui.frame({
		Name = "Progress",
		Size = UDim2.new(1, -90, 0, 14),
		Position = UDim2.new(0, 62, 1, 4),
		BackgroundColor3 = Ui.Colors.PanelDark,
		Visible = false,
	})
	Ui.corner(progress, 7)
	Ui.stroke(progress, 2)
	progressFill = Ui.frame({ Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Ui.Colors.Blue })
	Ui.corner(progressFill, 7)
	progressFill.Parent = progress
	progress.Parent = goal
	action = Ui.button(
		{
			Name = "Action",
			Size = UDim2.fromOffset(170, 58),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 14),
			BackgroundColor3 = Ui.Colors.Green,
			Visible = false,
		},
		"",
		function()
			if actionKind then
				local ok, why = Net.func("Pets"):InvokeServer(actionKind)
				if not ok and why then
					Ui.toast(why, "Bad")
				end
			end
		end
	)
	action.Parent = goal

	-- Spotlight: four dim frames around the button, a pointing hand on top.
	local spotGui = Ui.screen("Spotlight", 30)
	for k = 1, 4 do
		local f = Ui.frame({
			Name = "Dim" .. k,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.5,
			Visible = false,
		})
		f.Parent = spotGui
		spot[k] = f
	end
	hand = Ui.icon("Tap", { Name = "Hand", Visible = false, ZIndex = 5 })
	hand.Parent = spotGui

	arrowFolder = Instance.new("Folder")
	arrowFolder.Name = "TutorialArrows"
	arrowFolder.Parent = Workspace
	markerAnchor = Instance.new("Part")
	markerAnchor.Name = "TutorialTarget"
	markerAnchor.Anchored = true
	markerAnchor.CanCollide = false
	markerAnchor.CanQuery = false
	markerAnchor.CanTouch = false
	markerAnchor.Transparency = 1
	markerAnchor.Size = Vector3.one
	markerAnchor.Parent = arrowFolder
	marker = Instance.new("BillboardGui")
	marker.Name = "Marker"
	marker.Size = UDim2.fromOffset(84, 84)
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.Enabled = false
	marker.Adornee = markerAnchor
	-- The chevron art points up; turned over it points down at the goal.
	Ui.icon("Fx_Chevron", { Size = UDim2.fromScale(1, 1), Rotation = 180 }).Parent = marker
	marker.Parent = markerAnchor
end

function TutorialController:Start()
	State.observe(update)
	for _, attr in { "Training", "RollPhase" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			update(State.data)
		end)
	end
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		update(State.data)
	end)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			update(State.data)
		end
		layArrows()
		laySpotlight()
	end)
end

return TutorialController
