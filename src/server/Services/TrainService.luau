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

local function onRoller(player: Player): boolean
	local index = player:GetAttribute("BaseIndex")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if type(index) ~= "number" or not root then
		return false
	end
	if S.RollService and S.RollService:IsBusy(player) then
		return false
	end
	local spot = World.rollerSpot(index)
	local offset = root.Position - spot
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= Economy.RollerRadius
		and offset.Y > -2
		and offset.Y < Economy.RollerHeight
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

local function tick()
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
	model:SetAttribute("Owner", player.UserId)

	-- Upgrade the station right here (Dev, 2026-11-20: like the treadmill games): a sign
	-- over the roller with the Upgrade icon and the next price, and a prompt to buy it.
	local nextDef = Rollers.get(data.Roller + 1)
	-- A short sign post standing on the ground beside the roller (not floating over it):
	-- the price board sits on top at eye height and the prompt is on the post itself.
	local post = Instance.new("Part")
	post.Name = "UpgradePost"
	post.Anchored = true
	post.Size = Vector3.new(0.8, 4, 0.8)
	post.CFrame = cf * CFrame.new(10, 2, -3)
	post.Material = Enum.Material.Wood
	post.Color = Color3.fromRGB(120, 80, 48)
	post.Parent = model
	local sign = Instance.new("Part")
	sign.Name = "UpgradeSign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.CanQuery = false
	sign.Size = Vector3.new(5, 0.4, 0.4)
	sign.CFrame = cf * CFrame.new(10, 4.2, -3)
	sign.Material = Enum.Material.Wood
	sign.Color = Color3.fromRGB(120, 80, 48)
	sign.Parent = model
	local board = Instance.new("BillboardGui")
	board.Name = "Board"
	board.Size = UDim2.fromScale(6, 2.2)
	board.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
	board.MaxDistance = 90
	board.LightInfluence = 0
	board.Parent = sign
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(16, 27, 52)
	bg.BorderSizePixel = 0
	bg.Parent = board
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 32, 58)
	stroke.Parent = bg
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(0.3, 1)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = if nextDef then Images.Upgrade else Images.Star
	icon.Parent = bg
	local price = Instance.new("TextLabel")
	price.BackgroundTransparency = 1
	price.Position = UDim2.fromScale(0.32, 0.1)
	price.Size = UDim2.fromScale(0.66, 0.8)
	price.TextScaled = true
	price.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	price.TextColor3 = Color3.fromRGB(120, 230, 120)
	local free = nextDef ~= nil and nextDef.Index == Rollers.FreeInTutorial and not data.Flags.TutorialDone
	price.Text = if not nextDef then "MAX" elseif free then "FREE" else Format.cash(nextDef.Price)
	price.Parent = bg
	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 2
	textStroke.Parent = price
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

function TrainService:Init(services)
	S = services
	Net.onInvoke("BuyRoller", buyRoller)
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
