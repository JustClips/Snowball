--!strict
-- The Run Results card (GAME_PLAN §5.6, §7 item 9) and the big flash words during a roll
-- (SMASH!, BONK!, zone names). Tiles: AGAIN and HOME.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Zones = require(Shared.Config.Zones)
local Ui = require(script.Parent.Parent.Ui)

local ResultsController = {}

local gui: ScreenGui
local card: Frame
local title: TextLabel
local distance: TextLabel
local bigScale: UIScale
local zoneLabel: TextLabel
local cashLabel: TextLabel
local eggsLabel: TextLabel
local eggsRow: Frame
local flash: TextLabel
local flashScale: UIScale

function ResultsController:Flash(text: string, color: Color3)
	flash.Text = text
	flash.TextColor3 = color
	flash.TextTransparency = 0
	flash.Visible = true
	flashScale.Scale = 0.5
	TweenService:Create(flashScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(0.8, function()
		if flash.Text == text then
			TweenService:Create(flash, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		end
	end)
end

-- The reveal (Dev: like Throw Food For Animals): the distance counts up big, then the
-- rewards pop in as icons. Icons and numbers only.
function ResultsController:Show(result)
	if not result then
		return
	end
	local zone = Zones.List[result.Zone] or Zones.List[1]
	title.Text = if result.Village then "VILLAGE!" elseif result.Record then "RECORD!" else ""
	title.Visible = title.Text ~= ""
	zoneLabel.Text = zone.Name
	zoneLabel.TextColor3 = zone.Color
	cashLabel.Text = "+" .. Format.cash(result.Cash)
	eggsLabel.Text = `x{#result.Eggs}`
	eggsRow.Visible = #result.Eggs > 0
	task.delay(0.6, function()
		Ui.openWindow(card)
		local target = result.Distance
		local t0 = os.clock()
		local duration = math.clamp(target / 600, 0.6, 1.8)
		while card.Visible do
			local p = math.min(1, (os.clock() - t0) / duration)
			distance.Text = tostring(math.floor(target * (1 - (1 - p) ^ 3)))
			if p >= 1 then
				break
			end
			task.wait()
		end
		Ui.sound("Pop")
		bigScale.Scale = 1.3
		TweenService:Create(bigScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
end

function ResultsController:Init()
	gui = Ui.screen("Results", 15)
	local root = Ui.root(gui)
	flash = Ui.label({
		Name = "Flash",
		Size = UDim2.fromOffset(600, 70),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Text = "",
		Visible = false,
	})
	flashScale = Instance.new("UIScale")
	flashScale.Parent = flash
	flash.Parent = root

	local window, body = Ui.window(gui, "Card", "", Vector2.new(440, 400))
	card = window
	title = Ui.label({ Name = "Title", Size = UDim2.new(1, 0, 0, 40), Text = "", TextColor3 = Ui.Colors.Gold })
	title.Parent = body
	distance =
		Ui.label({ Name = "Distance", Size = UDim2.new(1, 0, 0, 90), Position = UDim2.fromOffset(0, 40), Text = "0" })
	bigScale = Instance.new("UIScale")
	bigScale.Parent = distance
	distance.Parent = body
	zoneLabel =
		Ui.label({ Name = "Zone", Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 130), Text = "" })
	zoneLabel.Parent = body
	-- Reward row: cash icon + amount, egg icon + count.
	local rewards = Ui.frame({
		Name = "Rewards",
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.fromOffset(0, 170),
		BackgroundTransparency = 1,
	})
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 16)
	list.Parent = rewards
	local cashRow = Ui.frame({ Name = "Cash", Size = UDim2.fromOffset(190, 60), BackgroundTransparency = 1 })
	Ui.icon("Cash", { Size = UDim2.fromOffset(60, 60) }).Parent = cashRow
	cashLabel = Ui.label({
		Size = UDim2.new(1, -64, 1, -10),
		Position = UDim2.fromOffset(64, 5),
		Text = "",
		TextColor3 = Ui.Colors.Green,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	cashLabel.Parent = cashRow
	cashRow.Parent = rewards
	eggsRow = Ui.frame({ Name = "Eggs", Size = UDim2.fromOffset(130, 60), BackgroundTransparency = 1 })
	Ui.icon("GoldenEgg", { Size = UDim2.fromOffset(60, 60) }).Parent = eggsRow
	eggsLabel = Ui.label({
		Size = UDim2.new(1, -64, 1, -10),
		Position = UDim2.fromOffset(64, 5),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	eggsLabel.Parent = eggsRow
	eggsRow.Parent = rewards
	rewards.Parent = body

	local again = Ui.tile("Again", "Roll", "AGAIN", Color3.fromRGB(60, 190, 255), function()
		Ui.closeWindow(card)
		local ok, why = Net.func("StartPack"):InvokeServer()
		if not ok and why then
			Ui.toast(why, "Bad")
		end
	end, 96)
	again.AnchorPoint = Vector2.new(1, 1)
	again.Position = UDim2.new(0.5, -10, 1, 0)
	again.Parent = body
	local home = Ui.tile("Home", "Base", "HOME", Color3.fromRGB(90, 140, 255), function()
		Ui.closeWindow(card)
		Net.func("Teleport"):InvokeServer("Base")
	end, 96)
	home.AnchorPoint = Vector2.new(0, 1)
	home.Position = UDim2.new(0.5, 10, 1, 0)
	home.Parent = body
end

return ResultsController
