--!strict
-- Daily, Gifts (playtime), Lucky Wheel and Codes: one window each (Dev's rule), opened
-- from the HUD rail with red count badges. The wheel also opens from the plaza stand.
-- Rebuilt 2026-11-20 after Dev's review ("timed gifts frame looks bad", "wheel spin doesn't
-- even have a wheel, copy it from Sweep the World"):
--   Gifts / Daily: big bright reward cards, sun rays behind a big prize (the real 3D egg for
--   eggs), the AMOUNT under it ($ from the server's snapshot), a status pill at the bottom
--   (timer / CLAIM! / a tick when claimed). Day 7 is the tall rainbow card.
--   Wheel: Sweep the World's wheel. A real wheel face (art/wheel_art.py) that spins and
--   lands on the server's wedge with a click per divider, a gold pointer, prizes and odds
--   on the wedges, a side panel with spins, SPIN!, Robux packs and the odds list, then a
--   YOU WON! card with rays, confetti and the exact prize.
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggLook = require(Shared.EggLook)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Rewards = require(Shared.Config.Rewards)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local RewardsController = {}

local C: any

local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 200, 50)
local PINK = Color3.fromRGB(255, 90, 200)
local DONE_DIM = Color3.fromRGB(10, 12, 30)
local CONFETTI = {
	Color3.fromRGB(255, 212, 59),
	Color3.fromRGB(255, 90, 200),
	Color3.fromRGB(76, 168, 255),
	Color3.fromRGB(92, 214, 92),
	Color3.fromRGB(255, 154, 60),
	Color3.fromRGB(197, 155, 255),
}
local STEP = 360 / #Rewards.Wheel.Segments

type Card = {
	frame: TextButton,
	amount: TextLabel,
	status: TextButton,
	done: Frame,
	pulse: UIScale,
}

local windows: { [string]: GuiObject } = {}
local buttons: { [string]: TextButton } = {}
local dailyCards: { Card } = {}
local giftCards: { Card } = {}
local wheelSpinButton: TextButton
local wheelSpins: TextLabel
local wheelFree: TextLabel
local spinner: Frame
local wheelArea: Frame
local oddsPanel: Frame
local prizeCard: Frame
local prizeToken = 0
local rotation = 0
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

local function playtimeNow(): number
	return snapPlaytime + math.floor(os.clock() - snapAt)
end

local function toggle(name: string)
	local w = windows[name]
	if w.Visible then
		Ui.closeWindow(w)
	else
		Ui.openWindow(w)
		local sc = w:FindFirstChild("Pop", true) :: UIScale?
		if sc then
			sc.Scale = 0.7
			TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		Net.event("Analytics"):FireServer("Open", name)
	end
end

function RewardsController:Open(name: string)
	if windows[name] and not windows[name].Visible then
		toggle(name)
	end
end

-------------------------------------------------------------------------- prize looks

-- The colour a reward's card is painted (eggs: their rarity colour).
local function rewardColor(r: Rewards.Reward): Color3
	local k = r.Kind
	if k == "Egg" then
		local def = Eggs.ByName[r.Rarity or ""]
		return if def then def.Color else Ui.Colors.Blue
	elseif k == "Cash" then
		return Color3.fromRGB(70, 200, 90)
	elseif k == "Boost" then
		return Color3.fromRGB(255, 140, 50)
	elseif k == "Charge" then
		return if r.Charge == "LuckyRoll" then Color3.fromRGB(60, 200, 120) else GOLD
	elseif k == "Spin" then
		return Color3.fromRGB(70, 170, 255)
	elseif k == "Pet" then
		return PINK
	elseif k == "Power" then
		return Color3.fromRGB(255, 110, 60)
	end
	return Ui.Colors.Blue
end

local function rewardImage(r: Rewards.Reward): string
	local k = r.Kind
	if k == "Cash" then
		return "Cash"
	elseif k == "Egg" then
		return "Egg"
	elseif k == "Spin" then
		return "Wheel"
	elseif k == "Pet" then
		return "Pets"
	elseif k == "Boost" then
		return if r.Boost == "Train2x" then "Power" else "Cash"
	elseif k == "Charge" then
		return if r.Charge == "LuckyRoll" then "Luck" else "Star"
	elseif k == "Power" then
		return "Power"
	end
	return "Gift"
end

-- Short amount text for one part of a reward ("$12.4K", "x2 Power 10m", "Rare Egg").
local function amountText(r: Rewards.Reward, cash: number?): string
	local k = r.Kind
	if k == "Cash" then
		return if cash then Format.cash(cash) else "Cash"
	elseif k == "Egg" then
		return `{r.Rarity} Egg`
	elseif k == "Spin" then
		return `+{r.Amount or 1} Spin{if (r.Amount or 1) > 1 then "s" else ""}`
	elseif k == "Pet" then
		return if r.Pet == "Daily" then "Red Panda" else r.Pet or "Pet"
	elseif k == "Boost" then
		return `x2 {if r.Boost == "Train2x" then "Power" else "Cash"} {r.Minutes}m`
	elseif k == "Charge" then
		return `{r.Amount}x {if r.Charge == "LuckyRoll" then "Lucky Roll" else "Golden Run"}`
	elseif k == "Power" then
		return "Power"
	end
	return ""
end

-- Even shorter, for the wheel wedges (they are narrow and turn with the wheel).
local function wedgeText(r: Rewards.Reward, cash: number?): string
	local k = r.Kind
	if k == "Cash" then
		return if cash then Format.cash(cash) else "Cash"
	elseif k == "Egg" then
		return r.Rarity or "Egg"
	elseif k == "Boost" then
		return `x2 {r.Minutes}m`
	elseif k == "Charge" or k == "Spin" then
		return `x{r.Amount or 1}`
	end
	return amountText(r, cash)
end

local function fullAmount(r: Rewards.Reward, cash: number?): string
	local text = amountText(r, if r.Kind == "Cash" then cash else nil)
	if r.Bonus then
		text ..= " + " .. fullAmount(r.Bonus, cash)
	end
	return text
end

-- The prize picture: the real Blender egg in a viewport for eggs, else the icon.
local function prizeView(r: Rewards.Reward, size: number, z: number): GuiObject
	if r.Kind == "Egg" then
		local vp = Instance.new("ViewportFrame")
		vp.Name = "Prize"
		vp.BackgroundTransparency = 1
		vp.Size = UDim2.fromOffset(size, size)
		vp.AnchorPoint = Vector2.new(0.5, 0.5)
		vp.Ambient = Color3.fromRGB(200, 210, 235)
		vp.LightColor = WHITE
		vp.LightDirection = Vector3.new(-1, -1, -1)
		vp.ZIndex = z
		-- The Blender egg for its rarity. The server shares them a moment after joining
		-- (ReplicatedStorage.EggModels), so wait for it instead of drawing a plain ball.
		task.spawn(function()
			local rarity = r.Rarity or "Common"
			local folder = ReplicatedStorage:WaitForChild("EggModels", 60)
			if folder then
				folder:WaitForChild(rarity, 30)
			end
			local model = EggLook.make(rarity)
			model:PivotTo(CFrame.new(0, -EggLook.Height / 2, 0) * CFrame.Angles(0, math.rad(25), math.rad(-8)))
			model.Parent = vp
		end)
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		cam.CFrame = CFrame.lookAt(Vector3.new(0, 0.3, 9.6), Vector3.new(0, 0, 0))
		cam.Parent = vp
		vp.CurrentCamera = cam
		return vp
	end
	local icon = Ui.icon(rewardImage(r), {
		Name = "Prize",
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z,
	})
	return icon
end

local function rays(parent: GuiObject, size: number, pos: UDim2, z: number, transparency: number?): ImageLabel
	local r = Ui.icon("Rays", {
		Name = "Rays",
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		ImageTransparency = transparency or 0.55,
		ZIndex = z,
	})
	r.Parent = parent
	return r
end

-------------------------------------------------------------------------- reward cards

-- A bright reward card: title on top, rays + big prize, the amount, a status pill.
local function makeCard(name: string, title: string, r: Rewards.Reward, w: number, h: number, big: boolean?): Card
	local color = rewardColor(r)
	local f = Instance.new("TextButton")
	f.Name = name
	f.Text = ""
	f.AutoButtonColor = false
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Size = UDim2.fromOffset(w, h)
	f.ClipsDescendants = true
	Ui.corner(f, 14)
	Ui.gradient(f, color)
	Ui.stroke(f, 3)
	local pulse = Instance.new("UIScale")
	pulse.Parent = f
	local prizeSize = if big then 150 else math.floor(math.min(w, h) * 0.5)
	local mid = UDim2.new(0.5, 0, 0.5, if big then -10 else -6)
	local rr = rays(f, prizeSize * 2, mid, 1, 0.5)
	rr.Name = "Rays"
	local t = Ui.label({
		Name = "Title",
		Size = UDim2.new(1, -10, 0, if big then 40 else 28),
		Position = UDim2.fromOffset(5, 4),
		Text = title,
		ZIndex = 3,
	})
	t.Parent = f
	if big then
		local best = Ui.label({
			Name = "Best",
			Size = UDim2.new(1, -20, 0, 26),
			Position = UDim2.fromOffset(10, 44),
			Rotation = -4,
			Text = "THE BEST!",
			TextColor3 = GOLD,
			ZIndex = 3,
		})
		best.Parent = f
		local rainbow = Instance.new("UIGradient")
		rainbow.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 126, 182)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 212, 59)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(124, 245, 200)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(127, 211, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(197, 155, 255)),
		})
		rainbow.Rotation = 35
		f.BackgroundColor3 = WHITE
		local g = f:FindFirstChildOfClass("UIGradient")
		if g then
			g:Destroy()
		end
		rainbow.Parent = f
	end
	-- Main prize + a small bonus badge in the corner.
	local prize = prizeView(r, prizeSize, 2)
	prize.Position = mid
	prize.Parent = f
	if r.Bonus then
		local bonus = prizeView(r.Bonus, math.floor(prizeSize * 0.5), 3)
		bonus.Position = UDim2.new(0.5, prizeSize * 0.42, 0.5, prizeSize * 0.18 - 6)
		bonus.Parent = f
	end
	local amount = Ui.label({
		Name = "Amount",
		Size = UDim2.new(1, -10, 0, if big then 30 else 22),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Text = "",
		ZIndex = 4,
	})
	amount.Parent = f
	local status = Instance.new("TextButton")
	status.Name = "Status"
	status.Text = ""
	status.AutoButtonColor = true
	status.BorderSizePixel = 0
	status.Size = UDim2.new(1, -16, 0, 32)
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.new(0.5, 0, 1, -6)
	status.BackgroundColor3 = Ui.Colors.PanelDark
	status.ZIndex = 5
	Ui.block(status, nil, 2.5, 4)
	Ui.label({
		Name = "Label",
		Size = UDim2.new(1, -10, 1, -6),
		Position = UDim2.fromOffset(5, 3),
		Text = "",
		ZIndex = 6,
	}).Parent =
		status
	status.Parent = f
	local done = Ui.frame({
		Name = "Done",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = DONE_DIM,
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 7,
	})
	Ui.corner(done, 14)
	Ui.icon("Checkmark", {
		Size = UDim2.fromOffset(64, 64),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		ZIndex = 8,
	}).Parent =
		done
	done.Parent = f
	return { frame = f, amount = amount, status = status, done = done, pulse = pulse }
