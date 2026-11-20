--!strict
-- HUD (GAME_PLAN §7 items 1, 4, 6, 8): wallet plate (Cash, Power, how far you'd roll), boost
-- chips, the zone progress bar during a roll, and the core buttons. Placeholder look made
-- by Ui (ForgeUI art replaces it later; names stay the same).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local PowerCurve = require(Shared.PowerCurve)
local Zones = require(Shared.Config.Zones)
local AvalancheConfig = require(Shared.Config.Avalanche)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local HudController = {}

local C: any
local gui: ScreenGui
local cashLabel: TextLabel
local powerLabel: TextLabel
local rollLabel: TextLabel
local goalLabel: TextLabel
local chips: Frame
local zoneBar: Frame
local zoneFill: Frame
local zoneText: TextLabel
local zoneBest: Frame
local avaBar: Frame
local avaFill: Frame
local avaText: TextLabel

local function nextZone(distance: number)
	for _, z in Zones.List do
		if z.Start > distance then
			return z
		end
	end
	return nil
end

local function chip(name: string, text: string, color: Color3)
	local c = chips:FindFirstChild(name) :: Frame?
	if not c then
		local f = Ui.frame({ Name = name, Size = UDim2.fromOffset(104, 34), BackgroundColor3 = color })
		Ui.stroke(f, 3)
		Ui.label({ Name = "Text", Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), Text = text }).Parent =
			f
		f.Parent = chips
		c = f
	end
	((c :: Frame):FindFirstChild("Text") :: TextLabel).Text = text
end

local function clearChip(name: string)
	local c = chips:FindFirstChild(name)
	if c then
		c:Destroy()
	end
end

local function updateChips()
	local data = State.data
	if not data then
		return
	end
	local now = State.now()
	local pop = data.Boosts.Pop
	if type(pop) == "table" and pop.EndsAt > now then
		chip(
			"Pop",
			`x{pop.Mult} {Format.time(pop.EndsAt - now)}`,
			if pop.Mult >= 25 then Color3.fromRGB(255, 110, 200) else Ui.Colors.Ice
		)
	else
		clearChip("Pop")
	end
	for _, name in { "Train2x", "Cash2x" } do
		local ends = data.Boosts[name]
		if type(ends) == "number" and ends > now then
			chip(name, `{if name == "Train2x" then "2x PWR" else "2x $"} {Format.time(ends - now)}`, Ui.Colors.Yellow)
		else
			clearChip(name)
		end
	end
	local luck = State.server("ServerLuck")
	local luckEnds = State.server("ServerLuckEnds")
	if luck and luckEnds and luckEnds > now then
		chip("ServerLuck", `{luck}x LUCK {Format.time(luckEnds - now)}`, Ui.Colors.Green)
	else
		clearChip("ServerLuck")
	end
	local crown = data.Boosts.Crown
	if type(crown) == "number" and crown > now then
		chip("Crown", `CROWN {Format.time(crown - now)}`, Ui.Colors.Gold)
	else
		clearChip("Crown")
	end
end

-- Avalanche meter, top centre (ServerState: AvalancheMeter 0-1, AvalancheAt, AvalancheEnds).
local function updateAvalanche()
	local now = os.time()
	local at = State.server("AvalancheAt")
	local ends = State.server("AvalancheEnds")
	if at and now < at then
		avaFill.Size = UDim2.fromScale(1, 1)
		avaFill.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
		avaText.Text = `AVALANCHE IN {at - now}!`
	elseif ends and now < ends then
		avaFill.Size = UDim2.fromScale(math.clamp((ends - now) / AvalancheConfig.ActiveSeconds, 0, 1), 1)
		avaFill.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
		avaText.Text = `AVALANCHE! 2x LUCK {Format.time(ends - now)}`
	else
		local m = State.server("AvalancheMeter") or 0
		avaFill.Size = UDim2.fromScale(math.clamp(m, 0, 1), 1)
		avaFill.BackgroundColor3 = Ui.Colors.Ice
		avaText.Text = `AVALANCHE {math.floor(m * 100)}%`
	end
end

local function render(data)
	cashLabel.Text = Format.cash(data.Cash)
	powerLabel.Text = Format.big(BigNum.floor(data.Power)) .. " POWER"
	local zone = Zones.at(data.Distance)
	rollLabel.Text = `Rolls {math.floor(data.Distance)} studs ({zone.Name})`
	local nz = nextZone(data.Distance)
	if nz then
		goalLabel.Text = `{nz.Name} at {Format.big(PowerCurve.powerFor(nz.Start))} Power`
	else
		goalLabel.Text = "You can reach the Village!"
	end
	updateChips()
end

-- Zone bar during a roll: s = the ball's distance.
function HudController:ShowZoneBar(on: boolean)
	zoneBar.Visible = on
	avaBar.Visible = not on
end

function HudController:SetZoneProgress(s: number)
	local length = Zones.VillageWall
	zoneFill.Size = UDim2.fromScale(math.clamp(s / length, 0, 1), 1)
	zoneText.Text = `{math.floor(s)} studs · {Zones.at(s).Name}`
	local best = State.data and State.data.BestDistance or 0
	zoneBest.Position = UDim2.new(math.clamp(best / length, 0, 1), -2, 0, -4)
end

