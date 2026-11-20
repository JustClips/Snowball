--!strict
-- The HUD, laid out like Steal an Egg / Throw Food For Animals (Dev 2026-11-20,
-- reference-study.md). Every position comes from Config/HudLayout (tools/hud_preview.py
-- renders the same numbers on phone and PC screens to check for overlaps):
--   bottom-left   Power + cash numbers with no panel
--   left rail     Shop / Upgrade / Home / Rebirth tiles, word under each tile
--   right rail    Daily / Gifts / Spin / Codes (RewardsController adds them)
--   top-right     Avalanche bar + boost chips
--   top centre    the tutorial goal line (TutorialController), toasts under it
--   bottom centre ONE contextual button: ROLL (snowball) normally, red STOP while training
-- Modes: Normal, Training (STOP), Packing (meter only), Rolling (LUCK + zone, nothing else).
-- Never shows a distance (Dev: "why does it show go far"): during a roll the top shows the
-- luck multiplier rising and the zone you are in, like Throw Food.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AvalancheConfig = require(Shared.Config.Avalanche)
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local L = require(Shared.Config.HudLayout)
local Net = require(Shared.Net)
local Zones = require(Shared.Config.Zones)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local HudController = {}

local C: any
local gui: ScreenGui
local cashLabel: TextLabel
local incomeLabel: TextLabel
local powerLabel: TextLabel
local stats: Frame
local chips: Frame
local topRight: Frame
local leftRail: Frame
local rightRail: Frame
local action: Frame
local rollButton: TextButton
local stopButton: TextButton
local avaFill: Frame
local avaText: TextLabel
local luckBox: Frame
local luckValue: TextLabel
local luckScale: UIScale
local zonePill: Frame
local zoneName: TextLabel
local tiles: { [string]: GuiObject } = {}
local mode = "Normal"
local rolling = false
local runLuck = 1
local lastZone = 0

local function place(object: GuiObject, def: any)
	object.AnchorPoint = def.Anchor
	object.Position = def.Pos
	object.Size = UDim2.fromOffset(def.Size.X, def.Size.Y)
end

-------------------------------------------------------------------------- chips

local function chip(name: string, icon: string, text: string, color: Color3)
	local c = chips:FindFirstChild(name) :: Frame?
	if not c then
		local f = Ui.frame({ Name = name, Size = UDim2.fromOffset(L.Chip.X, L.Chip.Y), BackgroundColor3 = color })
		Ui.block(f, nil, 2.5, 4)
		Ui.icon(icon, {
			Size = UDim2.fromOffset(L.Chip.Y + 4, L.Chip.Y + 4),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -8, 0.5, -1),
			ZIndex = 3,
		}).Parent =
			f
		local t = Ui.label({
			Name = "Text",
			Size = UDim2.new(1, -L.Chip.Y + 2, 1, -10),
			Position = UDim2.fromOffset(L.Chip.Y - 6, 3),
			Text = text,
			ZIndex = 3,
		})
		Ui.maxText(t, 22)
		t.Parent = f
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
			"Bolt",
			`x{pop.Mult} {Format.time(pop.EndsAt - now)}`,
			if pop.Mult >= 25 then Color3.fromRGB(255, 110, 200) else Ui.Colors.Blue
		)
	else
		clearChip("Pop")
	end
	local timed = {
		{ "Train2x", "Power", Ui.Colors.Power },
		{ "Cash2x", "Cash", Ui.Colors.Green },
		{ "Crown", "Crown", Ui.Colors.Gold },
	}
	for _, t in timed do
		local ends = data.Boosts[t[1]]
		if type(ends) == "number" and ends > now then
			chip(t[1], t[2], (if t[1] == "Crown" then "" else "2x ") .. Format.time(ends - now), t[3])
		else
			clearChip(t[1])
		end
	end
	local luck = State.server("ServerLuck")
	local luckEnds = State.server("ServerLuckEnds")
	if luck and luckEnds and luckEnds > now then
		chip("ServerLuck", "Luck", `x{luck} {Format.time(luckEnds - now)}`, Ui.Colors.Green)
	else
		clearChip("ServerLuck")
	end
end

-- Avalanche bar: storm icon + fill. Text only for the countdown numbers.
local function updateAvalanche()
	local now = os.time()
	local at = State.server("AvalancheAt")
	local ends = State.server("AvalancheEnds")
	if at and now < at then
		avaFill.Size = UDim2.fromScale(1, 1)
		avaFill.BackgroundColor3 = Ui.Colors.Red
		avaText.Text = `{at - now}!`
	elseif ends and now < ends then
		avaFill.Size = UDim2.fromScale(math.clamp((ends - now) / AvalancheConfig.ActiveSeconds, 0, 1), 1)
		avaFill.BackgroundColor3 = Ui.Colors.Red
		avaText.Text = `x2 {Format.time(ends - now)}`
	else
		local m = State.server("AvalancheMeter") or 0
		avaFill.Size = UDim2.fromScale(math.clamp(m, 0, 1), 1)
		avaFill.BackgroundColor3 = Ui.Colors.Blue
		avaText.Text = `{math.floor(m * 100)}%`
	end