end

local function setStatus(card: Card, text: string, color: Color3, claimable: boolean, claimed: boolean)
	Ui.setText(card.status, text)
	Ui.tint(card.status, color)
	card.done.Visible = claimed
	card.frame:SetAttribute("Claimable", claimable)
end

-- A window holder that pops in (the Pop scale) inside the screen-size scale.
local function popWindow(gui: ScreenGui, name: string, title: string, size: Vector2): (Frame, Frame)
	local window, body = Ui.window(gui, name, title, size)
	-- Ui.window put the screen-size UIScale on the window; pop the body instead.
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = body
	return window, body
end

-------------------------------------------------------------------------- render

local function renderDaily(r)
	local cashOf = r.CashOf and r.CashOf.Daily or {}
	for i, card in dailyCards do
		card.amount.Text = fullAmount(Rewards.Daily[i], cashOf[i])
		if i == r.DailyIndex and r.DailyReady then
			setStatus(card, "CLAIM!", Ui.Colors.Green, true, false)
		elseif i < r.DailyIndex or (i == r.DailyIndex and not r.DailyReady) then
			setStatus(card, "CLAIMED", Ui.Colors.PanelDark, false, true)
		elseif i == r.DailyIndex + 1 and not r.DailyReady then
			setStatus(card, Format.time(math.max(0, r.DailyNextAt - State.now())), Ui.Colors.Blue, false, false)
		else
			setStatus(card, "LOCKED", Ui.Colors.PanelDark, false, false)
		end
	end
	local nextLabel = windows.Daily and (windows.Daily :: any):FindFirstChild("Next", true) :: TextLabel?
	if nextLabel then
		nextLabel.Text = if r.DailyReady
			then "Your reward is ready!"
			else `Next reward in {Format.time(math.max(0, r.DailyNextAt - State.now()))}`
	end
