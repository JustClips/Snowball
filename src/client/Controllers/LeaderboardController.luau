--!strict
-- Leaderboards on the client (LeaderboardService publishes the top 50 of every board in
-- ReplicatedStorage.Leaderboards):
--   * the four plaza stands: a SurfaceGui on each stand's Screen part (header block with
--     the board's icon + one word, ALL TIME / THIS WEEK swapping every SwapSeconds, ten
--     rows with gold / silver / bronze crowns for the top 3). Tap a stand to open the window.
--   * the window: icon tabs for the 4 boards, THIS WEEK | ALL TIME, top 50, and your own
--     row pinned at the bottom (rank, or 50+).
--   * the competition moments (kids research, LihFolk vault "Social Design"): a card that
--     slides down at the top when you pass someone ("PASSED!" + their face + #rank), and a
--     SERVER RECORD! card for everyone when someone sets this server's best roll / luck.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Leaderboards)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Parent.Ui)

local LeaderboardController = {}

type Row = { U: number, N: string, S: number }

local CROWNS = { "Crown", "CrownSilver", "CrownBronze" }
local RANK_COLORS = { Color3.fromRGB(255, 205, 40), Color3.fromRGB(215, 222, 235), Color3.fromRGB(230, 140, 70) }
local PERIOD_WORD = { All = "ALL TIME", Week = "THIS WEEK" }
local PPS = 40 -- SurfaceGui pixels per stud

local player = Players.LocalPlayer
local folder: Instance? = nil
local gui: ScreenGui
local window: Frame
local tabButtons: { [string]: TextButton } = {}
local periodButtons: { [string]: TextButton } = {}
local listFrame: ScrollingFrame
local youRow: Frame
local resetChip: TextLabel
local selected = "Distance"
local period = "Week"
local mine: any = nil
local standPeriod = "All"
local standRefreshers: { () -> () } = {}

local function headshot(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=60&h=60`
end

local function rows(key: string, p: string): { Row }
	folder = folder or ReplicatedStorage:FindFirstChild("Leaderboards")
	local value = folder and folder:FindFirstChild(`{key}_{p}`) :: StringValue?
	if not value or value.Value == "" then
		return {}
	end
	local ok, list = pcall(HttpService.JSONDecode, HttpService, value.Value)
	return if ok and type(list) == "table" then list else {}
end

-- One row: rank (crown for 1-3), face, name, value. Sizes are scale so it works on the
-- stands (SurfaceGui) and in the window.
local function makeRow(parent: Instance, rank: number?, row: Row?, key: string, height: UDim, mineRow: boolean?): Frame
	local board = Config.ByKey[key]
	local f = Ui.frame({
		Name = "Row",
		Size = UDim2.new(1, 0, height.Scale, height.Offset),
		BackgroundColor3 = if mineRow
			then Ui.Colors.Blue
			elseif (rank or 0) % 2 == 1 then Ui.Colors.PanelDark
			else Ui.Colors.Panel,
		BackgroundTransparency = if mineRow then 0 else 0.15,
		LayoutOrder = rank or 999,
	})
	if rank and rank <= 3 and row then
		Ui.icon(CROWNS[rank], {
			Size = UDim2.fromScale(0.11, 0.86),
			Position = UDim2.fromScale(0.01, 0.07),
			ZIndex = f.ZIndex + 1,
		}).Parent =
			f
	else
		local r = Ui.label({
			Name = "Rank",
			Size = UDim2.fromScale(0.12, 0.7),
			Position = UDim2.fromScale(0.005, 0.15),
			Text = if rank then `#{rank}` else "50+",
			TextColor3 = Ui.Colors.Sub,
			ZIndex = f.ZIndex + 1,
		})
		Ui.maxText(r, 60)
		r.Parent = f
	end
	if row then
		local face = Instance.new("ImageLabel")
		face.Name = "Face"
		face.BackgroundColor3 = Ui.Colors.Ice
		face.BorderSizePixel = 0
		face.Size = UDim2.fromScale(0.1, 0.86)
		face.Position = UDim2.fromScale(0.135, 0.07)
		face.Image = headshot(row.U)
		face.ZIndex = f.ZIndex + 1
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = face
		Ui.stroke(face, 2)
		face.Parent = f
	end
	local name = Ui.label({
		Name = "Name",
		Size = UDim2.fromScale(0.43, 0.66),
		Position = UDim2.fromScale(0.25, 0.17),
		Text = if row then row.N else "...",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = if rank and rank <= 3 and row then RANK_COLORS[rank] else Ui.Colors.Snow,
		TextTransparency = if row then 0 else 0.5,
		ZIndex = f.ZIndex + 1,
	})
	Ui.maxText(name, 60)
	name.Parent = f
	local value = Ui.label({
		Name = "Value",
		Size = UDim2.fromScale(0.31, 0.66),
		Position = UDim2.fromScale(0.675, 0.17),
		Text = if row then Config.text(key, row.S) else "",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = if mineRow then Ui.Colors.Snow else board.Color,
		ZIndex = f.ZIndex + 1,
	})
	Ui.maxText(value, 60)
	value.Parent = f
	f.Parent = parent
	return f
