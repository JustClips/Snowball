--!strict
-- Daily, Gifts (playtime), Lucky Wheel and Codes: one window each (Dev's rule), opened
-- from a button column on the left of the HUD with red count badges. The wheel also opens
-- from the plaza stand's prompt. Placeholder look made by Ui; ForgeUI art replaces it.
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Rewards = require(Shared.Config.Rewards)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local RewardsController = {}

local windows: { [string]: Frame } = {}
local buttons: { [string]: TextButton } = {}
local dailyCards: { Frame } = {}
local dailyClaim: TextButton
local dailyInfo: TextLabel
local giftRows: { { frame: Frame, button: TextButton } } = {}
local wheelRows: { Frame } = {}
local wheelSpin: TextButton
local wheelInfo: TextLabel
local codeBox: TextBox
local spinning = false
local snapAt = 0 -- os.clock() when the last Rewards snapshot arrived
local snapPlaytime = 0

local function invoke(action: string, arg: any?): (boolean, string?, any)
	local ok, why, extra = Net.func("Rewards"):InvokeServer(action, arg)
	if why then
		Ui.toast(why, if ok then "Good" else "Bad")
	end
	return ok, why, extra
end

local function badge(button: TextButton, count: number)
	local b = button:FindFirstChild("Badge") :: TextLabel?
	if count <= 0 then
		if b then
			b.Visible = false
		end
		return
	end
	if not b then
		local nb = Ui.label({
			Name = "Badge",
			Size = UDim2.fromOffset(24, 24),
			Position = UDim2.new(1, -16, 0, -8),
			BackgroundTransparency = 0,
			BackgroundColor3 = Ui.Colors.Red,
			Text = "",
			ZIndex = 5,
		})
		nb.Parent = button
		b = nb
	end
	local bb = b :: TextLabel
	bb.Visible = true
	bb.Text = tostring(count)
end

local function playtimeNow(): number
	return snapPlaytime + math.floor(os.clock() - snapAt)
end

local function toggle(name: string)
	local w = windows[name]
	if w.Visible then
		Ui.closeWindow(w)
	else
		Ui.openWindow(w)
		Net.event("Analytics"):FireServer("Open", name)
	end
end

function RewardsController:Open(name: string)
	if windows[name] and not windows[name].Visible then
		toggle(name)
	end
end

-------------------------------------------------------------------------- render

local function renderDaily(r)
	for i, card in dailyCards do
		local done = i < r.DailyIndex or (i == r.DailyIndex and not r.DailyReady)
		card.BackgroundColor3 = if i == r.DailyIndex and r.DailyReady
			then Ui.Colors.Green
			elseif done then Ui.Colors.PanelDark
			else Ui.Colors.Panel
		local text = Rewards.describe(Rewards.Daily[i])
		if i == 7 and r.DailyHuge then
			text = "Huge " .. text
		end
		(card:FindFirstChild("Reward") :: TextLabel).Text = text
	end
	dailyClaim.Visible = r.DailyReady
	if r.DailyReady then
		dailyInfo.Text = `Streak: {r.DailyStreak} days. Claim day {r.DailyIndex}!`
	else
		dailyInfo.Text = `Next reward in {Format.time(math.max(0, r.DailyNextAt - State.now()))}`
	end
end

local function renderGifts(r)
	local ready = 0
	local played = playtimeNow()
	for i, row in giftRows do
		local entry = Rewards.Playtime[i]
		local left = entry.Minutes * 60 - played
		local claimed = r.PlaytimeClaimed[i]
		if claimed then
			Ui.setText(row.button, "CLAIMED")
			row.button.BackgroundColor3 = Ui.Colors.PanelDark
		elseif left <= 0 then
			ready += 1
			Ui.setText(row.button, "CLAIM")
			row.button.BackgroundColor3 = Ui.Colors.Green
		else
			Ui.setText(row.button, Format.time(left))
			row.button.BackgroundColor3 = Ui.Colors.Panel
		end
	end
	return ready
end

local function renderWheel(r)
	local free = r.FreeSpin
	if free then
		Ui.setText(wheelSpin, "FREE SPIN")
	else
		Ui.setText(wheelSpin, `SPIN ({r.Spins})`)
	end
	if free then
		wheelInfo.Text = "Your free spin is ready!"
	elseif r.FreeSpinAt then
		wheelInfo.Text = `Free spin in {Format.time(math.max(0, r.FreeSpinAt - State.now()))}`
	else
		wheelInfo.Text = ""
	end
end

local function render()
	local data = State.data
	local r = data and data.Rewards
	if not r then
		return
	end
	renderDaily(r)
	local giftsReady = renderGifts(r)
	renderWheel(r)
	badge(buttons.Daily, if r.DailyReady then 1 else 0)
	badge(buttons.Gifts, giftsReady)
	badge(buttons.Wheel, (if r.FreeSpin then 1 else 0) + (r.Spins or 0))
	local text = if r.FreeSpin then "SPIN" elseif r.FreeSpinAt then Format.time(math.max(0, r.FreeSpinAt - State.now())) else "SPIN"
	Ui.setText(buttons.Wheel, text)
end

-------------------------------------------------------------------------- build

local function buildDaily(gui: ScreenGui)
	local window, body = Ui.window(gui, "Daily", "DAILY REWARDS", Vector2.new(600, 400))
	windows.Daily = window
	local grid = Ui.frame({ Name = "Grid", Size = UDim2.new(1, -16, 0, 230), Position = UDim2.fromOffset(8, 4), BackgroundTransparency = 1 })
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(134, 108)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	grid.Parent = body
	for i = 1, #Rewards.Daily do
		local card = Ui.frame({ Name = "Day" .. i, LayoutOrder = i, BackgroundColor3 = Ui.Colors.Panel })
		Ui.stroke(card, 2)
		Ui.label({ Name = "Day", Size = UDim2.new(1, -8, 0, 26), Position = UDim2.fromOffset(4, 4), Text = `DAY {i}` }).Parent = card
		Ui.label({
			Name = "Reward",
			Size = UDim2.new(1, -8, 1, -38),
			Position = UDim2.fromOffset(4, 34),
			Text = "",
			TextWrapped = true,
			TextColor3 = if i == 7 then Ui.Colors.Gold else Ui.Colors.Ice,
		}).Parent = card
		card.Parent = grid
		dailyCards[i] = card
	end
	dailyInfo = Ui.label({ Name = "Info", Size = UDim2.new(1, -16, 0, 28), Position = UDim2.new(0, 8, 1, -100), Text = "" })
	dailyInfo.Parent = body
	dailyClaim = Ui.button({
		Name = "Claim",
		Size = UDim2.fromOffset(220, 60),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		BackgroundColor3 = Ui.Colors.Green,
	}, "CLAIM", function()
		invoke("ClaimDaily")
	end)
	dailyClaim.Parent = body
end

local function buildGifts(gui: ScreenGui)
	local window, body = Ui.window(gui, "Gifts", "PLAYTIME GIFTS", Vector2.new(480, 430))
	windows.Gifts = window
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = body
	for i, entry in Rewards.Playtime do
		local row = Ui.frame({ Name = "Gift" .. i, LayoutOrder = i, Size = UDim2.new(1, -8, 0, 54), BackgroundColor3 = Ui.Colors.PanelDark })
		Ui.stroke(row, 2)
		Ui.label({
			Size = UDim2.new(1, -170, 1, -10),
			Position = UDim2.fromOffset(8, 5),
			Text = `{entry.Minutes} min: {Rewards.describe(entry.Reward)}`,
			TextXAlignment = Enum.TextXAlignment.Left,
		}).Parent = row
		local button = Ui.button({
			Name = "Claim",
			Size = UDim2.fromOffset(150, 44),
			Position = UDim2.new(1, -156, 0, 5),
		}, "", function()
			invoke("ClaimPlaytime", i)
		end)
		button.Parent = row
		row.Parent = body
		giftRows[i] = { frame = row, button = button }
	end
end

local function buildWheel(gui: ScreenGui)
	local window, body = Ui.window(gui, "Wheel", "LUCKY WHEEL", Vector2.new(520, 560))
	windows.Wheel = window
	local total = Rewards.wheelTotal()
	for i, seg in Rewards.Wheel.Segments do
		local row = Ui.frame({
			Name = "Seg" .. i,
			Size = UDim2.new(1, -16, 0, 40),
			Position = UDim2.fromOffset(8, 4 + (i - 1) * 44),
			BackgroundColor3 = seg.Color,
		})
		Ui.stroke(row, 2)
		Ui.label({
			Size = UDim2.new(1, -90, 1, -8),
			Position = UDim2.fromOffset(8, 4),
			Text = Rewards.describe(seg.Reward),
			TextXAlignment = Enum.TextXAlignment.Left,
		}).Parent = row
		Ui.label({
			Size = UDim2.new(0, 76, 1, -8),
			Position = UDim2.new(1, -82, 0, 4),
			Text = `{math.floor(seg.Weight / total * 1000 + 0.5) / 10}%`,
		}).Parent = row
		row.Parent = body
		wheelRows[i] = row
	end
	wheelInfo = Ui.label({ Name = "Info", Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 362), Text = "" })
	wheelInfo.Parent = body
	wheelSpin = Ui.button({
		Name = "Spin",
		Size = UDim2.fromOffset(200, 56),
		Position = UDim2.fromOffset(8, 392),
		BackgroundColor3 = Ui.Colors.Green,
	}, "SPIN", function()
		if spinning then
			return
		end
		local ok, why, index = Net.func("Rewards"):InvokeServer("Spin")
		if not ok then
			if why then
				Ui.toast(why, "Bad")
			end
			return
		end
		-- The highlight runs down the list and slows onto the prize.
		spinning = true
		task.spawn(function()
			local count = #wheelRows
			local steps = count * 3 + (index - 1)
			local t0 = os.clock()
			local duration = Rewards.Wheel.SpinSeconds
			local last = 0
			while true do
				local p = math.min(1, (os.clock() - t0) / duration)
				local step = math.floor((1 - (1 - p) ^ 3) * steps)
				if step ~= last then
					last = step
					Ui.sound("Tap")
				end
				local at = step % count + 1
				for i, row in wheelRows do
					(row :: any).UIStroke.Color = if i == at then Ui.Colors.Snow else Ui.Colors.Ink
					;(row :: any).UIStroke.Thickness = if i == at then 5 else 2
				end
				if p >= 1 then
					break
				end
				RunService.Heartbeat:Wait()
			end
			Ui.sound("Pop")
			if why then
				Ui.toast(why, "Good")
			end
			spinning = false
		end)
	end)
	wheelSpin.Parent = body
	-- Robux spin packs (hidden until the products exist).
	for i, key in { "WheelSpin1", "WheelSpin5", "WheelSpin10" } do
		local product = Products.ProductByKey[key]
		local b = Ui.button({
			Name = key,
			Size = UDim2.fromOffset(92, 56),
			Position = UDim2.fromOffset(216 + (i - 1) * 98, 392),
			BackgroundColor3 = Ui.Colors.Robux,
			Visible = product ~= nil and product.Id ~= 0,
		}, if product then `{product.Count}: {Ui.ROBUX}{product.Price}` else "", function()
			local ok, msg = Net.func("PromptPurchase"):InvokeServer(key)
			if not ok and msg then
				Ui.toast(msg, "Bad")
			end
		end)
		b.Parent = body
	end