function HudController:Init(controllers)
	C = controllers
	gui = Ui.screen("Hud", 5)
	local root = Ui.root(gui)

	-- Wallet plate, top left.
	local wallet = Ui.frame({
		Name = "Wallet",
		Size = UDim2.fromOffset(300, 150),
		Position = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
	})
	Ui.autoScale(wallet)
	wallet.Parent = root
	local cashBox = Ui.frame({ Name = "Cash", Size = UDim2.fromOffset(280, 46), BackgroundColor3 = Ui.Colors.Green })
	Ui.stroke(cashBox, 3)
	cashLabel = Ui.label({
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		Text = "$0",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	cashLabel.Parent = cashBox
	cashBox.Parent = wallet
	local powerBox = Ui.frame({
		Name = "Power",
		Size = UDim2.fromOffset(280, 46),
		Position = UDim2.fromOffset(0, 52),
		BackgroundColor3 = Ui.Colors.Power,
	})
	Ui.stroke(powerBox, 3)
	powerLabel = Ui.label({
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		Text = "0 POWER",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	powerLabel.Parent = powerBox
	powerBox.Parent = wallet
	rollLabel = Ui.label({
		Name = "Roll",
		Size = UDim2.fromOffset(280, 22),
		Position = UDim2.fromOffset(2, 102),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	rollLabel.Parent = wallet
	goalLabel = Ui.label({
		Name = "Goal",
		Size = UDim2.fromOffset(280, 20),
		Position = UDim2.fromOffset(2, 126),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Ui.Colors.Yellow,
	})
	goalLabel.Parent = wallet

	-- Boost chips under the wallet.
	chips = Ui.frame({
		Name = "Chips",
		Size = UDim2.fromOffset(330, 40),
		Position = UDim2.fromOffset(12, 170),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.Parent = chips
	Ui.autoScale(chips)
	chips.Parent = root

	-- Zone bar, top centre (only during a roll).
	zoneBar = Ui.frame({
		Name = "ZoneBar",
		Size = UDim2.fromOffset(520, 26),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		BackgroundColor3 = Ui.Colors.PanelDark,
		Visible = false,
	})
	Ui.stroke(zoneBar, 3)
	Ui.autoScale(zoneBar)
	zoneFill = Ui.frame({ Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Ui.Colors.Ice })
	zoneFill.Parent = zoneBar
	for _, z in Zones.List do
		if z.Start > 0 then
			Ui.frame({
				Name = "Mark" .. z.Id,
				Size = UDim2.new(0, 3, 1, 0),
				Position = UDim2.fromScale(z.Start / Zones.VillageWall, 0),
				BackgroundColor3 = z.Color,
			}).Parent =
				zoneBar
		end
	end
	zoneBest = Ui.frame({ Name = "Best", Size = UDim2.new(0, 4, 1, 8), BackgroundColor3 = Ui.Colors.Gold })
	zoneBest.Parent = zoneBar
	zoneText = Ui.label({ Name = "Text", Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, 4), Text = "" })
	zoneText.Parent = zoneBar
	zoneBar.Parent = root

	-- Avalanche meter, top centre (hidden while the zone bar shows).
	avaBar = Ui.frame({
		Name = "Avalanche",
		Size = UDim2.fromOffset(300, 30),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		BackgroundColor3 = Ui.Colors.PanelDark,
	})
	Ui.stroke(avaBar, 3)
	Ui.autoScale(avaBar)
	avaFill = Ui.frame({ Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Ui.Colors.Ice })
	avaFill.Parent = avaBar
	avaText = Ui.label({ Name = "Text", Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), Text = "" })
	avaText.ZIndex = 2
	avaText.Parent = avaBar
	avaBar.Parent = root

	-- Core buttons, right side (mobile thumb reach).
	local buttons = Ui.frame({
		Name = "Buttons",
		Size = UDim2.fromOffset(130, 370),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		BackgroundTransparency = 1,
	})
	Ui.autoScale(buttons)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.Parent = buttons
	buttons.Parent = root
	local function core(name: string, text: string, color: Color3, fn: () -> ())
		Ui.button({ Name = name, Size = UDim2.fromOffset(124, 54), BackgroundColor3 = color }, text, fn).Parent =
			buttons
	end
	core("Upgrades", "UPGRADES", Ui.Colors.Yellow, function()
		C.UpgradesController:Toggle()
	end)
	core("Pets", "PETS", Color3.fromRGB(255, 150, 90), function()
		if C.PetsController then
			C.PetsController:Toggle()
		end
	end)
	core("Rebirth", "REBIRTH", Color3.fromRGB(200, 120, 255), function()
		C.RebirthController:Toggle()
	end)
	;((buttons :: any).Rebirth :: GuiObject).Visible = false
	core("Base", "BASE", Ui.Colors.Ice, function()
		Net.func("Teleport"):InvokeServer("Base")
	end)
	core("Roll", "ROLL", Ui.Colors.Green, function()
		Net.func("Teleport"):InvokeServer("Deck")
	end)
end

function HudController:Buttons(): Frame
	return (gui :: any).Root.Buttons
end

function HudController:Start()
	State.observe(render)
	Net.event("Notify").OnClientEvent:Connect(function(text, kind)
		Ui.toast(text, kind)
	end)
	Net.event("Announce").OnClientEvent:Connect(function(text)
		Ui.toast(text, "Info")
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.5 then
			acc = 0
			updateChips()
			updateAvalanche()
		end
	end)
	local _ = player
end

return HudController
