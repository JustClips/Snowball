--!strict
-- Boots client controllers: all Init() first, then all Start().
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local State = require(Client:WaitForChild("State"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local ORDER = {
	"HudController",
	"TrainController",
	"PopController",
	"SteerController",
	"PackController",
	"TrackFxController",
	"BallController",
	"ResultsController",
	"UpgradesController",
	"PetsController",
	"FollowerController",
	"HatchController",
	"TutorialController",
}

local folder = Client:WaitForChild("Controllers")
local controllers: { [string]: any } = {}
for _, name in ORDER do
	controllers[name] = require(folder:WaitForChild(name) :: ModuleScript)
end

State.init()
for _, name in ORDER do
	local controller = controllers[name]
	if controller.Init then
		controller:Init(controllers)
	end
end
for _, name in ORDER do
	local controller = controllers[name]
	if controller.Start then
		task.spawn(controller.Start, controller)
	end
end
Net.event("Analytics"):FireServer("Loaded")