end

local function renderGifts(r): number
	local ready = 0
	local played = playtimeNow()
	local cashOf = r.CashOf and r.CashOf.Playtime or {}
	for i, card in giftCards do
		local entry = Rewards.Playtime[i]
		card.amount.Text = fullAmount(entry.Reward, cashOf[i])
		local left = entry.Minutes * 60 - played
		if r.PlaytimeClaimed[i] then
			setStatus(card, "CLAIMED", Ui.Colors.PanelDark, false, true)
		elseif left <= 0 then
			ready += 1
			setStatus(card, "CLAIM!", Ui.Colors.Green, true, false)
		else
			setStatus(card, Format.time(left), Ui.Colors.PanelDark, false, false)
		end
	end
	return ready
end

local function renderWheel(r)
	local count = (r.Spins or 0) + (if r.FreeSpin then 1 else 0)
	wheelSpins.Text = `SPINS: {count}`
	if r.FreeSpin then
		wheelFree.Text = "Free spin ready!"
	elseif r.FreeSpinAt then
		wheelFree.Text = `Free spin in {Format.time(math.max(0, r.FreeSpinAt - State.now()))}`
	else
		wheelFree.Text = ""
	end
	Ui.setText(wheelSpinButton, if spinning then "..." elseif r.FreeSpin then "FREE SPIN!" else "SPIN!")
	wheelSpinButton.BackgroundColor3 = if count > 0 or spinning then Ui.Colors.Green else Ui.Colors.Red
	local cashOf = r.CashOf and r.CashOf.Wheel or {}
	local total = Rewards.wheelTotal()
	for i, seg in Rewards.Wheel.Segments do
		local row = oddsPanel:FindFirstChild("Odds" .. i)
		local label = row and row:FindFirstChild("Text") :: TextLabel?
		if label then
			label.Text = `{wedgeText(seg.Reward, cashOf[i])} {math.floor(seg.Weight / total * 1000 + 0.5) / 10}%`
		end
	end
