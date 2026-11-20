--!strict
-- Training Power on the Snow Roller next to your base (GAME_PLAN §5.1).
-- Standing near your own roller = training, automatically (Dev, 2026-11-20: no tapping to
-- train; taps are only for Snow Pops). Each rep gives
--   roller Power x Robux roller x pets x pop x rebirth x boosts   (BoostService:GetTrainMult)
-- at Economy.TrainRepsPerSecond, x FastTrainMult with the Auto Train pass.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Rollers = require(Shared.Config.Rollers)
local Signal = require(Shared.Signal)
local World = require(Shared.Config.World)
local Images = require(Shared.Config.Images)
local ModelLoader = require(script.Parent.Parent.Lib.ModelLoader)

local TrainService = {
	-- (player, training: boolean) when a player steps on or off their roller
	TrainingChanged = Signal.new() :: Signal.Signal<Player, boolean>,
}

local S: any
local TICK = 0.1

type Train = {
	on: boolean,
	auto: number, -- fractional server-driven taps
	sessionStart: number,
	sessionTaps: number,
	sessionGain: number,
}
local state: { [Player]: Train } = {}

local function trainOf(player: Player): Train
	local t = state[player]
	if not t then
		t = {
			on = false,
			auto = 0,
			sessionStart = 0,
			sessionTaps = 0,
			sessionGain = 0,
		}
		state[player] = t
	end
	return t
end

function TrainService:IsTraining(player: Player): boolean
	local t = state[player]
	return t ~= nil and t.on
end

-- Power one tap gives right now (for the HUD readout and Training Time products).
function TrainService:PowerPerTap(player: Player): number
	local data = S.DataService:GetData(player)
	if not data then
		return 0
	end
	local roller = Rollers.get(data.Roller) or Rollers.Cash[1]
	return roller.Power * S.BoostService:GetTrainMult(player)
end

-- Adds `taps` taps worth of Power. Returns the Power gained.
function TrainService:Grant(player: Player, taps: number, quiet: boolean?): number
	local data = S.DataService:GetData(player)
	if not data or taps <= 0 then
		return 0
	end
	local gain = TrainService:PowerPerTap(player) * taps
	local before = BigNum.toNumber(data.Power)
	data.Power = BigNum.add(data.Power, gain)
	data.Stats.Taps += taps
	local t = trainOf(player)
	t.sessionTaps += taps
	t.sessionGain += gain
	S.StateService:Mark(player)
	if not quiet then
		Net.fire("PowerGained", player, gain, taps)
	end
	S.AnalyticsService:Funnel(player, "FirstTap")
	if before < 100 and before + gain >= 100 then
		S.AnalyticsService:Funnel(player, "Power100")
	end
	return gain
end

local function rollerPad(player: Player): BasePart?
	local index = player:GetAttribute("BaseIndex")
	local base = type(index) == "number" and S.WorldService:GetBase(index)
	return base and base:FindFirstChild("RollerPad") :: BasePart?
end