end

-------------------------------------------------------------------------------- window

local function renderWindow()
	if not window or not window.Visible then
		return
	end
	local board = Config.ByKey[selected]
	Ui.setHeader(window, board.Color)
	for key, b in tabButtons do
		local def = Config.ByKey[key]
		Ui.tint(b, if key == selected then def.Color else Ui.Colors.PanelDark)
		local st = b:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = if key == selected then Color3.new(1, 1, 1) else Ui.Colors.Ink
		end
	end
	for p, b in periodButtons do
		Ui.tint(b, if p == period then Ui.Colors.Green else Ui.Colors.Muted)
	end
	folder = folder or ReplicatedStorage:FindFirstChild("Leaderboards")
	local ends = folder and folder:GetAttribute("WeekEndsAt")
	resetChip.Visible = period == "Week" and type(ends) == "number"
	if type(ends) == "number" then
		resetChip.Text = Format.duration(ends - os.time())
	end
	for _, c in listFrame:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local list = rows(selected, period)
	local myRank = nil
	for i, row in list do
		local r = makeRow(listFrame, i, row, selected, UDim.new(0, 52), row.U == player.UserId)
		r.ZIndex = 22
		if row.U == player.UserId then
			myRank = i
		end
	end
	if #list == 0 then
		for i = 1, 3 do
			makeRow(listFrame, i, nil, selected, UDim.new(0, 52))
		end
	end
	-- You, pinned at the bottom.
	for _, c in youRow:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local myScore = mine and mine[period] and mine[period][selected] or 0
	local r = makeRow(
		youRow,
		myRank,
		{ U = player.UserId, N = player.DisplayName, S = myScore },
		selected,
		UDim.new(1, 0),
		true
	)
	if myScore <= 0 then
		(r:FindFirstChild("Value") :: TextLabel).Text = Config.text(selected, 0)
	end
end

function LeaderboardController:Open(key: string?)
	if key and Config.ByKey[key] then
		selected = key
	end
	Ui.openWindow(window)
	Net.event("Analytics"):FireServer("Open", "Leaderboards")
	renderWindow()
	task.spawn(function()
		local ok, result = pcall(function()
			return Net.func("Leaderboards"):InvokeServer()
		end)
		if ok and type(result) == "table" then
			mine = result
			renderWindow()
		end
	end)
end

