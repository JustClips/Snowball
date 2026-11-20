--!strict
-- One place for a pet's numbers, used by the server (income, training) and the client
-- (hover card, inventory tiles), so what you see is what you get.
local Eggs = require(script.Parent.Config.Eggs)
local Pets = require(script.Parent.Config.Pets)

local PetStats = {}

local mutationMult: { [string]: number } = {}
for _, m in Eggs.Mutations do
	mutationMult[m.Name] = m.IncomeMult
end

-- Weight / normal weight for its rarity (1 = normal). Old pets without a weight are 1.
function PetStats.weightMult(pet: any): number
	local def = Pets.ById[pet.Id]
	if not def or type(pet.Weight) ~= "number" then
		return 1
	end
	local base = (Pets.Kg[def.Rarity] or 1) * (if pet.Huge then 10 else 1)
	return math.clamp(pet.Weight / base, 0.5, 3)
end

-- How much bigger a pet is drawn for its weight.
function PetStats.sizeMult(pet: any): number
	return PetStats.weightMult(pet) ^ (1 / 3)
end

-- $/s before boosts.
function PetStats.income(pet: any): number
	local def = Pets.ById[pet.Id]
	if not def then
		return 0
	end
	local mult = (Pets.ZoneMult[pet.Zone or "Meadow"] or 1) * (mutationMult[pet.Mutation or ""] or 1)
	if pet.Huge then
		mult *= Eggs.HugeIncomeMult
	end
	return def.Income * mult * PetStats.weightMult(pet)
end

-- Training boost (0.2 = +20%).
function PetStats.train(pet: any): number
	local def = Pets.ById[pet.Id]
	if not def then
		return 0
	end
	local mult = (Pets.TrainZoneMult[pet.Zone or "Meadow"] or 1) * math.sqrt(mutationMult[pet.Mutation or ""] or 1)
	if pet.Huge then
		mult *= 3
	end
	return def.Train * mult
end

function PetStats.name(pet: any): string
	local def = Pets.ById[pet.Id]
	return (if pet.Huge then "Huge " else "")
		.. (if pet.Mutation then pet.Mutation .. " " else "")
		.. (def and def.Name or tostring(pet.Id))
end

function PetStats.rarity(pet: any): string
	local def = Pets.ById[pet.Id]
	return def and def.Rarity or "Common"
end

function PetStats.color(pet: any): Color3
	local r = Eggs.ByName[PetStats.rarity(pet)]
	return if r then r.Color else Color3.new(1, 1, 1)
end

function PetStats.kgText(kg: number?): string
	if not kg then
		return "?"
	end
	if kg >= 100 then
		return `{math.floor(kg + 0.5)} kg`
	end
	return string.format("%.1f kg", kg)
end

return PetStats