-- On the roller = standing on its 16 x 16 deck (Dev 2026-11-20: "when I step on the
-- training thing"), not anywhere near it.
local function onRoller(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pad = rollerPad(player)
	if not root or not pad then
		return false
	end
	if S.RollService and S.RollService:IsBusy(player) then
		return false
	end
	local p = pad.CFrame:PointToObjectSpace(root.Position)
	local half = Economy.RollerDeck / 2
	return math.abs(p.X) <= half and math.abs(p.Z) <= half and p.Y > -1 and p.Y < Economy.RollerHeight
end

local function setTraining(player: Player, on: boolean)
	local t = trainOf(player)
	if t.on == on then
		return
	end
	t.on = on
	player:SetAttribute("Training", on or nil)
	if on then
		t.auto = math.max(t.auto, 0.95) -- the first rep comes right away
		t.sessionStart = os.clock()
		t.sessionTaps = 0
		t.sessionGain = 0
	elseif t.sessionTaps > 0 then
		S.AnalyticsService:Custom(
			player,
			"TrainSession",
			math.floor(os.clock() - t.sessionStart),
			{ Taps = tostring(t.sessionTaps) }
		)
	end
	TrainService.TrainingChanged:Fire(player, on)
end

-- The upgrade board's price pill: green when you can pay, red when not (checked 1/s).
local pillAcc = 0
local function refreshPills()
	for player in S.DataService:GetSessions() do
		local data = S.DataService:GetData(player)
		local index = player:GetAttribute("BaseIndex")
		local base = type(index) == "number" and S.WorldService:GetBase(index)
		local roller = base and base:FindFirstChild("Roller")
		local post = roller and roller:FindFirstChild("UpgradePost")
		local board = post and post:FindFirstChild("Board")
		local pill = board and board:FindFirstChild("Price") :: Frame?
		local nextDef = data and Rollers.get(data.Roller + 1)
		if pill and data and nextDef then
			local free = nextDef.Index == Rollers.FreeInTutorial and not data.Flags.TutorialDone
			local canPay = free or not BigNum.lt(data.Cash, nextDef.Price)
			pill.BackgroundColor3 = if canPay then Color3.fromRGB(70, 205, 95) else Color3.fromRGB(235, 70, 70)
		end
	end
end

local function tick()
	pillAcc += TICK
	if pillAcc >= 1 then
		pillAcc = 0
		refreshPills()
	end
	for player in S.DataService:GetSessions() do
		local on = onRoller(player)
		setTraining(player, on)
		local t = state[player]
		if t and t.on then
			local data = S.DataService:GetData(player)
			local rate = Economy.TrainRepsPerSecond
			if data and data.Gamepasses.AutoTrain then
				rate *= Economy.FastTrainMult
			end
			t.auto += rate * TICK
			if t.auto >= 1 then
				local taps = math.floor(t.auto)
				t.auto -= taps
				TrainService:Grant(player, taps)
			end
		end
	end
end

-- Buys the next cash roller. The Stone Roller is free while the tutorial runs.
local function buyRoller(player: Player): (boolean, string?)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading"
	end
	local nextDef = Rollers.get(data.Roller + 1)
	if not nextDef then
		return false, "You have the best roller"
	end
	if data.Rebirths < nextDef.RebirthsNeeded then
		return false, `Rebirth {nextDef.RebirthsNeeded} needed`
	end
	local free = nextDef.Index == Rollers.FreeInTutorial and not data.Flags.TutorialDone
	if not free then
		local ok, why = S.CashService:Spend(player, nextDef.Price, "Roller" .. nextDef.Id)
		if not ok then
			return false, why
		end
	end
	data.Roller = nextDef.Index
	S.StateService:Mark(player)
	S.AnalyticsService:RollerBought(player, nextDef.Index, nextDef.Name)
	if nextDef.Index == Rollers.FreeInTutorial then
		S.AnalyticsService:Funnel(player, "StoneRoller")
	end
	TrainService:RefreshRoller(player)
	Net.fire("Notify", player, `{nextDef.Name}! +{Format.big(nextDef.Power)} Power`, "Good")
	return true, nil
end

-- Graybox roller on the base pad (until the Blender roller models are uploaded): a big
-- snowball in a wooden frame. The client spins the ball while its owner trains.
function TrainService:RefreshRoller(player: Player)
	local data = S.DataService:GetData(player)
	local index = player:GetAttribute("BaseIndex")
	if not data or type(index) ~= "number" then
		return
	end
	local base = S.WorldService:GetBase(index)
	local pad = base and base:FindFirstChild("RollerPad") :: BasePart?
	if not base or not pad then
		return
	end
	local old = base:FindFirstChild("Roller")
	if old then
		old:Destroy()
	end
	local look = Rollers.lookId(data.Roller, data.RobuxRollers)
	local color = (Rollers.get(data.Roller) or Rollers.Cash[1]).Color
	local robux = Rollers.RobuxById[look]
	if robux then
		color = robux.Color
	end
	local model = Instance.new("Model")
	model.Name = "Roller"
	model:SetAttribute("Look", look)
	local cf = pad.CFrame * CFrame.new(0, 0.5, 0)
	-- The Blender station for this tier (art/blender/roller.py): "Station" + a "Ball" that
	-- TrainController spins. Falls back to a graybox until the model is uploaded.
	local look3d = ModelLoader.clone("Roller_" .. look, cf)
	if look3d then
		for _, child in look3d:GetChildren() do
			child.Parent = model
		end
		look3d:Destroy()
		-- Mesh hulls would wall off the deck: the meshes are visual, a plain box is the deck.
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
			end
		end
		local deck = Instance.new("Part")
		deck.Name = "DeckCollider"
		deck.Anchored = true
		deck.Transparency = 1
		deck.Size = Vector3.new(16, 0.6, 16)
		deck.CFrame = cf * CFrame.new(0, 0.3, 0)
		deck.Parent = model
	else
		local function frame(name: string, size: Vector3, offset: CFrame)
			local p = Instance.new("Part")
			p.Name = name
			p.Anchored = true
			p.Size = size
			p.CFrame = cf * offset
			p.Material = Enum.Material.Wood
			p.Color = color:Lerp(Color3.fromRGB(120, 85, 55), 0.5)
			p.Parent = model
		end
		frame("PostL", Vector3.new(1.5, 12, 1.5), CFrame.new(-7, 6, 0))
		frame("PostR", Vector3.new(1.5, 12, 1.5), CFrame.new(7, 6, 0))
		frame("Bar", Vector3.new(15.5, 1.5, 1.5), CFrame.new(0, 12, 0))
		local ball = Instance.new("Part")
		ball.Name = "Ball"
		ball.Shape = Enum.PartType.Ball
		ball.Anchored = true
		ball.CanCollide = false
		ball.Size = Vector3.new(9, 9, 9)
		ball.CFrame = cf * CFrame.new(0, 5, 4.5)
		ball.Material = Enum.Material.Snow
		ball.Color = Color3.fromRGB(245, 248, 255):Lerp(color, 0.25)
		ball.Parent = model
	end
	model:SetAttribute("Owner", player.UserId)

	-- Upgrade the station right here (Dev, 2026-11-20: like the treadmill games): a sign
	-- over the roller with the Upgrade icon and the next price, and a prompt to buy it.
	local nextDef = Rollers.get(data.Roller + 1)
	-- Steal an Egg style upgrade board beside the roller (Dev 2026-11-20: the old price
	-- sign looked weird): two posts, a dark navy board facing the plaza with
	-- "Upgrade Roller", "Stone > Iron", "+N Power" and a price pill (green when you can
	-- afford it, red when not). The prompt is on the board.
	local cur = Rollers.get(data.Roller) or Rollers.Cash[1]
	local free = nextDef ~= nil and nextDef.Index == Rollers.FreeInTutorial and not data.Flags.TutorialDone
	local boardCf = cf * CFrame.new(11, 4.6, -3) * CFrame.Angles(math.rad(-12), 0, 0)
	for _, sx in { -3.2, 3.2 } do
		local leg = Instance.new("Part")
		leg.Name = "UpgradeLeg"
		leg.Anchored = true
		leg.Size = Vector3.new(0.6, 5.6, 0.6)
		leg.CFrame = cf * CFrame.new(11 + sx, 2.8, -2.6)
		leg.Material = Enum.Material.Wood
		leg.Color = Color3.fromRGB(110, 72, 44)
		leg.Parent = model
	end
	local post = Instance.new("Part")
	post.Name = "UpgradePost"
	post.Anchored = true
	post.Size = Vector3.new(7.6, 4.2, 0.4)
	post.CFrame = boardCf
	post.Material = Enum.Material.SmoothPlastic
	post.Color = Color3.fromRGB(24, 30, 64)
	post.Parent = model
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Parent = post
	local font = Font.fromEnum(Enum.Font.FredokaOne)
	local function text(name: string, t: string, y: number, h: number, color: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, -40, 0, h)
		l.Position = UDim2.new(0, 20, 0, y)
		l.FontFace = font
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = t
		local st = Instance.new("UIStroke")
		st.Thickness = 4
		st.Color = Color3.fromRGB(22, 20, 38)
		st.Parent = l
		l.Parent = gui
		return l
	end
	text("Title", if nextDef then "Upgrade Roller" else "Best Roller!", 14, 56, Color3.new(1, 1, 1))
	if nextDef then
		text(
			"Tiers",
			`{string.gsub(cur.Name, " Roller", "")} > {string.gsub(nextDef.Name, " Roller", "")}`,
			74,
			48,
			Color3.fromRGB(255, 215, 70)
		)
		text("Gain", `+{Format.big(nextDef.Power)} Power`, 124, 36, Color3.fromRGB(120, 210, 255))
		local pill = Instance.new("Frame")
		pill.Name = "Price"
		pill.Size = UDim2.new(0, 260, 0, 64)
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.Position = UDim2.new(0.5, 0, 0, 170)
		local canPay = free or not BigNum.lt(data.Cash, nextDef.Price)
		pill.BackgroundColor3 = if canPay then Color3.fromRGB(70, 205, 95) else Color3.fromRGB(235, 70, 70)
		pill.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = pill
		local ps = Instance.new("UIStroke")
		ps.Thickness = 4
		ps.Color = Color3.fromRGB(22, 20, 38)
		ps.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ps.Parent = pill
		local price = text("Text", if free then "FREE" else Format.cash(nextDef.Price), 0, 52, Color3.new(1, 1, 1))
		price.Size = UDim2.new(1, -20, 1, -12)
		price.Position = UDim2.fromOffset(10, 6)
		price.Parent = pill
	else
		text("Tiers", cur.Name, 90, 60, Color3.fromRGB(255, 215, 70))
	end
	if nextDef then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RollerUpgrade"
		prompt.ActionText = "Upgrade"
		prompt.ObjectText = ""
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 18
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = post
		prompt.Triggered:Connect(function(who)
			if who ~= player then
				return
			end
			local ok, why = buyRoller(player)
			if not ok and why then
				Net.fire("Notify", player, why, "Bad")
			end
		end)
	end
	model.Parent = base
end

-- STOP (bottom centre while training): step off the roller onto the plaza side.
local function stopTraining(player: Player): (boolean, string?)
	local pad = rollerPad(player)
	local character = player.Character
	if not pad or not character or not TrainService:IsTraining(player) then
		return false, nil
	end
	setTraining(player, false)
	local spot = pad.CFrame * CFrame.new(0, 4, -(Economy.RollerDeck / 2 + 6))
	character:PivotTo(CFrame.lookAt(spot.Position, spot.Position + spot.LookVector))
	return true, nil
end

function TrainService:Init(services)
	S = services
	Net.onInvoke("BuyRoller", buyRoller)
	Net.onInvoke("StopTraining", stopTraining)
	S.BaseService.BaseAssigned:Connect(function(player)
		TrainService:RefreshRoller(player)
	end)
	S.DataService.ProfileReleasing:Connect(function(player)
		setTraining(player, false)
		local index = player:GetAttribute("BaseIndex")
		local base = type(index) == "number" and S.WorldService:GetBase(index)
		local roller = base and base:FindFirstChild("Roller")
		if roller then
			roller:Destroy()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
	end)
end

function TrainService:Start()
	task.spawn(function()
		while true do
			task.wait(TICK)
			tick()
		end
	end)
end

return TrainService
