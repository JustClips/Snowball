--!strict
-- Overhead name tags (Dev 2026-11-20: "a tag above player showing how much his base gives
-- ... introduce vip tag above user"). Roblox's own name is hidden (LeaderboardService).
--
--   [crown] [VIP] Name [#7]      crown = top 3 base income in this server (gold/silver/
--   ($) $1.2K/s                  bronze), VIP = VIP pass, #N = best world rank (top 50)
--
-- Icons first, one number, no sentences. Built on the client from player attributes
-- (IncomePerSec, VIP, ServerRank, WorldRank, WorldBoard), sized in studs so tags shrink
-- with distance, hidden past MAX_DISTANCE. Your own tag hides while you train (the "+N"
-- floaters use that space).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Leaderboards = require(Shared.Config.Leaderboards)
local Ui = require(script.Parent.Parent.Ui)

local NametagController = {}

local MAX_DISTANCE = 90
local WIDTH = 9 -- studs
local HEIGHT = 2.7
local CROWNS = { "Crown", "CrownSilver", "CrownBronze" }
local VIP_GOLD = Color3.fromRGB(255, 196, 0)

local localPlayer = Players.LocalPlayer
local gui: ScreenGui
local tags: { [Player]: { board: BillboardGui, refresh: () -> () } } = {}

local function build(player: Player)
	local board = Instance.new("BillboardGui")
	board.Name = "Tag_" .. player.UserId
	board.Size = UDim2.fromScale(WIDTH, HEIGHT)
	board.StudsOffset = Vector3.new(0, 2.9, 0)
	board.MaxDistance = MAX_DISTANCE
	board.LightInfluence = 0
	board.AlwaysOnTop = false
	board.ResetOnSpawn = false
	board.ClipsDescendants = false
	board.Enabled = false

	-- Top row: crown, VIP block, name, world rank chip (a centred horizontal list).
	local top = Ui.frame({
		Name = "Top",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0.52),
	})
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0.015, 0)
	list.Parent = top
	top.Parent = board

	local crown = Ui.icon("Crown", {
		Name = "Crown",
		LayoutOrder = 1,
		Size = UDim2.fromScale(0.13, 1),
		Visible = false,
	})
	crown.Parent = top

	local vip = Ui.frame({
		Name = "VIP",
		LayoutOrder = 2,
		Size = UDim2.fromScale(0.15, 0.8),
		BackgroundColor3 = VIP_GOLD,
		Visible = false,
	})
	Ui.block(vip, nil, 2, 3)
	local vipText = Ui.label({
		Name = "Text",
		Size = UDim2.fromScale(0.9, 0.78),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Text = "VIP",
		ZIndex = 3,
	})
	Ui.maxText(vipText, 60)
	vipText.Parent = vip
	vip.Parent = top

	local name = Ui.label({
		Name = "Name",
		LayoutOrder = 3,
		Size = UDim2.fromScale(0.5, 0.92),
		Text = player.DisplayName,
	})
	Ui.maxText(name, 60)
	name.Parent = top

	local rank = Ui.frame({
		Name = "Rank",
		LayoutOrder = 4,
		Size = UDim2.fromScale(0.17, 0.8),
		BackgroundColor3 = Ui.Colors.Blue,
		Visible = false,
	})
	Ui.block(rank, nil, 2, 3)
	local rankText = Ui.label({
		Name = "Text",
		Size = UDim2.fromScale(0.92, 0.78),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Text = "#1",
		ZIndex = 3,
	})
	Ui.maxText(rankText, 60)
	rankText.Parent = rank
	rank.Parent = top

	-- Bottom row: cash icon + what the base makes per second, in green.
	local bottom = Ui.frame({
		Name = "Income",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0.44),
		Position = UDim2.fromScale(0, 0.55),
	})
	local blist = list:Clone()
	blist.Parent = bottom
	Ui.icon("Cash", { LayoutOrder = 1, Size = UDim2.fromScale(0.1, 1) }).Parent = bottom
	local income = Ui.label({
		Name = "Value",
		LayoutOrder = 2,
		Size = UDim2.fromScale(0.45, 1),
		Text = "$0/s",
		TextColor3 = Ui.Colors.Lime,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Ui.maxText(income, 60)
	income.Parent = bottom
	bottom.Parent = board

	local function refresh()
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		board.Adornee = head
		local hide = player == localPlayer and player:GetAttribute("Training") == true
		board.Enabled = head ~= nil and not hide

		-- Name width follows its length so the row stays centred.
		local n = utf8.len(player.DisplayName) or #player.DisplayName
		name.Size = UDim2.fromScale(math.clamp(0.07 + n * 0.042, 0.2, 0.6), 0.92)

		local serverRank = player:GetAttribute("ServerRank")
		crown.Visible = type(serverRank) == "number" and serverRank >= 1 and serverRank <= 3
		if crown.Visible then
			crown.Image = Ui.Images[CROWNS[serverRank :: number]] or Ui.Images.Crown or ""
		end
		vip.Visible = player:GetAttribute("VIP") == true

		local worldRank = player:GetAttribute("WorldRank")
		rank.Visible = type(worldRank) == "number"
		if rank.Visible then
			local boardDef = Leaderboards.ByKey[tostring(player:GetAttribute("WorldBoard"))]
			Ui.tint(rank, if boardDef then boardDef.Color else Ui.Colors.Blue)
			rankText.Text = `#{worldRank}`
		end

		local perSec = tonumber(player:GetAttribute("IncomePerSec")) or 0
		bottom.Visible = perSec > 0
		income.Text = Format.cash(perSec) .. "/s"
		local digits = #income.Text
		income.Size = UDim2.fromScale(math.clamp(0.06 + digits * 0.045, 0.2, 0.6), 1)
	end

	board.Parent = gui
	tags[player] = { board = board, refresh = refresh }
	for _, attr in { "IncomePerSec", "VIP", "ServerRank", "WorldRank", "WorldBoard", "Training" } do
		player:GetAttributeChangedSignal(attr):Connect(refresh)
	end
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		refresh()
	end)
	refresh()
end

function NametagController:Init()
	gui = Ui.screen("Nametags", 0)
end

function NametagController:Start()
	Players.PlayerAdded:Connect(build)
	for _, p in Players:GetPlayers() do
		task.spawn(build, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		local t = tags[p]
		if t then
			t.board:Destroy()
			tags[p] = nil
		end
	end)
	-- Heads can be replaced (respawn, avatar reload): re-adorn now and then.
	task.spawn(function()
		while true do
			task.wait(2)
			for _, t in tags do
				t.refresh()
			end
		end
	end)
end

return NametagController
