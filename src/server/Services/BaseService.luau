--!strict
-- Gives each player one of the 8 summit bases and spawns their character there.
-- Characters only load after the profile loaded (DataService turns off CharacterAutoLoads).
-- (Ported from Sweep the World.)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local World = require(Shared.Config.World)

local BaseService = {
	CharacterReady = Signal.new() :: Signal.Signal<Player, Model>,
	BaseAssigned = Signal.new() :: Signal.Signal<Player, number>,
}

local S: any
local owners: { [number]: Player } = {}

local function freeIndex(): number?
	for i = 1, World.BaseCount do
		if not owners[i] then
			return i
		end
	end
	return nil
end

function BaseService:GetBaseIndex(player: Player): number?
	local session = S.DataService:GetSession(player)
	return if session then session.Runtime.BaseIndex else nil
end

function BaseService:GetOwner(index: number): Player?
	return owners[index]
end

function BaseService:SpawnCFrame(index: number): CFrame
	-- On the path in the open yard between the cabin porch and the gate, facing the gate.
	return World.baseCFrame(index) * CFrame.new(0, 4, -2)
end

-- Owner name over the base (placeholder sign until the Blender cabin has its sign board).
local function setOwnerName(index: number, player: Player?)
	local base = S.WorldService:GetBase(index)
	local pad = base and base:FindFirstChild("Pad")
	if not pad then
		return
	end
	local sign = pad:FindFirstChild("OwnerSign")
	if not player then
		if sign then
			sign:Destroy()
		end
		return
	end
	if not sign then
		local gui = Instance.new("BillboardGui")
		gui.Name = "OwnerSign"
		gui.Size = UDim2.fromOffset(260, 50)
		gui.StudsOffset = Vector3.new(0, 14, 0)
		gui.MaxDistance = 180
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.Parent = gui
		gui.Parent = pad
		sign = gui
	end
	((sign :: Instance):FindFirstChild("Label") :: TextLabel).Text = player.DisplayName .. "'s Base"
end

local function onCharacter(player: Player, character: Model)
	local index = BaseService:GetBaseIndex(player)
	if index then
		task.defer(function()
			character:PivotTo(BaseService:SpawnCFrame(index))
		end)
	end
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid.Died:Connect(function()
			task.wait(Players.RespawnTime)
			if player.Parent and S.DataService:GetSession(player) then
				player:LoadCharacter()
			end
		end)
	end
	BaseService.CharacterReady:Fire(player, character)
end

-- Teleport("Base" | "Deck" | "Roller"): the HUD's BASE / ROLL buttons.
local function teleport(player: Player, where: any): (boolean, string?)
	local index = BaseService:GetBaseIndex(player)
	local character = player.Character
	if not index or not character or (S.RollService and S.RollService:IsBusy(player)) then
		return false, nil
	end
	if S.EggRescueService and S.EggRescueService:IsRescuing(player) then
		return false, "Save your eggs first! (or press LEAVE)"
	end
	if where == "Base" then
		character:PivotTo(BaseService:SpawnCFrame(index))
	elseif where == "Roller" then
		local spot = World.rollerSpot(index)
		character:PivotTo(CFrame.lookAt(spot + Vector3.yAxis * 4, Vector3.new(0, spot.Y + 4, spot.Z)))
	elseif where == "Deck" then
		-- Straight onto your lane pad and the launch starts (only ROLL starts one).
		local pos = World.DeckStand + Vector3.new(World.laneX(index), 2, 0)
		character:PivotTo(CFrame.lookAt(pos, pos + Vector3.zAxis))
		if S.RollService then
			return S.RollService:StartPack(player)
		end
	else
		return false, nil
	end
	return true, nil
end

function BaseService:Init(services)
	S = services
	Net.onInvoke("Teleport", teleport)
	S.DataService.ProfileLoaded:Connect(function(player: Player, session)
		local index = freeIndex()
		if not index then
			-- Server size is 8, so this should never happen.
			player:Kick("This server is full. Please join another one!")
			return
		end
		owners[index] = player
		session.Runtime.BaseIndex = index
		player:SetAttribute("BaseIndex", index)
		setOwnerName(index, player)
		BaseService.BaseAssigned:Fire(player, index)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		player:LoadCharacter()
	end)
	S.DataService.ProfileReleasing:Connect(function(player: Player, session)
		local index = session.Runtime.BaseIndex
		if index and owners[index] == player then
			owners[index] = nil
			setOwnerName(index, nil)
		end
	end)
	-- Safety net: whatever happened to the save, a player who left never keeps a base.
	Players.PlayerRemoving:Connect(function(player: Player)
		task.defer(function()
			for index, owner in owners do
				if owner == player then
					owners[index] = nil
					setOwnerName(index, nil)
				end
			end
		end)
	end)
end

return BaseService
