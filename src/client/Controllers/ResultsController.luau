--!strict
-- The Run Results card (GAME_PLAN §5.6, §7 item 9) and the big flash words during a roll
-- (SMASH!, BONK!, zone names). Buttons: ROLL AGAIN and BASE.
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
local lines: TextLabel
local title: TextLabel
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

function ResultsController:Show(result)
	if not result then
		return
	end
	local zone = Zones.List[result.Zone] or Zones.List[1]
	title.Text = if result.Village then "THE VILLAGE!" elseif result.Record then "NEW RECORD!" else "CRACK!"
	local eggs = if #result.Eggs > 0 then table.concat(result.Eggs, ", ") else "none"
	lines.Text =
		`{result.Distance} studs · {zone.Name}\nSize {result.Radius}\n+{Format.cash(result.Cash)}\nEggs: {eggs}`
	task.delay(0.8, function()
		Ui.openWindow(card)
	end)
end

function ResultsController:Init()
	gui = Ui.screen("Results", 15)
	local root = Ui.root(gui)
	flash = Ui.label({
		Name = "Flash",
		Size = UDim2.fromOffset(600, 64),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Text = "",
		Visible = false,
	})
	flashScale = Instance.new("UIScale")
	flashScale.Parent = flash
	flash.Parent = root

	local window, body = Ui.window(gui, "Card", "RESULTS", Vector2.new(420, 360))
	card = window
	title = Ui.label({ Name = "Big", Size = UDim2.new(1, 0, 0, 50), Text = "CRACK!", TextColor3 = Ui.Colors.Yellow })
	title.Parent = body
	lines = Ui.label({
		Name = "Lines",
		Size = UDim2.new(1, 0, 0, 160),
		Position = UDim2.fromOffset(0, 56),
		Text = "",
		TextScaled = true,
	})
	lines.Parent = body
	Ui.button(
		{
			Name = "Again",
			Size = UDim2.new(0.5, -6, 0, 60),
			Position = UDim2.new(0, 0, 1, -62),
			BackgroundColor3 = Ui.Colors.Green,
		},
		"ROLL AGAIN",
		function()
			Ui.closeWindow(card)
			local ok, why = Net.func("StartPack"):InvokeServer()
			if not ok and why then
				Ui.toast(why, "Bad")
			end
		end
	).Parent =
		body
	Ui.button(
		{
			Name = "Base",
			Size = UDim2.new(0.5, -6, 0, 60),
			Position = UDim2.new(0.5, 6, 1, -62),
			BackgroundColor3 = Ui.Colors.Ice,
		},
		"BASE",
		function()
			Ui.closeWindow(card)
			Net.func("Teleport"):InvokeServer("Base")
		end
	).Parent =
		body
end

return ResultsController
