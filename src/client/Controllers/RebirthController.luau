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
local function stat(parent: Frame, icon: string, x: number, y: number, color: Color3?): TextLabel
	Ui.icon(icon, { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(x, y) }).Parent = parent
	local l = Ui.label({
		Size = UDim2.fromOffset(110, 40),
		Position = UDim2.fromOffset(x + 60, y + 8),
		Text = "",
		TextColor3 = color or Ui.Colors.Snow,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	l.Parent = parent
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
	rebirthButton.BackgroundColor3 = if ready then Ui.Colors.Green else Ui.Colors.PanelDark
	local product = Products.ProductByKey.SkipRebirth
	local canSkip = data.ReachedVillage
		and not ready
		and not BigNum.lt(data.Cash, cost * Economy.SkipRebirthMinShare)
		and product ~= nil
		and product.Id ~= 0
	skipButton.Visible = canSkip
	if product then
		Ui.setText(skipButton, `{Ui.ROBUX}{product.Price}`)
	end
	local hud = C.HudController:Buttons():FindFirstChild("Rebirth")
	if hud then
		(hud :: GuiObject).Visible = data.ReachedVillage or n > 0
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
	Ui.icon("Target", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(10, 4) }).Parent = body
	villageIcon = Ui.icon("Lock", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(52, 22) })
	villageIcon.Parent = body
	priceLabel = stat(body, "Cash", 150, 4)
	-- Get: training, cash, luck.
	local arrow = Ui.icon(
		"Upgrade",
		{ Size = UDim2.fromOffset(50, 50), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70) }
	)
	arrow.Parent = body
	trainLabel = stat(body, "Power", 10, 130, Ui.Colors.Green)
	cashLabel = stat(body, "Cash", 175, 130, Ui.Colors.Green)
	luckLabel = stat(body, "Luck", 340, 130, Ui.Colors.Green)
	rebirthButton = Ui.tile("Rebirth", "Rebirth", "REBIRTH", Ui.Colors.Green, function()
		local ok, why = Net.func("Rebirth"):InvokeServer()
		if ok then
			Ui.closeWindow(window)
		elseif why then
			Ui.toast(why, "Bad")
		end
	end, 110)
	rebirthButton.AnchorPoint = Vector2.new(0.5, 1)
	rebirthButton.Position = UDim2.new(0.5, -70, 1, -4)
	rebirthButton.Parent = body
	skipButton = Ui.button(
		{
			Name = "Skip",
			Size = UDim2.fromOffset(130, 70),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0.5, 10, 1, -24),
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