end

local function buildCodes(gui: ScreenGui)
	local window, body = Ui.window(gui, "Codes", "CODES", Vector2.new(460, 210))
	windows.Codes = window
	codeBox = Instance.new("TextBox")
	codeBox.Name = "Code"
	codeBox.Size = UDim2.new(1, -16, 0, 56)
	codeBox.Position = UDim2.fromOffset(8, 6)
	codeBox.BackgroundColor3 = Ui.Colors.PanelDark
	codeBox.BorderSizePixel = 0
	codeBox.PlaceholderText = "Type a code"
	codeBox.Text = ""
	codeBox.TextColor3 = Ui.Colors.Snow
	codeBox.TextScaled = true
	codeBox.ClearTextOnFocus = false
	codeBox.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
	Ui.stroke(codeBox, 2)
	codeBox.Parent = body
	Ui.button({
		Name = "Redeem",
		Size = UDim2.fromOffset(200, 56),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 72),
		BackgroundColor3 = Ui.Colors.Green,
	}, "REDEEM", function()
		local ok, why = Net.func("RedeemCode"):InvokeServer(codeBox.Text)
		if why then
			Ui.toast(why, if ok then "Good" else "Bad")
		end
		if ok then
			codeBox.Text = ""
		end
	end).Parent = body
end