end

-- Pulses the CLAIM! cards so the eye goes there (kids don't read).
local function pulseClaimable(t: number)
	local s = 1 + 0.04 * math.sin(t * 6)
	for _, list in { dailyCards, giftCards } do
		for _, card in list do
			card.pulse.Scale = if card.frame:GetAttribute("Claimable") then s else 1
		end
	end
	local holder = wheelArea and wheelArea:FindFirstChild("Pointer") :: GuiObject?
	if holder and not spinning then
		holder.Rotation = math.sin(t * 3) * 4
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
	Ui.badge(buttons.Daily, if r.DailyReady then 1 else 0)
	Ui.badge(buttons.Gifts, giftsReady)
	Ui.badge(buttons.Wheel, (if r.FreeSpin then 1 else 0) + (r.Spins or 0))
end

-------------------------------------------------------------------------- build: daily / gifts

local function buildDaily(gui: ScreenGui)
	local cw, ch, gap = 150, 168, 10
	local w = 3 * cw + 2 * gap + gap + 210 + 24
	local window, body = popWindow(gui, "Daily", "DAILY REWARDS", Vector2.new(w, 2 * ch + gap + 68 + 46))
	windows.Daily = window
	local nextLabel = Ui.label({
		Name = "Next",
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.fromOffset(0, 0),
		Text = "",
		TextColor3 = Color3.fromRGB(190, 220, 255),
	})
	nextLabel.Parent = body
	for i = 1, #Rewards.Daily do
		local big = i == #Rewards.Daily
		local card = makeCard(
			"Day" .. i,
			`DAY {i}`,
			Rewards.Daily[i],
			if big then 210 else cw,
			if big then 2 * ch + gap else ch,
			big
		)
		if big then
			card.frame.Position = UDim2.fromOffset(3 * (cw + gap), 36)
		else
			local col, row = (i - 1) % 3, (i - 1) // 3
			card.frame.Position = UDim2.fromOffset(col * (cw + gap), 36 + row * (ch + gap))
		end
		local function claim()
			if card.frame:GetAttribute("Claimable") then
				local ok = invoke("ClaimDaily")
				if ok then
					Ui.sound("Winner")
				end
			end
		end
		card.frame.Activated:Connect(claim)
		card.status.Activated:Connect(claim)
		card.frame.Parent = body
		dailyCards[i] = card
	end
end

local function buildGifts(gui: ScreenGui)
	local cw, ch, gap = 168, 190, 12
	local w = 3 * cw + 2 * gap + 24
	local window, body = popWindow(gui, "Gifts", "FREE GIFTS", Vector2.new(w, 2 * ch + gap + 68 + 46))
	windows.Gifts = window
	Ui.label({
		Name = "Info",
		Size = UDim2.new(1, 0, 0, 28),
		Text = "Play to unlock free gifts!",
		TextColor3 = Color3.fromRGB(190, 220, 255),
	}).Parent =
		body
	for i, entry in Rewards.Playtime do
		local col, row = (i - 1) % 3, (i - 1) // 3
		local card = makeCard("Gift" .. i, `{entry.Minutes} MIN`, entry.Reward, cw, ch)
		card.frame.Position = UDim2.fromOffset(col * (cw + gap), 36 + row * (ch + gap))
		local function claim()
			if card.frame:GetAttribute("Claimable") then
				local ok = invoke("ClaimPlaytime", i)
				if ok then
					Ui.sound("Winner")
				end
			end
		end
		card.frame.Activated:Connect(claim)
		card.status.Activated:Connect(claim)
		card.frame.Parent = body
		giftCards[i] = card
	end
end

-------------------------------------------------------------------------- build: wheel

local function burstConfetti(holder: Frame, amount: number)
	holder:ClearAllChildren()
	if Ui.reducedMotion() then
		return
	end
	for _ = 1, amount do
		local bit = Instance.new("Frame")
		bit.BorderSizePixel = 0
		bit.AnchorPoint = Vector2.new(0.5, 0.5)
		bit.BackgroundColor3 = CONFETTI[math.random(#CONFETTI)]
		local w = math.random(8, 14)
		bit.Size = UDim2.fromOffset(w, math.floor(w * 0.6))
		bit.Position = UDim2.fromScale(0.5, 0.48)
		bit.Rotation = math.random(0, 360)
		bit.ZIndex = 46
		bit.Parent = holder
		local angle = math.random() * math.pi * 2
		local dist = math.random(120, 230)
		local out = UDim2.new(0.5, math.cos(angle) * dist, 0.48, math.sin(angle) * dist - 40)
		TweenService:Create(bit, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = out,
			Rotation = bit.Rotation + math.random(-360, 360),
		}):Play()
		task.delay(0.55, function()
			if bit.Parent then
				TweenService:Create(bit, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = out + UDim2.fromOffset(math.random(-20, 20), 140),
					BackgroundTransparency = 1,
					Rotation = bit.Rotation + math.random(-360, 360),
				}):Play()
			end
		end)
	end
end

local function makePrizeCard(): Frame
	local card = Ui.frame({
		Name = "PrizeCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(400, 400),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 40,
	})
	local scale = Instance.new("UIScale")
	scale.Parent = card
	local back = Ui.frame({
		Name = "Back",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(290, 290),
		BackgroundColor3 = Ui.Colors.PanelDark,
		ZIndex = 40,
	})
	Ui.corner(back, 22)
	local edge = Ui.stroke(back, 5, GOLD)
	edge.Name = "Edge"
	back.Parent = card
	local r = rays(card, 340, UDim2.fromScale(0.5, 0.48), 41, 0.25)
	r.ImageColor3 = GOLD
	local holder = Ui.frame({
		Name = "PrizeHolder",
		Size = UDim2.fromOffset(150, 150),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		BackgroundTransparency = 1,
		ZIndex = 43,
	})
	holder.Parent = card
	local sticker = Ui.frame({
		Name = "Sticker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.17),
		Size = UDim2.fromOffset(250, 58),
		BackgroundColor3 = GOLD,
		Rotation = -6,
		ZIndex = 44,
	})
	Ui.corner(sticker, 14)
	Ui.stroke(sticker, 4)
	local ss = Instance.new("UIScale")
	ss.Parent = sticker
	Ui.label({
		Name = "Title",
		Size = UDim2.new(1, -12, 1, -8),
		Position = UDim2.fromOffset(6, 4),
		Text = "YOU WON!",
		ZIndex = 45,
	}).Parent =
		sticker
	sticker.Parent = card
	local plate = Ui.frame({
		Name = "Plate",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.8),
		Size = UDim2.fromOffset(290, 56),
		BackgroundColor3 = Ui.Colors.Green,
		ZIndex = 44,
	})
	Ui.corner(plate, 14)
	Ui.gradient(plate)
	Ui.stroke(plate, 4)
	Ui.label({
		Name = "PrizeName",
		Size = UDim2.new(1, -14, 1, -10),
		Position = UDim2.fromOffset(7, 5),
		Text = "",
		ZIndex = 45,
	}).Parent =
		plate
	plate.Parent = card
	Ui.frame({ Name = "Confetti", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 46 }).Parent = card
	card.Parent = wheelArea
	return card
