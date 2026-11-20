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
local needLabel: TextLabel
local gainLabel: TextLabel
local rebirthButton: TextButton
local skipButton: TextButton

local function line(body: Frame, name: string, y: number, h: number, color: Color3?): TextLabel
	local l = Ui.label({
		Name = name,
		Size = UDim2.new(1, -20, 0, h),
		Position = UDim2.fromOffset(10, y),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color or Ui.Colors.Snow,
		TextWrapped = true,
	})
	l.Parent = body
	return l
end

local function render(data)
	local n = data.Rebirths
	local cost = Economy.rebirthCost(n)
	local village = if data.ReachedVillage then "Village reached" else "Reach the Village"
	needLabel.Text = `Rebirth {n + 1} needs: {village} + {Format.cash(cost)}`
	gainLabel.Text = `You get: x{Format.big(Economy.rebirthTrainMult(n + 1))} training, x{Economy.rebirthCashMult(n + 1)} cash, +{math.floor(
		(n + 1) * Economy.RebirthLuckBonus * 100 + 0.5
	)}% luck`
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
		Ui.setText(skipButton, `SKIP {Ui.ROBUX}{product.Price}`)
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
	window, body = Ui.window(gui, "Window", "REBIRTH", Vector2.new(520, 330))
	needLabel = line(body, "Need", 6, 48, Ui.Colors.Yellow)
	gainLabel = line(body, "Gain", 58, 48, Ui.Colors.Green)
	line(body, "Reset", 110, 48, Ui.Colors.Ice).Text = "Resets Cash, Power, Snow Roller and Core. Keeps pets, eggs, slots and Robux rollers."
	rebirthButton = Ui.button({
		Name = "Rebirth",
		Size = UDim2.fromOffset(230, 64),
		Position = UDim2.new(0, 10, 1, -74),
		BackgroundColor3 = Ui.Colors.Green,
	}, "REBIRTH", function()
		local ok, why = Net.func("Rebirth"):InvokeServer()
		if ok then
			Ui.closeWindow(window)
		elseif why then
			Ui.toast(why, "Bad")
		end
	end)
	rebirthButton.Parent = body
	skipButton = Ui.button({
		Name = "Skip",
		Size = UDim2.fromOffset(230, 64),
		Position = UDim2.new(1, -240, 1, -74),
		BackgroundColor3 = Ui.Colors.Robux,
		Visible = false,
	}, "SKIP", function()
		local ok, why = Net.func("PromptPurchase"):InvokeServer("SkipRebirth")
		if not ok and why then
			Ui.toast(why, "Bad")
		end
	end)
	skipButton.Parent = body
end

function RebirthController:Start()
	State.observe(render)
end

return RebirthController
