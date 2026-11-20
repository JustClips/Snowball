--!strict
-- Boots client controllers: all Init() first, then all Start().
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

-- Our own bag hotbar replaces Roblox's backpack: without this, Roblox's 1-0 slot bar sits
-- on top of ours and ` opens its grey "Search" inventory over ROLL (Dev 2026-11-20).
task.spawn(function()
	for _ = 1, 20 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false) then
			return
		end
		task.wait(0.5)
	end
end)

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
	"LuckController",
	"ResultsController",
	"UpgradesController",
	"RebirthController",
	"RewardsController",
	"ShopController",
	"OfferController",
	"StarterPackController",
	"ContinueController",
	"PurchaseController",
	"InventoryController",
	"PlacementController",
	"PetWorldController",
	"HoldPoseController",
	"HoverController",
	"PromptController",
	"HatchController",
	"TutorialController",
	"RescueController",
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