end

local function showPrize(index: number, text: string?)
	local seg = Rewards.Wheel.Segments[index]
	if not seg then
		return
	end
	local card = prizeCard
	local holder = card:FindFirstChild("PrizeHolder") :: Frame
	holder:ClearAllChildren()
	local view = prizeView(seg.Reward, 150, 43)
	view.Position = UDim2.fromScale(0.5, 0.5)
	view.Parent = holder
	local jackpot = seg.Weight <= 1
	local color = if jackpot then PINK else GOLD
	local back = card:FindFirstChild("Back") :: Frame
	local edge = back:FindFirstChild("Edge") :: UIStroke
	edge.Color = color
	local cardRays = card:FindFirstChild("Rays") :: ImageLabel
	cardRays.ImageColor3 = color
	local sticker = card:FindFirstChild("Sticker") :: Frame
	sticker.BackgroundColor3 = color
	local title = sticker:FindFirstChild("Title") :: TextLabel
	title.Text = if jackpot then "JACKPOT!" else "YOU WON!"
	-- The server's own words ("You won $12.4K!") hold the exact amount.
	local name = text and string.match(text, "^You won (.+)!$") or Rewards.describe(seg.Reward)
	local plate = card:FindFirstChild("Plate") :: Frame
	local plateName = plate:FindFirstChild("PrizeName") :: TextLabel
	plateName.Text = name
	card.Visible = true
	local scale = card:FindFirstChildOfClass("UIScale") :: UIScale
	local stickerScale = sticker:FindFirstChildOfClass("UIScale") :: UIScale
	if Ui.reducedMotion() then
		scale.Scale = 1
		stickerScale.Scale = 1
	else
		scale.Scale = 0.3
		TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		stickerScale.Scale = 0
		task.delay(0.2, function()
			TweenService:Create(stickerScale, TweenInfo.new(0.4, Enum.EasingStyle.Elastic), { Scale = 1 }):Play()
		end)
	end
	burstConfetti(card:FindFirstChild("Confetti") :: Frame, if jackpot then 60 else 30)
	Ui.sound(if jackpot then "Reveal" else "Winner")
	prizeToken += 1
	local token = prizeToken
	task.spawn(function()
		local r = card:FindFirstChild("Rays") :: ImageLabel
		local t0 = os.clock()
		while token == prizeToken and card.Visible do
			local t = os.clock() - t0
			r.Rotation = t * 40
			holder.Position = UDim2.new(0.5, 0, 0.48, math.sin(t * 4) * 6)
			sticker.Rotation = -6 + math.sin(t * 5) * 3
			RunService.RenderStepped:Wait()
		end
	end)
	task.delay(3.5, function()
		if token == prizeToken then
			card.Visible = false
		end
	end)
