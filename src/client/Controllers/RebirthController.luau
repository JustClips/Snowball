--!strict
-- The Rebirth window (GAME_PLAN §5.11): what you need, what you get, what resets.
-- REBIRTH spends nothing extra (cash resets anyway); SKIP pays Robux when 30% is saved.
-- The HUD button only shows once the Village was reached or after the first rebirth.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Rollers = require(Shared.Config.Rollers)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local RebirthController = {}

local C: any
local window: Frame
local villageIcon: ImageLabel
local priceLabel: TextLabel
local trainLabel: TextLabel
local cashLabel: TextLabel
local luckLabel: TextLabel
local rebirthButton: TextButton
local skipButton: TextButton

-- An icon with a number next to it.
-- What you get: a dark stud well with the icon on top and the new value under it.
local function gain(parent: Frame, icon: string, x: number): TextLabel
	local well = Ui.frame({
		Name = icon,
		Size = UDim2.fromOffset(150, 120),
		Position = UDim2.fromOffset(x, 92),
		BackgroundColor3 = Ui.Colors.PanelDark,
	})
	Ui.block(well, nil, 3, 5)
	well.Parent = parent
	Ui.icon(icon, {
		Size = UDim2.fromOffset(62, 62),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		ZIndex = 3,
	}).Parent =
		well
	local l = Ui.label({
		Size = UDim2.new(1, -12, 0, 40),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Text = "",
		TextColor3 = Ui.Colors.Lime,
		ZIndex = 3,
	})
	Ui.maxText(l, 36)
	l.Parent = well
	return l
end

local function render(data)
	local n = data.Rebirths
	local cost = Economy.rebirthCost(n)
	villageIcon.Image = Ui.Images[if data.ReachedVillage then "Checkmark" else "Lock"] or ""
	priceLabel.Text = Format.cash(cost)
	priceLabel.TextColor3 = if BigNum.lt(data.Cash, cost) then Ui.Colors.Red else Ui.Colors.Green
	trainLabel.Text = `x{Format.big(Economy.rebirthTrainMult(n + 1))}`
	cashLabel.Text = `x{Economy.rebirthCashMult(n + 1)}`
	luckLabel.Text = `+{math.floor((n + 1) * Economy.RebirthLuckBonus * 100 + 0.5)}%`
	local ready = data.ReachedVillage and not BigNum.lt(data.Cash, cost)
	Ui.tint(rebirthButton, if ready then Ui.Colors.Green else Ui.Colors.Muted)
	local product = Products.ProductByKey.SkipRebirth
	local canSkip = data.ReachedVillage
		and not ready
		and not BigNum.lt(data.Cash, cost * Economy.SkipRebirthMinShare)
		and product ~= nil
		and product.Id ~= 0
	skipButton.Visible = canSkip
	-- REBIRTH sits in the middle; with the Robux skip it moves left to make room.
	rebirthButton.AnchorPoint = Vector2.new(if canSkip then 1 else 0.5, 1)
	rebirthButton.Position = UDim2.new(0.5, if canSkip then -6 else 0, 1, -8)
	if product then
		Ui.setText(skipButton, `{Ui.ROBUX}{product.Price}`)
	end
	local hud = C.HudController:Buttons():FindFirstChild("Rebirth")
	if hud then
		-- Also once a roller needs a rebirth, so "REBIRTH 2" on the upgrade leads somewhere.
		local nextRoller = Rollers.get(data.Roller + 1)
		local needed = nextRoller ~= nil and nextRoller.RebirthsNeeded > n
		local tile = hud :: GuiObject
		tile.Visible = data.ReachedVillage or n > 0 or needed
	end
end

function RebirthController:Toggle()
	if window.Visible then
		Ui.closeWindow(window)
	else
		Ui.openWindow(window)
		Net.event("Analytics"):FireServer("Open", "Rebirth")
	end
end

function RebirthController:Init(controllers)
	C = controllers
	local gui = Ui.screen("Rebirth", 20)
	local body
	window, body = Ui.window(gui, "Window", "REBIRTH", Vector2.new(520, 380))
	-- Need: the Village (lock / check) + the cash price.
	-- Need (top row, centred): the Village (lock / check) + the cash price.
	Ui.icon("Target", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(110, 8) }).Parent = body
	villageIcon = Ui.icon("Lock", { Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(146, 34) })
	villageIcon.Parent = body
	Ui.icon("Cash", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(200, 8) }).Parent = body
	priceLabel = Ui.label({
		Size = UDim2.fromOffset(170, 48),
		Position = UDim2.fromOffset(262, 12),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Ui.maxText(priceLabel, 40)
	priceLabel.Parent = body
	-- Get: training, cash, luck.
	trainLabel = gain(body, "Power", 6)
	cashLabel = gain(body, "Cash", 170)
	luckLabel = gain(body, "Luck", 334)
	rebirthButton = Ui.bigButton("Rebirth", "Rebirth", "REBIRTH", Ui.Colors.Green, function()
		local ok, why = Net.func("Rebirth"):InvokeServer()
		if ok then
			Ui.closeWindow(window)
		elseif why then
			Ui.toast(why, "Bad")
		end
	end, Vector2.new(240, 74))
	rebirthButton.AnchorPoint = Vector2.new(1, 1)
	rebirthButton.Position = UDim2.new(0.5, 0, 1, -8)
	rebirthButton.Parent = body
	skipButton = Ui.button(
		{
			Name = "Skip",
			Size = UDim2.fromOffset(170, 74),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0.5, 14, 1, -8),
			BackgroundColor3 = Ui.Colors.Robux,
			Visible = false,
		},
		"",
		function()
			local ok, why = Net.func("PromptPurchase"):InvokeServer("SkipRebirth")
			if not ok and why then
				Ui.toast(why, "Bad")
			end
		end
	)
	skipButton.Parent = body
end

function RebirthController:Start()
	State.observe(render)
end

return RebirthController
