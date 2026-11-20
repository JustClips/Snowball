--!strict
-- Loads the pet pack (Config/Assets.PetPack) once and puts every animal in
-- ReplicatedStorage.PetModels, so the server (base pets) and clients (followers) clone
-- from the same models. If the pack can't load (the place isn't owned by the account
-- that uploaded it), pets are graybox blocks coloured by rarity, and a warning says so.
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)

local PetModels = {}

local folder: Folder? = nil

function PetModels.load()
	if folder then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "PetModels"
	folder = f
	if Assets.PetPack ~= 0 then
		local ok, result = pcall(function()
			return InsertService:LoadAsset(Assets.PetPack)
		end)
		if ok and result then
			local pack = result:FindFirstChildWhichIsA("Model")
			if pack then
				for _, model in pack:GetChildren() do
					if model:IsA("Model") then
						for _, d in model:GetDescendants() do
							if d:IsA("BasePart") then
								d.Anchored = true
								d.CanCollide = false
								d.CanQuery = false
								d.CanTouch = false
								d.Massless = true
							end
						end
						model.Parent = f
					end
				end
			end
			result:Destroy()
		else
			warn(`[PetModels] couldn't load the pet pack {Assets.PetPack} ({result}). Pets show as blocks until the place is published under the account that uploaded it.`)
		end
	end
	f.Parent = ReplicatedStorage
end

return PetModels