end

-- Turns the wheel so wedge `index` stops under the pointer (top), several turns clockwise.
local function turnTo(index: number, done: () -> ())
	local centre = (index - 0.5) * STEP
	local jitter = (math.random() - 0.5) * STEP * 0.7
	local from = rotation
	local target = math.ceil(from / 360) * 360 + 360 * 5 + (360 - centre) + jitter
	local duration = if Ui.reducedMotion() then 0.6 else Rewards.Wheel.SpinSeconds
	local start = os.clock()
	local lastTick = math.floor(from / STEP)
	local pointer = wheelArea:FindFirstChild("Pointer") :: GuiObject
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / duration, 0, 1)
		local e = 1 - (1 - t) ^ 4
		rotation = from + (target - from) * e
		spinner.Rotation = rotation
		-- A click each time a divider passes the pointer, and the pointer flicks.
		local tick = math.floor((rotation + STEP / 2) / STEP)
		if tick ~= lastTick then
			lastTick = tick
			Ui.sound("Tap", 1 + (1 - t) * 0.4)
			pointer.Rotation = -14
		end
		pointer.Rotation *= 0.8
		if t >= 1 then
			conn:Disconnect()
			pointer.Rotation = 0
			rotation %= 360
			spinner.Rotation = rotation
			done()
		end
	end)
end

