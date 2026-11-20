--!strict
-- The tutorial (GAME_PLAN §4), icon first (Dev 2026-11-20: kids don't read): a goal chip
-- at the top with a big icon and ONE word, a progress bar where it helps, a bouncing pin
-- over the place to go and a beam path to it. The server decides the step (StateService);
-- the player does every step themselves.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Net = require(Shared.Net)
local World = require(Shared.Config.World)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local TutorialController = {}

local STEPS: { [string]: { n: number, icon: string, word: string } } = {
	Train = { n = 1, icon = "Power", word = "TRAIN!" },
	Roll = { n = 2, icon = "Roll", word = "ROLL!" },
	Egg = { n = 3, icon = "Egg", word = "HATCH!" },
	Roller = { n = 4, icon = "Upgrade", word = "UPGRADE!" },
	Pine = { n = 5, icon = "Target", word = "GO FAR!" },
}
local TRAIN_GOAL = 100 -- Power for step 1's bar (StateService moves on at 100)

local C: any
local card: Frame
local action: TextButton
local actionKind: string? = nil
local stepIcon: ImageLabel
local textLabel: TextLabel
local progress: Frame
local progressFill: Frame
local pin: BillboardGui
local beam: Beam
local a0: Attachment
local a1: Attachment
local targetPart: Part

local function target(step: string): Vector3?
	local index = player:GetAttribute("BaseIndex")
	if type(index) ~= "number" then
		return nil
	end
	if step == "Train" then
		return World.rollerSpot(index)
	elseif step == "Roll" or step == "Pine" then
		return World.DeckStand
	elseif step == "Egg" then
		return World.baseCenter(index)
	elseif step == "Roller" then
		return World.rollerSpot(index)
	end
	return nil
end

local function update(data)
	local step = data.TutorialStep
	local def = STEPS[step]
	card.Visible = def ~= nil
	if not def then
		beam.Enabled = false
		return
	end
	-- One button for the step's action where walking somewhere isn't the point.
	actionKind = nil
	if step == "Egg" then
		local bagEggs = next(data.Eggs) ~= nil
		local ready = false
		for _, h in data.Hatching do
			if h.EndsAt <= State.now() then
				ready = true
			end
		end
		actionKind = if ready then "OpenReady" elseif bagEggs then "PlaceEggs" else nil
		Ui.setText(action, if ready then "OPEN!" else "PLACE")
	end
	action.Visible = actionKind ~= nil
	stepIcon.Image = Ui.Images[def.icon] or ""
	textLabel.Text = def.word
	progress.Visible = step == "Train"
	if step == "Train" then
		local power = if data.Power then BigNum.toNumber(data.Power) else 0
		progressFill.Size = UDim2.fromScale(math.clamp(power / TRAIN_GOAL, 0, 1), 1)
	end
	local pos = target(step)
	-- No path while you're already there (training on the roller) or rolling.
	local busy = player:GetAttribute("Training") or player:GetAttribute("RollPhase")
	beam.Enabled = pos ~= nil and not busy
	pin.Enabled = pos ~= nil and not busy
	if pos then
		targetPart.Position = pos + Vector3.yAxis * 2
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and a0.Parent ~= root then
		a0.Parent = root
	end
end

function TutorialController:Init(controllers)
	C = controllers
	local gui = Ui.screen("Tutorial", 7)
	local root = Ui.root(gui)
	card = Ui.frame({
		Name = "Card",
		Size = UDim2.fromOffset(250, 70),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		BackgroundColor3 = Ui.Colors.Panel,
		Visible = false,
	})
	Ui.gradient(card, Ui.Colors.Panel)
	Ui.stroke(card, 3, Ui.Colors.Yellow)
	Ui.autoScale(card)
	stepIcon = Ui.icon("Power", { Size = UDim2.fromOffset(84, 84), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 20, 0.5, 0), ZIndex = 3 })
	stepIcon.Parent = card
	textLabel = Ui.label({ Name = "Text", Size = UDim2.new(1, -80, 0, 44), Position = UDim2.fromOffset(70, 6), Text = "", TextColor3 = Ui.Colors.Yellow })
	textLabel.Parent = card
	progress = Ui.frame({ Name = "Progress", Size = UDim2.new(1, -86, 0, 12), Position = UDim2.fromOffset(72, 52), BackgroundColor3 = Ui.Colors.PanelDark })
	Ui.stroke(progress, 2)
	progressFill = Ui.frame({ Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Ui.Colors.Power })
	progressFill.Parent = progress
	progress.Parent = card
	action = Ui.button({ Name = "Action", Size = UDim2.fromOffset(150, 56), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 10), BackgroundColor3 = Ui.Colors.Green, Visible = false }, "", function()
		if actionKind then
			local ok, why = Net.func("Pets"):InvokeServer(actionKind)
			if not ok and why then
				Ui.toast(why, "Bad")
			end
		end
	end)
	Ui.icon("Tap", { Size = UDim2.fromOffset(44, 44), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(1, -6, 1, -18), ZIndex = 4 }).Parent =
		action
	action.Parent = card
	card.Parent = root

	targetPart = Instance.new("Part")
	targetPart.Name = "TutorialTarget"
	targetPart.Anchored = true
	targetPart.CanCollide = false
	targetPart.CanQuery = false
	targetPart.Transparency = 1
	targetPart.Size = Vector3.one
	targetPart.Parent = Workspace
	a0 = Instance.new("Attachment")
	a1 = Instance.new("Attachment")
	a1.Parent = targetPart
	beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 2
	beam.Width1 = 2
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(Ui.Colors.Yellow)
	beam.LightEmission = 0.6
	beam.Enabled = false
	beam.Parent = targetPart
	-- A big pin bouncing over the place to go.
	pin = Instance.new("BillboardGui")
	pin.Name = "Pin"
	pin.Size = UDim2.fromOffset(90, 90)
	pin.StudsOffset = Vector3.new(0, 10, 0)
	pin.AlwaysOnTop = true
	pin.LightInfluence = 0
	pin.Enabled = false
	Ui.icon("Pin", { Size = UDim2.fromScale(1, 1) }).Parent = pin
	pin.Adornee = targetPart
	pin.Parent = targetPart
	task.spawn(function()
		while true do
			local t = os.clock()
			pin.StudsOffset = Vector3.new(0, 10 + math.abs(math.sin(t * 3)) * 3, 0)
			task.wait(1 / 30)
		end
	end)
end

function TutorialController:Start()
	State.observe(update)
	player:GetAttributeChangedSignal("Training"):Connect(function()
		if State.data then
			update(State.data)
		end
	end)
	player:GetAttributeChangedSignal("RollPhase"):Connect(function()
		if State.data then
			update(State.data)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if State.data and State.data.TutorialStep == "Egg" then
				update(State.data)
			end
		end
	end)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		if State.data then
			update(State.data)
		end
	end)
end

return TutorialController