function RewardsController:Init()
	local gui = Ui.screen("Rewards", 20)
	buildDaily(gui)
	buildGifts(gui)
	buildWheel(gui)
	buildCodes(gui)

	-- Button column, left middle.
	local hud = Ui.screen("RewardButtons", 5)
	local root = Ui.root(hud)
	local column = Ui.frame({
		Name = "Column",
		Size = UDim2.fromOffset(104, 260),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 30),
		BackgroundTransparency = 1,
	})
	Ui.autoScale(column)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = column
	column.Parent = root
	for i, def in {
		{ "Daily", "DAILY", Ui.Colors.Yellow },
		{ "Gifts", "GIFTS", Color3.fromRGB(255, 120, 160) },
		{ "Wheel", "SPIN", Ui.Colors.Gold },
		{ "Codes", "CODES", Ui.Colors.Ice },
	} do
		local b = Ui.button({ Name = def[1], LayoutOrder = i, Size = UDim2.fromOffset(100, 54), BackgroundColor3 = def[3] }, def[2], function()
			toggle(def[1])
		end)
		b.Parent = column
		buttons[def[1]] = b
	end
end

function RewardsController:Start()
	State.observe(function(data)
		local r = data.Rewards
		if r then
			snapPlaytime = r.Playtime
			snapAt = os.clock()
		end
		render()
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 1 then
			acc = 0
			render()
		end
	end)
	-- The plaza stand opens the wheel window (works with streaming: no WaitForChild).
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "WheelPrompt" then
			RewardsController:Open("Wheel")
		end
	end)
end

return RewardsController