local function buildWindow()
	gui = Ui.screen("Leaderboards", 20)
	local w, body = Ui.window(gui, "Leaderboards", "TOP", Vector2.new(600, 660), {
		Icon = "Trophy",
		Color = Config.Boards[1].Color,
	})
	window = w
	-- Board tabs: one big icon each.
	for i, def in Config.Boards do
		local b = Ui.tile("Tab_" .. def.Key, def.Icon, "", def.Color, function()
			selected = def.Key
			renderWindow()
		end, 64)
		b.Size = UDim2.new(0.25, -9, 0, 64)
		b.Position = UDim2.new((i - 1) * 0.25, if i == 1 then 0 else 3 * (i - 1), 0, 0)
		b.ZIndex = 22
		b.Parent = body
		tabButtons[def.Key] = b
	end
	-- THIS WEEK | ALL TIME, and the week's reset countdown.
	for i, p in { "Week", "All" } do
		local b = Ui.button(
			{
				Name = "Period_" .. p,
				Size = UDim2.new(0, 170, 0, 44),
				Position = UDim2.fromOffset((i - 1) * 180, 76),
				BackgroundColor3 = Ui.Colors.Muted,
				ZIndex = 22,
			},
			PERIOD_WORD[p],
			function()
				period = p
				renderWindow()
			end
		)
		b.Parent = body
		periodButtons[p] = b
	end
	Ui.icon("Clock", {
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -112, 0, 78),
		ZIndex = 22,
	}).Parent =
		body
	resetChip = Ui.label({
		Name = "Reset",
		Size = UDim2.fromOffset(106, 34),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 81),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
	})
	Ui.maxText(resetChip, 26)
	resetChip.Parent = body
	listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "List"
	listFrame.BackgroundColor3 = Ui.Colors.PanelDark
	listFrame.BorderSizePixel = 0
	listFrame.Position = UDim2.fromOffset(0, 130)
	listFrame.Size = UDim2.new(1, 0, 1, -130 - 64)
	listFrame.ScrollBarThickness = 8
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.CanvasSize = UDim2.new()
	listFrame.ZIndex = 21
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = listFrame
	Ui.stroke(listFrame, 3)
	listFrame.Parent = body
	youRow = Ui.frame({
		Name = "You",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 56),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		ZIndex = 22,
	})
	youRow.Parent = body
	window:GetPropertyChangedSignal("Visible"):Connect(renderWindow)
end

-------------------------------------------------------------------------------- stands

local function buildStand(screen: BasePart)
	local key = screen:GetAttribute("Board")
	local def = Config.ByKey[tostring(key)]
	if not def then
		return
	end
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Stand_" .. def.Key
	surface.Adornee = screen
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = PPS
	surface.LightInfluence = 0
	surface.MaxDistance = 300
	surface.ResetOnSpawn = false
	surface.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = Ui.frame({
		Name = "Canvas",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.Colors.Panel,
	})
	canvas.Parent = surface
	-- Header: board colour block, icon + one word.
	local header = Ui.frame({
		Name = "Header",
		Size = UDim2.fromScale(1, 0.15),
		BackgroundColor3 = def.Color,
	})
	Ui.block(header, nil, 4, 10)
	Ui.icon(def.Icon, {
		Size = UDim2.fromScale(0.2, 0.92),
		Position = UDim2.fromScale(0.02, 0.02),
		ZIndex = 3,
	}).Parent =
		header
	local title = Ui.label({
		Size = UDim2.fromScale(0.74, 0.72),
		Position = UDim2.fromScale(0.24, 0.1),
		Text = def.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	Ui.maxText(title, 120)
	local ts = title:FindFirstChildOfClass("UIStroke")
	if ts then
		ts.Thickness = 4
	end
	title.Parent = header
	header.Parent = canvas
	-- ALL TIME / THIS WEEK chip under the header.
	local chip = Ui.label({
		Name = "Period",
		Size = UDim2.fromScale(1, 0.055),
		Position = UDim2.fromScale(0, 0.165),
		Text = "",
		TextColor3 = Ui.Colors.Yellow,
	})
	Ui.maxText(chip, 60)
	chip.Parent = canvas
	local rowsFrame = Ui.frame({
		Name = "Rows",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.96, 0.765),
		Position = UDim2.fromScale(0.02, 0.228),
	})
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.005, 0)
	layout.Parent = rowsFrame
	rowsFrame.Parent = canvas
	-- Tap the stand to open the window on this board.
	local tap = Instance.new("TextButton")
	tap.Name = "Tap"
	tap.Text = ""
	tap.BackgroundTransparency = 1
	tap.Size = UDim2.fromScale(1, 1)
	tap.ZIndex = 50
	tap.Activated:Connect(function()
		LeaderboardController:Open(def.Key)
	end)
	tap.Parent = canvas

	local function refresh()
		chip.Text = PERIOD_WORD[standPeriod]
		for _, c in rowsFrame:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local list = rows(def.Key, standPeriod)
		for i = 1, Config.WorldTop do
			makeRow(rowsFrame, i, list[i], def.Key, UDim.new(0.095, 0), list[i] ~= nil and list[i].U == player.UserId)
		end
	end
	table.insert(standRefreshers, refresh)
	refresh()
	surface.Parent = player:WaitForChild("PlayerGui")
