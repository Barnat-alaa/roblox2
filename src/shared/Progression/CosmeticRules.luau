--!strict

local Cosmetics = require(script.Parent.Parent.Config.Cosmetics)

local CosmeticRules = {}

export type CosmeticInventory = {
	ownedCosmetics: { string },
	equippedCosmetic: string,
}

local INVENTORY_FIELDS = table.freeze({
	ownedCosmetics = true,
	equippedCosmetic = true,
})

local function onlyHasFields(value: { [any]: any }, allowedFields: { [string]: boolean }): boolean
	for field in value do
		if typeof(field) ~= "string" or not allowedFields[field :: string] then
			return false
		end
	end
	return true
end

local function validateCosmeticId(value: unknown): (boolean, string?)
	if
		type(value) ~= "string"
		or #value < 1
		or #value > Cosmetics.MAX_COSMETIC_ID_LENGTH
		or value:match("^[a-z][a-z0-9_]*$") ~= value
	then
		return false, "invalid_cosmetic_id"
	end
	if Cosmetics.get(value) == nil then
		return false, "unknown_cosmetic"
	end
	return true, nil
end

local function validateOwned(value: unknown): (boolean, string?)
	if typeof(value) ~= "table" then
		return false, "invalid_owned_cosmetics"
	end
	local owned = value :: { [any]: any }
	local count = 0
	local maximumIndex = 0
	for index in owned do
		if
			type(index) ~= "number"
			or index ~= math.floor(index)
			or index < 1
			or index > Cosmetics.MAX_OWNED_COSMETICS
		then
			return false, "invalid_owned_cosmetic_index"
		end
		count += 1
		maximumIndex = math.max(maximumIndex, index)
	end
	if count ~= maximumIndex then
		return false, "sparse_owned_cosmetics"
	end

	local previousId: string? = nil
	for index = 1, maximumIndex do
		local cosmeticId = owned[index]
		local valid, reason = validateCosmeticId(cosmeticId)
		if not valid then
			return false, reason
		end
		if previousId ~= nil and (cosmeticId :: string) <= previousId then
			return false, "unsorted_or_duplicate_owned_cosmetics"
		end
		previousId = cosmeticId :: string
	end
	return true, nil
end

function CosmeticRules.createDefault(): CosmeticInventory
	return {
		ownedCosmetics = { Cosmetics.STARTER_COSMETIC_ID },
		equippedCosmetic = Cosmetics.STARTER_COSMETIC_ID,
	}
end

function CosmeticRules.clone(inventory: CosmeticInventory): CosmeticInventory
	return {
		ownedCosmetics = table.clone(inventory.ownedCosmetics),
		equippedCosmetic = inventory.equippedCosmetic,
	}
end

function CosmeticRules.validate(value: unknown): (boolean, string?)
	if typeof(value) ~= "table" then
		return false, "invalid_inventory"
	end
	local inventory = value :: { [any]: any }
	if not onlyHasFields(inventory, INVENTORY_FIELDS) then
		return false, "invalid_inventory_fields"
	end
	local ownedValid, ownedReason = validateOwned(inventory.ownedCosmetics)
	if not ownedValid then
		return false, ownedReason
	end
	local equippedValid, equippedReason = validateCosmeticId(inventory.equippedCosmetic)
	if not equippedValid then
		return false, equippedReason
	end
	local definition = Cosmetics.get(inventory.equippedCosmetic :: string)
	if definition == nil or not definition.enabled then
		return false, "disabled_cosmetic"
	end
	for _, ownedId in inventory.ownedCosmetics :: { string } do
		if ownedId == inventory.equippedCosmetic then
			return true, nil
		end
	end
	return false, "equipped_cosmetic_not_owned"
end

function CosmeticRules.owns(inventory: CosmeticInventory, cosmeticId: string): boolean
	for _, ownedId in inventory.ownedCosmetics do
		if ownedId == cosmeticId then
			return true
		end
	end
	return false
end

function CosmeticRules.canEquip(
	inventory: CosmeticInventory,
	cosmeticId: string
): (boolean, string?)
	local inventoryValid, inventoryReason = CosmeticRules.validate(inventory)
	if not inventoryValid then
		return false, inventoryReason
	end
	local idValid, idReason = validateCosmeticId(cosmeticId)
	if not idValid then
		return false, idReason
	end
	local definition = Cosmetics.get(cosmeticId)
	if definition == nil or not definition.enabled then
		return false, "disabled_cosmetic"
	end
	if not CosmeticRules.owns(inventory, cosmeticId) then
		return false, "cosmetic_not_owned"
	end
	return true, nil
end

function CosmeticRules.equip(
	inventory: CosmeticInventory,
	cosmeticId: string
): (CosmeticInventory?, string?)
	local allowed, reason = CosmeticRules.canEquip(inventory, cosmeticId)
	if not allowed then
		return nil, reason
	end
	local updated = CosmeticRules.clone(inventory)
	updated.equippedCosmetic = cosmeticId
	return updated, nil
end

return table.freeze(CosmeticRules)