local function spin()
	if spinning then
		return
	end
	prizeToken += 1
	prizeCard.Visible = false
	local ok, why, index = Net.func("Rewards"):InvokeServer("Spin")
	if not ok or type(index) ~= "number" then
		if why then
			Ui.toast(why, "Bad")
		end
		return
	end
	spinning = true
	render()
	turnTo(index, function()
		spinning = false
		local slot = spinner:FindFirstChild("Seg" .. index) :: Frame?
		local sc = slot and slot:FindFirstChildOfClass("UIScale")
		if sc then
			sc.Scale = 1.5
			TweenService:Create(sc, TweenInfo.new(0.6, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		showPrize(index, why)
		render()
	end)
end

local function buildWheel(gui: ScreenGui)
	-- No big window (Sweep: "why would it need a whole frame"): the wheel floats on a dimmed
	-- screen with a slim dark panel beside it.
	local dim = Instance.new("TextButton")
	dim.Name = "Wheel"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BorderSizePixel = 0
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.3
	-- Bigger than the screen: the ScreenGui keeps clear of the top bar / notch, the dark
	-- backdrop should not (Dev 2026-11-20: it only covered part of the screen).
	dim.Size = UDim2.new(1, 800, 1, 800)
	dim.Position = UDim2.fromOffset(-400, -400)
	dim.Visible = false
	dim.ZIndex = 30
	dim.Activated:Connect(function()
		if not spinning then
			Ui.closeWindow(dim)
		end
	end)
	dim.Parent = gui
	windows.Wheel = dim
	local win = Ui.frame({
		Name = "Window",
		Size = UDim2.fromOffset(800, 480),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 31,
	})
	Ui.autoScale(win)
	win.Parent = dim
	local popHolder = Ui.frame({ Name = "PopHolder", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = popHolder
	popHolder.Parent = win

	wheelArea = Ui.frame({
		Name = "WheelArea",
		Size = UDim2.fromOffset(470, 480),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 31,
	})
	wheelArea.Parent = popHolder
	local size = 450
	spinner = Ui.frame({
		Name = "Spinner",
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 12),
		BackgroundTransparency = 1,
		ZIndex = 32,
	})
	Ui.icon("SpinWheel", { Name = "Face", Size = UDim2.fromScale(1, 1), ZIndex = 32 }).Parent = spinner
	local total = Rewards.wheelTotal()
	for i, seg in Rewards.Wheel.Segments do
		local a = math.rad((i - 0.5) * STEP)
		local rad = 0.6 * size / 2
		local slot = Ui.frame({
			Name = "Seg" .. i,
			Size = UDim2.fromOffset(96, 112),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.sin(a) * rad, 0.5, -math.cos(a) * rad),
			Rotation = (i - 0.5) * STEP,
			BackgroundTransparency = 1,
			ZIndex = 33,
		})
		Instance.new("UIScale").Parent = slot
		local view = prizeView(seg.Reward, 80, 34)
		view.Position = UDim2.new(0.5, 0, 0, 42)
		view.Parent = slot
		local chance = Ui.label({
			Name = "Chance",
			Size = UDim2.fromOffset(62, 24),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 84),
			BackgroundTransparency = 0.25,
			BackgroundColor3 = Ui.Colors.Ink,
			Text = `{math.floor(seg.Weight / total * 1000 + 0.5) / 10}%`,
			TextColor3 = Color3.fromRGB(255, 240, 170),
			ZIndex = 35,
		})
		Ui.corner(chance, 12)
		chance.Parent = slot
		slot.Parent = spinner
	end
	spinner.Parent = wheelArea
	Ui.icon("SpinPointer", {
		Name = "Pointer",
		Size = UDim2.fromOffset(88, 88),
		AnchorPoint = Vector2.new(0.5, 0.15),
		Position = UDim2.new(0.5, 0, 0, -6),
		ZIndex = 38,
	}).Parent =
		wheelArea

	-- Side panel: spins, SPIN!, Robux packs, odds.
	local side = Ui.frame({
		Name = "Side",
		Size = UDim2.fromOffset(310, 410),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 12),
		BackgroundColor3 = Ui.Colors.PanelDark,
		ZIndex = 31,
	})
	Ui.corner(side, 18)
	Ui.stroke(side, 4)
	side.Parent = popHolder
	wheelSpins = Ui.label({
		Name = "Spins",
		Size = UDim2.new(1, -24, 0, 42),
		Position = UDim2.fromOffset(12, 10),
		Text = "SPINS: 0",
		ZIndex = 32,
	})
	wheelSpins.Parent = side
	wheelFree = Ui.label({
		Name = "Free",
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.fromOffset(12, 52),
		Text = "",
		TextColor3 = Color3.fromRGB(150, 255, 120),
		ZIndex = 32,
	})
	wheelFree.Parent = side
	wheelSpinButton = Ui.button({
		Name = "SpinButton",
		Size = UDim2.new(1, -24, 0, 84),
		Position = UDim2.fromOffset(12, 82),
		BackgroundColor3 = Ui.Colors.Green,
		ZIndex = 32,
	}, "SPIN!", spin)
	wheelSpinButton.Parent = side
	local buy = Ui.frame({
		Name = "Buy",
		Size = UDim2.new(1, -24, 0, 76),
		Position = UDim2.fromOffset(12, 178),
		BackgroundTransparency = 1,
		ZIndex = 32,
	})
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = buy
	buy.Parent = side
	for i, key in { "WheelSpin1", "WheelSpin5", "WheelSpin10" } do
		local product = Products.ProductByKey[key]
		if product then
			local b = Ui.button(
				{
					Name = key,
					Size = UDim2.fromOffset(88, 76),
					LayoutOrder = i,
					BackgroundColor3 = Color3.fromRGB(150, 70, 240),
					ZIndex = 33,
				},
				"",
				function()
					local ok, msg = Net.func("PromptPurchase"):InvokeServer(key)
					if not ok and msg then
						Ui.toast(msg, "Bad")
					end
				end
			)
			local l = b:FindFirstChild("Label") :: TextLabel
			l.Size = UDim2.new(1, -8, 0, 30)
			l.Position = UDim2.fromOffset(4, 6)
			l.Text = `+{product.Count}`
			l.ZIndex = 34
			Ui.label({
				Name = "Price",
				Size = UDim2.new(1, -8, 0, 26),
				Position = UDim2.new(0, 4, 1, -32),
				Text = `{Ui.ROBUX}{product.Price}`,
				TextColor3 = Color3.fromRGB(150, 255, 120),
				ZIndex = 34,
			}).Parent =
				b
			b.Parent = buy
		end
	end
	-- Odds list (paid random rewards must show their odds): always on, under the packs.
	oddsPanel = Ui.frame({
		Name = "Odds",
		Size = UDim2.new(1, -24, 0, 132),
		Position = UDim2.fromOffset(12, 266),
		BackgroundColor3 = Ui.Colors.Panel,
		ZIndex = 32,
	})
	Ui.corner(oddsPanel, 12)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(139, 30)
	grid.CellPadding = UDim2.fromOffset(4, 2)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = oddsPanel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingTop = UDim.new(0, 4)
	pad.Parent = oddsPanel
	for i, seg in Rewards.Wheel.Segments do
		local row = Ui.frame({ Name = "Odds" .. i, LayoutOrder = i, BackgroundTransparency = 1, ZIndex = 33 })
		local icon = prizeView(seg.Reward, 30, 34)
		icon.Position = UDim2.fromOffset(15, 15)
		icon.Parent = row
		local odds = Ui.label({
			Name = "Text",
			Size = UDim2.new(1, -32, 1, -6),
			Position = UDim2.fromOffset(32, 3),
			Text = `{wedgeText(seg.Reward, nil)} {math.floor(seg.Weight / total * 1000 + 0.5) / 10}%`,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 34,
		})
		local fit = Instance.new("UITextSizeConstraint")
		fit.MaxTextSize = 18
		fit.Parent = odds
		odds.Parent = row
		row.Parent = oddsPanel
	end
	oddsPanel.Parent = side
	-- Red X on the panel corner.
	local close = Ui.button(
		{
			Name = "Close",
			Size = UDim2.fromOffset(48, 48),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -8, 0, 8),
			BackgroundColor3 = Ui.Colors.Red,
			ZIndex = 36,
		},
		"X",
		function()
			if not spinning then
				Ui.closeWindow(dim)
			end
		end
	)
	close.Parent = side
	prizeCard = makePrizeCard()
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
	Ui.button(
		{
			Name = "Redeem",
			Size = UDim2.fromOffset(200, 56),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 72),
			BackgroundColor3 = Ui.Colors.Green,
		},
		"REDEEM",
		function()
			local ok, why = Net.func("RedeemCode"):InvokeServer(codeBox.Text)
			if why then
				Ui.toast(why, if ok then "Good" else "Bad")
			end
			if ok then
				codeBox.Text = ""
			end
		end
	).Parent =
		body
end

function RewardsController:Init(controllers)
	C = controllers
	local gui = Ui.screen("Rewards", 20)
	buildDaily(gui)
	buildGifts(gui)
	buildWheel(gui)
	buildCodes(gui)

	-- Tiles on the HUD's left rail (icons, one word).
	local tiles = {
		{ "Daily", "Daily", "DAILY", Color3.fromRGB(255, 200, 60), 5 },
		{ "Gifts", "Gift", "GIFTS", Color3.fromRGB(255, 110, 150), 6 },
		{ "Wheel", "Wheel", "SPIN", Color3.fromRGB(70, 200, 255), 7 },
		{ "Codes", "Codes", "CODES", Color3.fromRGB(150, 120, 255), 8 },
	}
	for _, t in tiles do
		buttons[t[1]] = C.HudController:AddTile(t[1], t[2], t[3], t[4], t[5], function()
			toggle(t[1])
		end)
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
		pulseClaimable(os.clock())
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