end

local function watchStands()
	local mountain = Workspace:WaitForChild("Mountain")
	local summit = mountain:WaitForChild("Summit")
	local stands = summit:WaitForChild("Leaderboards", 60)
	if not stands then
		return
	end
	local done: { [Instance]: boolean } = {}
	local function try(stand: Instance)
		local screen = stand:WaitForChild("Screen", 10)
		if screen and screen:IsA("BasePart") and not done[screen] then
			done[screen] = true
			buildStand(screen)
		end
	end
	stands.ChildAdded:Connect(try)
	for _, s in stands:GetChildren() do
		task.spawn(try, s)
	end
end

-------------------------------------------------------------------------------- cards

local card: Frame
local cardQueue: { () -> () } = {}
local cardBusy = false

local function buildCard()
	local holder = Ui.frame({
		Name = "RankCard",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(380, 92),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 72),
	})
	Ui.autoScale(holder)
	holder.Parent = Ui.screen("RankCards", 40)
	card = Ui.frame({
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, -2.2),
		BackgroundColor3 = Ui.Colors.PanelDark,
		Visible = false,
	})
	Ui.block(card, nil, 3, 6)
	local face = Instance.new("ImageLabel")
	face.Name = "Face"
	face.BackgroundColor3 = Ui.Colors.Ice
	face.BorderSizePixel = 0
	face.Size = UDim2.fromOffset(74, 74)
	face.Position = UDim2.fromOffset(8, 6)
	face.ZIndex = 3
	Ui.stroke(face, 3)
	face.Parent = card
	local word = Ui.label({
		Name = "Word",
		Size = UDim2.new(1, -196, 0, 46),
		Position = UDim2.fromOffset(92, 4),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	Ui.maxText(word, 40)
	local ws = word:FindFirstChildOfClass("UIStroke")
	if ws then
		ws.Thickness = 3
	end
	word.Parent = card
	local name = Ui.label({
		Name = "Name",
		Size = UDim2.new(1, -196, 0, 30),
		Position = UDim2.fromOffset(92, 50),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	Ui.maxText(name, 26)
	name.Parent = card
	local chip = Ui.frame({
		Name = "Chip",
		Size = UDim2.fromOffset(94, 74),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		BackgroundColor3 = Ui.Colors.Blue,
		ZIndex = 3,
	})
	Ui.block(chip, nil, 3, 5)
	Ui.icon("Roll", {
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2),
		ZIndex = 4,
	}).Parent =
		chip
	local chipText = Ui.label({
		Name = "Text",
		Size = UDim2.new(1, -8, 0, 28),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Text = "",
		ZIndex = 4,
	})
	Ui.maxText(chipText, 26)
	chipText.Parent = chip
	chip.Parent = card
	local tap = Instance.new("TextButton")
	tap.Text = ""
	tap.BackgroundTransparency = 1
	tap.Size = UDim2.fromScale(1, 1)
	tap.ZIndex = 10
	tap.Parent = card
	tap.Activated:Connect(function()
		local b = card:GetAttribute("Board")
		LeaderboardController:Open(if type(b) == "string" then b else nil)
	end)
	card.Parent = holder
end

-- Shows the card: face, big word, a name line, a chip (board icon + short text).
local function showCard(info: { [string]: any })
	table.insert(cardQueue, function()
		local def = Config.ByKey[info.Board] or Config.Boards[1]
		card:SetAttribute("Board", def.Key);
		(card:FindFirstChild("Face") :: ImageLabel).Image = headshot(info.UserId)
		local word = card:FindFirstChild("Word") :: TextLabel
		word.Text = info.Word
		word.TextColor3 = info.WordColor or def.Color;
		(card:FindFirstChild("Name") :: TextLabel).Text = info.Line
		local chip = card:FindFirstChild("Chip") :: Frame
		Ui.tint(chip, def.Color);
		(chip:FindFirstChild("Icon") :: ImageLabel).Image = Ui.Images[info.ChipIcon or def.Icon] or ""
		(chip:FindFirstChild("Text") :: TextLabel).Text = info.Chip
		Ui.tint(card, info.Back or Ui.Colors.PanelDark)
		Ui.sound(info.Sound or "Good")
		card.Visible = true
		card.Position = UDim2.fromScale(0, -2.2)
		TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0, 0) })
			:Play()
		task.wait(info.Hold or 3)
		TweenService:Create(card, TweenInfo.new(0.25), { Position = UDim2.fromScale(0, -2.2) }):Play()
		task.wait(0.3)
		card.Visible = false
	end)
	if cardBusy then
		return
	end
	cardBusy = true
	task.spawn(function()
		while #cardQueue > 0 do
			local f = table.remove(cardQueue, 1) :: () -> ()
			f()
		end
		cardBusy = false
	end)
