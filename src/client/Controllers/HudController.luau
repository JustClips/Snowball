--!strict
-- The HUD, icon first (Dev 2026-11-20: kids don't read). Zones follow the vault's HUD
-- Design note:
--   top centre    cash + Power pills, boost chips, the Avalanche bar
--   left edge     a 2-wide rail of square icon tiles (menus) with red badges
--   bottom centre one giant ROLL tile (+ a smaller BASE tile)
--   centre        kept clear for the world
-- During a roll the pills make room for the live distance bar (BallController).
-- Never shows how far the ball WILL roll (Dev): only what happened.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AvalancheConfig = require(Shared.Config.Avalanche)
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Zones = require(Shared.Config.Zones)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local HudController = {}

local C: any
local gui: ScreenGui
local cashLabel: TextLabel
local powerLabel: TextLabel
local chips: Frame
local rail: Frame
local action: Frame
local avaBar: Frame
local avaFill: Frame
local avaText: TextLabel
local zoneBar: Frame
local zoneFill: Frame
local zoneText: TextLabel
local zoneBest: Frame
local tiles: { [string]: TextButton } = {}
local onDeck = false
local packingOn = false

-------------------------------------------------------------------------- chips

local function chip(name: string, icon: string, text: string, color: Color3)
	local c = chips:FindFirstChild(name) :: Frame?
	if not c then
		local f = Ui.frame({ Name = name, Size = UDim2.fromOffset(112, 36), BackgroundColor3 = color })
		Ui.gradient(f, color)
		Ui.stroke(f, 3)
		Ui.icon(icon, { Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(1, 1), ZIndex = 2 }).Parent = f
		Ui.label({
			Name = "Text",
			Size = UDim2.new(1, -40, 1, -8),
			Position = UDim2.fromOffset(36, 4),
			Text = text,
			ZIndex = 2,
		}).Parent =
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
			"Bolt",
			`x{pop.Mult} {Format.time(pop.EndsAt - now)}`,
			if pop.Mult >= 25 then Color3.fromRGB(255, 110, 200) else Ui.Colors.Ice
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
			chip(t[1], t[2], (if t[1] == "Crown" then "" else "x2 ") .. Format.time(ends - now), t[3])
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
		avaFill.BackgroundColor3 = Ui.Colors.Ice
		avaText.Text = `{math.floor(m * 100)}%`
	end
end

local function render(data)
	cashLabel.Text = Format.cash(data.Cash)
	powerLabel.Text = Format.big(BigNum.floor(data.Power))
	updateChips()
end

-------------------------------------------------------------------------- public

-- On the deck the ROLL tile turns into a green GO! tile in the same spot.
function HudController:SetDeck(on: boolean)
	if on == onDeck then
		return
	end
	onDeck = on
	local roll = tiles.Roll
	if not roll then
		return
	end
	local color = if on then Ui.Colors.Green else Color3.fromRGB(60, 190, 255)
	roll.BackgroundColor3 = color
	local grad = roll:FindFirstChildOfClass("UIGradient")
	if grad then
		grad:Destroy()
	end
	Ui.gradient(roll, color)
	Ui.setText(roll, if on then "GO!" else "ROLL!")
end

-- While the power meter runs, the HUD buttons get out of its way.
function HudController:SetPacking(on: boolean)
	if on == packingOn then
		return
	end
	packingOn = on
	local show = not on and not zoneBar.Visible
	action.Visible = show
	rail.Visible = show
end

function HudController:ShowZoneBar(on: boolean)
	zoneBar.Visible = on
	avaBar.Visible = not on
	action.Visible = not on
	rail.Visible = not on
end

-- Live distance during a roll: what the ball HAS done (never a prediction).
function HudController:SetZoneProgress(s: number)
	local length = Zones.VillageWall
	zoneFill.Size = UDim2.fromScale(math.clamp(s / length, 0, 1), 1)
	zoneText.Text = `{math.floor(s)}`
	local best = State.data and State.data.BestDistance or 0
	zoneBest.Visible = best > 0
	zoneBest.Position = UDim2.new(math.clamp(best / length, 0, 1), -2, 0, -6)
end

function HudController:Buttons(): Frame
	return rail
end

function HudController:Tile(name: string): TextButton?
	return tiles[name]
end

function HudController:Badge(name: string, count: number)
	local t = tiles[name]
	if t then
		Ui.badge(t, count)
	end
end

-- Other controllers add their tiles to the rail (order = LayoutOrder).
function HudController:AddTile(
	name: string,
	icon: string,
	word: string,
	color: Color3,
	order: number,
	fn: () -> ()
): TextButton
	local t = Ui.tile(name, icon, word, color, fn)
	t.LayoutOrder = order
	t.Parent = rail
	tiles[name] = t
	return t
end

-------------------------------------------------------------------------- build

function HudController:Init(controllers)
	C = controllers
	gui = Ui.screen("Hud", 5)
	local root = Ui.root(gui)

	-- Top centre: cash + Power pills.
	local top = Ui.frame({
		Name = "Top",
		Size = UDim2.fromOffset(460, 150),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		BackgroundTransparency = 1,
	})
	Ui.autoScale(top)
	top.Parent = root
	local cash, cv = Ui.pill("Cash", "Cash", Ui.Colors.Green, 220, function()
		C.ShopController:Toggle("Cash")
	end)
	cash.Position = UDim2.fromOffset(10, 6)
	cash.Parent = top
	cashLabel = cv
	local power, pv = Ui.pill("Power", "Power", Ui.Colors.Power, 190)
	power.Position = UDim2.fromOffset(262, 6)
	power.Parent = top
	powerLabel = pv

	-- Boost chips under the pills.
	chips = Ui.frame({
		Name = "Chips",
		Size = UDim2.fromOffset(460, 36),
		Position = UDim2.fromOffset(0, 60),
		BackgroundTransparency = 1,
	})
	local chipList = Instance.new("UIListLayout")
	chipList.FillDirection = Enum.FillDirection.Horizontal
	chipList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	chipList.Padding = UDim.new(0, 6)
	chipList.Parent = chips
	chips.Parent = top

	-- Avalanche bar under the chips.
	avaBar = Ui.frame({
		Name = "Avalanche",
		Size = UDim2.fromOffset(240, 26),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 14, 0, 104),
		BackgroundColor3 = Ui.Colors.PanelDark,
	})
	Ui.stroke(avaBar, 3)
	avaFill = Ui.frame({ Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Ui.Colors.Ice })
	avaFill.Parent = avaBar
	avaText = Ui.label({
		Name = "Text",
		Size = UDim2.new(1, -8, 1, -4),
		Position = UDim2.fromOffset(4, 2),
		Text = "",
		ZIndex = 2,
	})
	avaText.Parent = avaBar
	Ui.icon("Storm", {
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, -6, 0.5, 0),
		ZIndex = 3,
	}).Parent =
		avaBar
	avaBar.Parent = top

	-- Live distance bar during a roll (replaces the top cluster's lower part).
	zoneBar = Ui.frame({
		Name = "ZoneBar",
		Size = UDim2.fromOffset(440, 30),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		BackgroundColor3 = Ui.Colors.PanelDark,
		Visible = false,
	})
	Ui.stroke(zoneBar, 3)
	zoneFill = Ui.frame({ Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Ui.Colors.Ice })
	Ui.gradient(zoneFill, Ui.Colors.Ice)
	zoneFill.Parent = zoneBar
	for _, z in Zones.List do
		if z.Start > 0 then
			Ui.frame({
				Name = "Mark" .. z.Id,
				Size = UDim2.new(0, 4, 1, 0),
				Position = UDim2.fromScale(z.Start / Zones.VillageWall, 0),
				BackgroundColor3 = z.Color,
			}).Parent =
				zoneBar
		end
	end
	zoneBest = Ui.frame({ Name = "Best", Size = UDim2.new(0, 4, 1, 12), BackgroundColor3 = Ui.Colors.Gold })
	zoneBest.Parent = zoneBar
	Ui.icon(
		"Trophy",
		{ Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 0) }
	).Parent =
		zoneBest
	-- The live number, big, under the bar: it counts up as the ball rolls.
	zoneText = Ui.label({
		Name = "Text",
		Size = UDim2.new(1, 0, 0, 56),
		Position = UDim2.new(0, 0, 1, 6),
		Text = "",
		TextColor3 = Ui.Colors.Snow,
	})
	zoneText.Parent = zoneBar
	zoneBar.Parent = top

	-- Left rail: 2-wide grid of icon tiles.
	rail = Ui.frame({
		Name = "Rail",
		Size = UDim2.fromOffset(172, 360),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 20),
		BackgroundTransparency = 1,
	})
	Ui.autoScale(rail)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(78, 78)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = rail
	rail.Parent = root
	HudController:AddTile("Shop", "Shop", "SHOP", Color3.fromRGB(255, 80, 100), 1, function()
		C.ShopController:Toggle()
	end)
	HudController:AddTile("Pets", "Pets", "PETS", Color3.fromRGB(255, 170, 60), 2, function()
		C.PetsController:Toggle()
	end)
	HudController:AddTile("Upgrades", "Upgrade", "UPGRADE", Color3.fromRGB(80, 200, 90), 3, function()
		C.UpgradesController:Toggle()
	end)
	HudController:AddTile("Rebirth", "Rebirth", "REBIRTH", Color3.fromRGB(180, 100, 255), 4, function()
		C.RebirthController:Toggle()
	end).Visible =
		false

	-- Bottom centre: the giant ROLL tile and a smaller BASE tile.
	action = Ui.frame({
		Name = "Action",
		Size = UDim2.fromOffset(240, 130),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		BackgroundTransparency = 1,
	})
	Ui.autoScale(action)
	action.Parent = root
	local roll = Ui.tile("Roll", "Roll", "ROLL!", Color3.fromRGB(60, 190, 255), function()
		if onDeck then
			-- On the launch deck the same tile is the GO button (one obvious action).
			local ok, why = Net.func("StartPack"):InvokeServer()
			if not ok and why then
				Ui.toast(why, "Bad")
			end
		else
			Net.func("Teleport"):InvokeServer("Deck")
		end
	end, 124)
	roll.Position = UDim2.fromOffset(0, 4)
	roll.Parent = action
	tiles.Roll = roll
	local base = Ui.tile("Base", "Base", "HOME", Color3.fromRGB(90, 140, 255), function()
		Net.func("Teleport"):InvokeServer("Base")
	end, 92)
	base.Position = UDim2.fromOffset(140, 36)
	base.Parent = action
	tiles.Base = base
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
end

return HudController