end

local function render(data)
	cashLabel.Text = Format.cash(data.Cash)
	powerLabel.Text = Format.big(BigNum.floor(data.Power))
	updateChips()
end

-------------------------------------------------------------------------- modes

local function applyMode(m: string)
	if m == mode then
		return
	end
	mode = m
	local normal = m == "Normal"
	-- Prompts only when you are free to walk around (Dev: training turns them all off).
	ProximityPromptService.Enabled = normal
	leftRail.Visible = normal or m == "Training"
	rightRail.Visible = normal or m == "Training"
	topRight.Visible = normal or m == "Training"
	action.Visible = normal or m == "Training"
	rollButton.Visible = normal
	stopButton.Visible = m == "Training"
	luckBox.Visible = m == "Rolling"
	zonePill.Visible = m == "Rolling"
	-- While rolling only Power stays (Throw Food hides everything else during the flight).
	stats.Visible = true
	local cashRow = stats:FindFirstChild("Cash") :: GuiObject?
	if cashRow then
		cashRow.Visible = m ~= "Rolling"
	end
	if m == "Training" then
		local scale = stopButton:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 0.5
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end
end

local function currentMode(): string
	local phase = player:GetAttribute("RollPhase")
	if rolling or phase == "Rolling" or phase == "Stopped" or phase == "Cracking" then
		return "Rolling"
	elseif phase == "Packing" then
		return "Packing"
	elseif player:GetAttribute("Training") then
		return "Training"
	elseif player:GetAttribute("Rescue") then
		return "Rescue" -- carrying eggs home past the yeti (RescueController draws its own HUD)
	end
	return "Normal"
end

function HudController:Mode(): string
	return mode
end

-------------------------------------------------------------------------- public

-- Compatibility for older callers: the mode now follows the player's state by itself.
function HudController:SetDeck(_on: boolean) end
function HudController:SetPacking(_on: boolean) end

function HudController:ShowZoneBar(on: boolean, info: any?)
	rolling = on
	if on then
		runLuck = if info and type(info.Luck) == "number" then info.Luck else 1
		lastZone = 0
	end
	applyMode(currentMode())
end

