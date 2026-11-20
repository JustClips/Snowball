--!strict
-- Pets in the world on the client: every player's equipped pets follow them (from the
-- player's "Followers" attribute) with a little hop, base pets bob in place, and hatch eggs
-- count down. Simple CFrame motion until the shared bone animations are made (one set
-- per body type, GAME_PLAN §5.10).
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local PetLook = require(Shared.PetLook)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Parent.Ui)

local FollowerController = {}

type Follower = { model: Model, offset: Vector3, phase: number, pos: Vector3 }
-- Where followers walk, behind their owner (studs, owner space).
local OFFSETS = {
	Vector3.new(-4, 0, 5),
	Vector3.new(4, 0, 5),
	Vector3.new(0, 0, 7),
	Vector3.new(-7, 0, 8),
	Vector3.new(7, 0, 8),
	Vector3.new(-3, 0, 11),
	Vector3.new(3, 0, 11),
}
local followers: { [Player]: { list: { Follower }, key: string } } = {}
local folder: Folder
local eggLabels: { [BasePart]: TextLabel } = {}

local function clear(player: Player)
	local entry = followers[player]
	if entry then
		for _, f in entry.list do
			f.model:Destroy()
		end
		followers[player] = nil
	end
end

local function rebuild(player: Player)
	local raw = player:GetAttribute("Followers")
	local key = if type(raw) == "string" then raw else ""
	local entry = followers[player]
	if entry and entry.key == key then
		return
	end
	clear(player)
	local ok, list = pcall(HttpService.JSONDecode, HttpService, key)
	if not ok or type(list) ~= "table" then
		return
	end
	local out: { Follower } = {}
	for i, item in list do
		local model = PetLook.make(item[1], if item[2] ~= "" then item[2] else nil, item[3] == 1)
		if model then
			model.Parent = folder
			table.insert(out, { model = model, offset = OFFSETS[(i - 1) % #OFFSETS + 1], phase = i * 0.7, pos = Vector3.zero })
		end
	end
	followers[player] = { list = out, key = key }
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("Followers"):Connect(function()
		rebuild(player)
	end)
	rebuild(player)
end

local function step(dt: number)
	local t = os.clock()
	for player, entry in followers do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local rolling = player:GetAttribute("RollPhase") == "Rolling"
			for _, f in entry.list do
				local goal = (root.CFrame * CFrame.new(f.offset)).Position
				if (f.pos - goal).Magnitude > 60 then
					f.pos = goal
				end
				f.pos = f.pos:Lerp(goal, math.min(1, dt * 6))
				local speed = root.AssemblyLinearVelocity.Magnitude
				local hop = if speed > 2 then math.abs(math.sin(t * 9 + f.phase)) * 1.2 else math.sin(t * 2 + f.phase) * 0.15 + 0.15
				-- Cheer next to the roller: bigger hops while the owner trains.
				if player:GetAttribute("Training") then
					hop = math.abs(math.sin(t * 7 + f.phase)) * 1.6
				end
				local ground = f.pos - Vector3.new(0, 3, 0) + Vector3.yAxis * hop
				local look = root.CFrame.LookVector
				f.model:PivotTo(CFrame.lookAt(ground, ground - Vector3.new(look.X, 0, look.Z)))
				for _, d in f.model:GetDescendants() do
					if d:IsA("BasePart") then
						d.LocalTransparencyModifier = if rolling then 1 else 0
					end
				end
			end
		end
	end
end

-- Base pets bob, hatch eggs show their timer.
local function basesTick()
	local mountain = Workspace:FindFirstChild("Mountain")
	local bases = mountain and mountain:FindFirstChild("Summit") and (mountain :: any).Summit:FindFirstChild("Bases")
	if not bases then
		return
	end
	local now = State.now()
	for _, base in bases:GetChildren() do
		local eggs = base:FindFirstChild("Eggs")
		for _, egg in (if eggs then eggs:GetChildren() else {}) do
			if egg:IsA("BasePart") then
				local label = eggLabels[egg]
				if not label then
					local gui = Instance.new("BillboardGui")
					gui.Size = UDim2.fromOffset(110, 30)
					gui.StudsOffset = Vector3.new(0, 3.6, 0)
					gui.MaxDistance = 90
					gui.AlwaysOnTop = true
					local l = Ui.label({ Size = UDim2.fromScale(1, 1), Text = "" })
					l.Parent = gui
					gui.Parent = egg
					eggLabels[egg] = l
					label = l
					egg.Destroying:Connect(function()
						eggLabels[egg] = nil
					end)
				end
				local left = (egg:GetAttribute("EndsAt") or 0) - now
				;(label :: TextLabel).Text = if left > 0 then Format.time(left) else "READY!"
				;(label :: TextLabel).TextColor3 = if left > 0 then Ui.Colors.Snow else Ui.Colors.Green
			end
		end
	end
end

local function bob()
	local mountain = Workspace:FindFirstChild("Mountain")
	local bases = mountain and mountain:FindFirstChild("Summit") and (mountain :: any).Summit:FindFirstChild("Bases")
	if not bases then
		return
	end
	local t = os.clock()
	for _, base in bases:GetChildren() do
		local pets = base:FindFirstChild("Pets")
		for i, model in (if pets then pets:GetChildren() else {}) do
			if model:IsA("Model") then
				local home = model:GetAttribute("Home") :: CFrame?
				if not home then
					home = model:GetPivot()
					model:SetAttribute("Home", home)
				end
				model:PivotTo((home :: CFrame) + Vector3.yAxis * (math.abs(math.sin(t * 2.2 + i)) * 0.5))
			end
		end
	end
end

function FollowerController:Init()
	folder = Instance.new("Folder")
	folder.Name = "Followers"
	folder.Parent = Workspace
end

function FollowerController:Start()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(clear)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		step(dt)
		bob()
		acc += dt
		if acc > 0.25 then
			acc = 0
			basesTick()
		end
	end)
end

return FollowerController