end

local function onRankEvent(event: any)
	if type(event) ~= "table" or event.Kind ~= "Passed" then
		return
	end
	local chip = if event.Rank then `#{event.Rank}` else "+1"
	if event.Scope == "Week" and event.Rank then
		chip = `#{event.Rank}`
	end
	showCard({
		Board = event.Board,
		UserId = event.UserId,
		Word = "PASSED!",
		Line = tostring(event.Name or ""),
		Chip = chip,
		ChipIcon = if event.Scope == "Server" then nil else "Trophy",
	})
end

local function onServerRecord(event: any)
	if type(event) ~= "table" then
		return
	end
	local me = event.UserId == player.UserId
	showCard({
		Board = event.Board,
		UserId = event.UserId,
		Word = "SERVER BEST!",
		WordColor = Ui.Colors.Yellow,
		Line = tostring(event.Name or ""),
		Chip = Config.text(event.Board, tonumber(event.Score) or 0),
		Back = if me then Ui.Colors.Purple else Ui.Colors.PanelDark,
		Sound = if me then "Winner" else "Good",
		Hold = 3.5,
	})
end

-------------------------------------------------------------------------------- boot

function LeaderboardController:Init()
	buildWindow()
	buildCard()
end

function LeaderboardController:Start()
	folder = ReplicatedStorage:WaitForChild("Leaderboards", 30)
	task.spawn(watchStands)
	if folder then
		local function changed()
			for _, f in standRefreshers do
				f()
			end
			renderWindow()
		end
		folder.ChildAdded:Connect(function(v)
			if v:IsA("StringValue") then
				v.Changed:Connect(changed)
				changed()
			end
		end)
		for _, v in folder:GetChildren() do
			if v:IsA("StringValue") then
				v.Changed:Connect(changed)
			end
		end
	end
	Net.event("RankEvent").OnClientEvent:Connect(onRankEvent)
	Net.event("ServerRecord").OnClientEvent:Connect(onServerRecord)
	-- The stands swap ALL TIME / THIS WEEK.
	task.spawn(function()
		while true do
			task.wait(Config.SwapSeconds)
			standPeriod = if standPeriod == "All" then "Week" else "All"
			for _, f in standRefreshers do
				f()
			end
		end
	end)
end

return LeaderboardController
