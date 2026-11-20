--!strict
-- The hatch show (placeholder until HatchFx is ported with the ice-shard reskin): a card
-- with the pet, its rarity colour and mutation. Also the welcome-back card for offline cash.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local PetLook = require(Shared.PetLook)
local Pets = require(Shared.Config.Pets)
local Products = require(Shared.Config.Products)
local Ui = require(script.Parent.Parent.Ui)

local HatchController = {}

local card: Frame
local title: TextLabel
local sub: TextLabel
local viewport: ViewportFrame
local welcome: Frame
local welcomeText: TextLabel

local function showPet(info)
	local def = Pets.ById[info.PetId]
	local rarity = Eggs.ByName[info.Rarity]
	if not def then
		return
	end
	title.Text = string.upper((if info.Huge then "HUGE " else "") .. (if info.Mutation then info.Mutation .. " " else "") .. def.Name) .. "!"
	title.TextColor3 = if rarity then rarity.Color else Ui.Colors.Snow
	sub.Text = `{info.Rarity} · +{math.floor(def.Train * 100)}% training · ${Format.number(def.Income)}/s`
	viewport:ClearAllChildren()
	local model = PetLook.make(info.PetId, info.Mutation, info.Huge)
	if model then
		model:PivotTo(CFrame.new())
		model.Parent = viewport
		local cam = Instance.new("Camera")
		local _, size = model:GetBoundingBox()
		local d = math.max(size.X, size.Y, size.Z) * 1.6 + 2
		cam.CFrame = CFrame.lookAt(Vector3.new(d * 0.5, size.Y * 0.8, -d), Vector3.new(0, size.Y / 2, 0))
		cam.Parent = viewport
		viewport.CurrentCamera = cam
	end
	Ui.openWindow(card)
	local scale = card:FindFirstChildOfClass("UIScale") :: UIScale
	local base = scale.Scale
	scale.Scale = base * 0.3
	TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = base }):Play()
	Ui.sound("Pop", 0.8)
end

function HatchController:Init()
	local gui = Ui.screen("Hatch", 30)
	local body
	card, body = Ui.window(gui, "Card", "YOU HATCHED", Vector2.new(420, 420))
	viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(1, 0, 0, 220)
	viewport.BackgroundColor3 = Ui.Colors.PanelDark
	viewport.BorderSizePixel = 0
	viewport.Parent = body
	title = Ui.label({ Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 226), Text = "" })
	title.Parent = body
	sub = Ui.label({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 272), Text = "", TextColor3 = Ui.Colors.Ice })
	sub.Parent = body
	Ui.button({ Size = UDim2.new(1, 0, 0, 50), Position = UDim2.new(0, 0, 1, -52), BackgroundColor3 = Ui.Colors.Green }, "AWESOME!", function()
		Ui.closeWindow(card)
	end).Parent = body

	local wbody
	welcome, wbody = Ui.window(gui, "Welcome", "WELCOME BACK!", Vector2.new(420, 260))
	welcomeText = Ui.label({ Size = UDim2.new(1, 0, 0, 90), Text = "" })
	welcomeText.Parent = wbody
	local double = Ui.button({ Name = "Double", Size = UDim2.new(0.5, -6, 0, 56), Position = UDim2.new(0, 0, 1, -58), BackgroundColor3 = Ui.Colors.Robux }, `DOUBLE {Ui.ROBUX}49`, function()
		Net.func("PromptPurchase"):InvokeServer("DoubleOffline")
		Ui.closeWindow(welcome)
	end)
	double.Visible = (Products.ProductByKey.DoubleOffline and Products.ProductByKey.DoubleOffline.Id ~= 0) == true
	double.Parent = wbody
	Ui.button({ Size = UDim2.new(0.5, -6, 0, 56), Position = UDim2.new(0.5, 6, 1, -58), BackgroundColor3 = Ui.Colors.Green }, "COLLECT", function()
		Ui.closeWindow(welcome)
	end).Parent = wbody
end

function HatchController:Start()
	Net.event("HatchCompleted").OnClientEvent:Connect(showPet)
	Net.event("WelcomeBack").OnClientEvent:Connect(function(info)
		welcomeText.Text = `Your pets earned {Format.cash(info.Cash)} while you were away ({Format.duration(info.Seconds)})`
		Ui.openWindow(welcome)
	end)
end

return HatchController