function HudController:SetZoneProgress(s: number)
	-- How far you've rolled (Dev 2026-11-20: "92.9KX LUCK" meant nothing to players).
	luckValue.Text = `{Format.number(math.floor(s))}m`
	local zone = Zones.at(s)
	if zone.Index ~= lastZone then
		lastZone = zone.Index
		zoneName.Text = zone.Name
		Ui.tint(zonePill, zone.Color)
		luckScale.Scale = 1.35
		TweenService:Create(luckScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
end

function HudController:Buttons(): Frame
	return leftRail
end

function HudController:Tile(name: string): GuiObject?
	return tiles[name]
end

function HudController:RollButton(): GuiObject
	return rollButton
end

function HudController:Badge(name: string, count: number)
	local t = tiles[name]
	if t then
		Ui.badge(t, count)
	end
end

-- Other controllers add tiles: order 1-4 go on the left rail, 5+ on the right rail.
function HudController:AddTile(
	name: string,
	icon: string,
	word: string,
	color: Color3,
	order: number,
	fn: () -> ()
): TextButton
	-- UIGridLayout forces every child to the cell size, so the tile sits in a holder the
	-- size of the cell (tile + its word underneath); the tile itself stays square on top
	-- and its word gets its own row space (Dev 2026-11-20: words were hidden under tiles).
	local holder = Ui.frame({ Name = name, BackgroundTransparency = 1 })
	holder.LayoutOrder = order
	local t = Ui.tile(name, icon, word, color, fn, L.Tile)
	t.Name = "Button"
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.new(0.5, 0, 0, 0)
	t.Parent = holder
	holder.Parent = if order >= 5 then rightRail else leftRail
	tiles[name] = t
	return t
end

-------------------------------------------------------------------------- build

local function rail(name: string, def: any): Frame
	local f = Ui.frame({ Name = name, BackgroundTransparency = 1 })
	place(f, def)
	Ui.autoScale(f)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(L.Tile, L.Tile + L.TileWord)
	grid.CellPadding = UDim2.fromOffset(L.TileGap, L.TileGap)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = def.Anchor.X > 0.5 and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left
	grid.VerticalAlignment = Enum.VerticalAlignment.Center
	grid.FillDirectionMaxCells = 2
	grid.Parent = f
	return f
end

function HudController:Init(controllers)
	C = controllers
	gui = Ui.screen("Hud", 5)
	local root = Ui.root(gui)

	-- Bottom-left: Power and cash, no panels (Steal an Egg).
	stats = Ui.frame({ Name = "Stats", BackgroundTransparency = 1 })
	place(stats, L.Stats)
	Ui.autoScale(stats)
	stats.Parent = root
	local cash, cv = Ui.stat("Cash", "Cash", Color3.fromRGB(110, 235, 90), L.Stats.Size.X)
	cash.Position = UDim2.fromOffset(0, 0)
	cash.Parent = stats
	cashLabel = cv
	local cashButton = Instance.new("TextButton")
	cashButton.Name = "Open"
	cashButton.BackgroundTransparency = 1
	cashButton.Text = ""
	cashButton.Size = UDim2.fromScale(1, 1)
	cashButton.ZIndex = 5
	cashButton.Activated:Connect(function()
		C.ShopController:Toggle("Cash")
	end)
	cashButton.Parent = cash
	-- Steal an Egg: what your pets earn, small and green under the cash (Dev 2026-11-20).
	incomeLabel = Ui.label({
		Name = "Income",
		Size = UDim2.new(1, -58, 0, 22),
		Position = UDim2.fromOffset(58, 44),
		Text = "+$0/s",
		TextColor3 = Color3.fromRGB(150, 255, 120),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	incomeLabel.Parent = cash
	local function showIncome()
		local rate = player:GetAttribute("IncomePerSec") or 0
		incomeLabel.Text = `+{Format.cash(rate)}/s`
		incomeLabel.Visible = rate > 0
	end
	player:GetAttributeChangedSignal("IncomePerSec"):Connect(function()
		showIncome()
		local sc = incomeLabel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		sc.Parent = incomeLabel
		sc.Scale = 1.25
		TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	showIncome()
	local power, pv = Ui.stat("Power", "Power", Color3.fromRGB(120, 210, 255), L.Stats.Size.X)
	power.Position = UDim2.fromOffset(0, L.StatRow)
	power.Parent = stats
	powerLabel = pv

	-- Top-right: Avalanche bar, boost chips under it.
	topRight = Ui.frame({ Name = "TopRight", BackgroundTransparency = 1 })
	place(topRight, L.TopRight)
	Ui.autoScale(topRight)
	topRight.Parent = root
	local avaBar = Ui.frame({
		Name = "Avalanche",
		Size = UDim2.new(1, -24, 0, 28),
		Position = UDim2.fromOffset(24, 4),
		BackgroundColor3 = Ui.Colors.PanelDark,
	})
	Ui.stroke(avaBar, 3)
	avaFill = Ui.frame({ Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Ui.Colors.Blue })
	Ui.gradient(avaFill)
	avaFill.Parent = avaBar
	avaText = Ui.label({
		Name = "Text",
		Size = UDim2.new(1, -40, 1, -6),
		Position = UDim2.fromOffset(32, 3),
		Text = "",
		ZIndex = 2,
	})
	Ui.maxText(avaText, 20)
	avaText.Parent = avaBar
	Ui.icon("Storm", {
		Size = UDim2.fromOffset(50, 50),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		ZIndex = 3,
	}).Parent =
		avaBar
	avaBar.Parent = topRight
	chips = Ui.frame({
		Name = "Chips",
		Size = UDim2.new(1, 0, 0, L.Chip.Y),
		Position = UDim2.fromOffset(0, 44),
		BackgroundTransparency = 1,
	})
	local chipGrid = Instance.new("UIGridLayout")
	chipGrid.CellSize = UDim2.fromOffset(L.Chip.X, L.Chip.Y)
	chipGrid.CellPadding = UDim2.fromOffset(8, 8)
	chipGrid.HorizontalAlignment = Enum.HorizontalAlignment.Right
	chipGrid.FillDirectionMaxCells = 2
	chipGrid.Parent = chips
	chips.Parent = topRight

	-- Rails.
	leftRail = rail("LeftRail", L.LeftRail)
	leftRail.Parent = root
	rightRail = rail("RightRail", L.RightRail)
	rightRail.Parent = root
	HudController:AddTile("Shop", "Shop", "Shop", Color3.fromRGB(255, 70, 90), 1, function()
		C.ShopController:Toggle()
	end)
	-- No Pets tile: eggs and pets live in the bag hotbar at the bottom (Dev 2026-11-20).
	HudController:AddTile("Upgrades", "Upgrade", "Upgrade", Color3.fromRGB(70, 200, 80), 2, function()
		C.UpgradesController:Toggle()
	end)
	-- TRAIN takes you to your roller (Dev 2026-11-20: Train where Home was, Home under
	-- Upgrade). Grid of 2: Shop | Upgrade, Train | Home.
	HudController:AddTile("Train", "Power", "Train", Color3.fromRGB(255, 150, 40), 3, function()
		local ok, why = Net.func("Teleport"):InvokeServer("Roller")
		if not ok and why then
			Ui.toast(why, "Bad")
		end
	end)
	HudController:AddTile("Base", "Base", "Home", Color3.fromRGB(70, 130, 255), 4, function()
		Net.func("Teleport"):InvokeServer("Base")
	end)
	local reb = HudController:AddTile("Rebirth", "Rebirth", "Rebirth", Color3.fromRGB(180, 90, 255), 4, function()
		C.RebirthController:Toggle()
	end)
	local rebHolder = reb.Parent :: Frame
	rebHolder.LayoutOrder = 10
	rebHolder.Visible = false

	-- Bottom centre: ONE button. ROLL (snowball) takes you onto your lane pad, which starts
	-- the launch. While training it is a red STOP.
	action = Ui.frame({ Name = "Action", BackgroundTransparency = 1 })
	place(action, L.Action)
	Ui.autoScale(action)
	action.Parent = root
	rollButton = Ui.bigButton("Roll", "Icon_Snowball", "ROLL", Ui.Colors.Blue, function()
		local ok, why = Net.func("Teleport"):InvokeServer("Deck")
		if not ok and why then
			Ui.toast(why, "Bad")
		end
	end, L.Action.Size)
	rollButton.Parent = action
	tiles.Roll = rollButton
	stopButton = Ui.bigButton("Stop", nil, "STOP", Ui.Colors.Red, function()
		Net.func("StopTraining"):InvokeServer()
	end, L.Action.Size)
	stopButton.Visible = false
	stopButton.Parent = action
	tiles.Stop = stopButton

	-- Top centre during a roll: the big LUCK multiplier and the zone you are in.
	luckBox = Ui.frame({ Name = "Luck", BackgroundTransparency = 1, Visible = false })
	place(luckBox, L.Luck)
	Ui.autoScale(luckBox)
	luckBox.Parent = root
	local luckPill = Ui.frame({
		Name = "Pill",
		Size = UDim2.new(1, 0, 0, 78),
		BackgroundColor3 = Ui.Colors.PanelDark,
		BackgroundTransparency = 0.15,
	})
	Ui.stroke(luckPill, 3)
	luckPill.Parent = luckBox
	luckScale = Instance.new("UIScale")
	luckScale.Parent = luckPill
	luckValue = Ui.label({
		Name = "Value",
		Size = UDim2.new(1, -20, 0, 54),
		Position = UDim2.fromOffset(10, 2),
		Text = "1X",
		TextColor3 = Ui.Colors.Yellow,
		ZIndex = 2,
	})
	Ui.maxText(luckValue, 52)
	local lst = luckValue:FindFirstChildOfClass("UIStroke")
	if lst then
		lst.Thickness = 3
	end
	luckValue.Parent = luckPill
	local lw = Ui.label({
		Name = "Word",
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 1, -24),
		Text = "DISTANCE",
		ZIndex = 2,
	})
	Ui.maxText(lw, 18)
	lw.Parent = luckPill
	zonePill = Ui.frame({
		Name = "Zone",
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 88),
		BackgroundColor3 = Ui.Colors.Blue,
		Visible = false,
	})
	Ui.block(zonePill, nil, 3, 4)
	zoneName = Ui.label({
		Name = "Text",
		Size = UDim2.new(1, -20, 1, -12),
		Position = UDim2.fromOffset(10, 4),
		Text = "",
		ZIndex = 3,
	})
	zoneName.Parent = zonePill
	zonePill.Parent = luckBox
	mode = ""
	applyMode("Normal")
end

function HudController:Start()
	State.observe(render)
	Ui.loop("Wind", true)
	Net.event("Notify").OnClientEvent:Connect(function(text, kind)
		if kind == "Good" then
			Ui.sound("Upgrade")
		end
		Ui.toast(text, kind)
	end)
	Net.event("Announce").OnClientEvent:Connect(function(text)
		Ui.toast(text, "Info")
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		applyMode(currentMode())
		acc += dt
		if acc >= 0.5 then
			acc = 0
			updateChips()
			updateAvalanche()
		end
		if mode == "Normal" then
			-- The ROLL button breathes so it reads as THE thing to press.
			local s = 1 + 0.035 * math.sin(os.clock() * 4)
			local scale = rollButton:FindFirstChildOfClass("UIScale")
			if scale and math.abs(scale.Scale - 1) < 0.05 then
				scale.Scale = s
			end
		end
	end)
end

return HudController
