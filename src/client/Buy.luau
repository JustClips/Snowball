--!strict
-- Every Robux buy from a window goes through here (Sweep the World's flow, Dev 2026-11-20):
-- the window hides, a dim "Processing..." screen with a spinning ring shows while Roblox's
-- buy box is up, and when it closes the window comes back where it was (after the BOUGHT!
-- stamp if it was bought). Studio test buys (no buy box) finish right away.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer

local Buy = {}

local overlay: Frame? = nil
local ring: ImageLabel? = nil
local busy = false
local spin: RBXScriptConnection? = nil

local function build(): Frame
	if overlay then
		return overlay
	end
	local gui = Ui.screen("Processing", 55)
	local f = Ui.frame({
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 50,
	})
	local r = Ui.icon("Fx_Ring", {
		Name = "Ring",
		Size = UDim2.fromOffset(110, 110),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -30),
		ImageColor3 = Color3.fromRGB(120, 220, 255),
		ZIndex = 51,
	})
	r.Parent = f
	Ui.label({
		Name = "Text",
		Size = UDim2.fromOffset(360, 48),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 40),
		Text = "Processing...",
		ZIndex = 51,
	}).Parent =
		f
	f.Parent = gui
	overlay = f
	ring = r
	return f
end

local function show(on: boolean)
	local f = build()
	f.Visible = on
	if on and not spin then
		spin = RunService.RenderStepped:Connect(function(dt)
			if ring then
				ring.Rotation = (ring.Rotation + dt * 300) % 360
			end
		end)
	elseif not on and spin then
		spin:Disconnect()
		spin = nil
	end
end

function Buy.isBusy(): boolean
	return busy
end

-- Prompts key (optionally as a gift). window: hidden while buying and shown again after.
-- Returns whether Roblox's buy box opened (or a Studio test buy ran).
function Buy.prompt(key: string, giftTo: number?, window: GuiObject?): boolean
	if busy then
		return false
	end
	busy = true
	local wasOpen = window ~= nil and window.Visible
	if window then
		window.Visible = false
	end
	show(true)
	local def = Products.ProductByKey[key] or Products.PassByKey[key]
	local isPass = Products.PassByKey[key] ~= nil
	local finished = false
	local bought = false
	local conns = {}
	if def and def.Id ~= 0 then
		if isPass then
			table.insert(
				conns,
				MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who, id, ok)
					if who == player and id == def.Id then
						finished, bought = true, ok
					end
				end)
			)
		else
			table.insert(
				conns,
				MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, id, ok)
					if userId == player.UserId and id == def.Id then
						finished, bought = true, ok
					end
				end)
			)
		end
	end
	local ok, why = Net.func("PromptPurchase"):InvokeServer(key, giftTo)
	if not ok then
		if why then
			Ui.toast(why, "Bad")
		end
		finished = true
	elseif why == "Studio" then
		finished, bought = true, true
	end
	local started = os.clock()
	while not finished and os.clock() - started < 90 do
		task.wait(0.1)
	end
	for _, c in conns do
		c:Disconnect()
	end
	show(false)
	if bought then
		task.wait(1.6) -- let the BOUGHT! stamp play first
	end
	if window and wasOpen then
		window.Visible = true
	end
	busy = false
	return ok == true
end

return Buy
