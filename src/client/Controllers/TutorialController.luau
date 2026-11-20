--!strict
-- The tutorial card ("STEP n/5", one short line) and a beam path to where the step
-- happens (GAME_PLAN §4). The server decides the step (StateService); the player does every
-- step themselves.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local World = require(Shared.Config.World)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local TutorialController = {}

local STEPS: { [string]: { n: number, text: string } } = {
	Train = { n = 1, text = "Stand on your Snow Roller and TAP to train Power!" },
	Roll = { n = 2, text = "Power 100! Go to the launch deck and ROLL!" },
	Egg = { n = 3, text = "Place your frozen egg on your base and hatch it!" },
	Roller = { n = 4, text = "Open UPGRADES and get the Stone Roller (FREE)!" },
	Pine = { n = 5, text = "Train more and roll to the Pine Forest!" },
}

local C: any
local card: Frame
local action: TextButton
local actionKind: string? = nil
local stepLabel: TextLabel
local textLabel: TextLabel
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
		Ui.setText(action, if ready then "OPEN EGG!" else "PLACE EGG")
	elseif step == "Roller" then
		actionKind = "Upgrades"
		Ui.setText(action, "UPGRADES")
	end
	action.Visible = actionKind ~= nil
	stepLabel.Text = `STEP {def.n}/5`
	textLabel.Text = def.text
	local pos = target(step)
	-- No path while you're already there (training on the roller) or rolling.
	local busy = player:GetAttribute("Training") or player:GetAttribute("RollPhase")
	beam.Enabled = pos ~= nil and not busy
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
		Size = UDim2.fromOffset(520, 76),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		BackgroundColor3 = Ui.Colors.Panel,
		Visible = false,
	})
	Ui.stroke(card, 3, Ui.Colors.Yellow)
	Ui.autoScale(card)
	stepLabel = Ui.label({
		Name = "Step",
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, 4),
		Text = "",
		TextColor3 = Ui.Colors.Yellow,
	})
	stepLabel.Parent = card
	textLabel =
		Ui.label({ Name = "Text", Size = UDim2.new(1, -16, 0, 36), Position = UDim2.fromOffset(8, 34), Text = "" })
	textLabel.Parent = card
	action = Ui.button({ Name = "Action", Size = UDim2.fromOffset(170, 50), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 8), BackgroundColor3 = Ui.Colors.Green, Visible = false }, "", function()
		if actionKind == "Upgrades" then
			C.UpgradesController:Toggle()
		elseif actionKind then
			local ok, why = Net.func("Pets"):InvokeServer(actionKind)
			if not ok and why then
				Ui.toast(why, "Bad")
			end
		end
	end)
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
