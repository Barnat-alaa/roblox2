--!strict

-- Original, presentation-only cosmetics. These definitions may affect appearance,
-- but never character collision, aim origins, movement, health, or weapon balance.

local Cosmetics = {}

export type CosmeticCategory = "neckwear"
export type AcquisitionType = "starter"

export type CosmeticDefinition = {
	id: string,
	displayName: string,
	description: string,
	category: CosmeticCategory,
	acquisitionType: AcquisitionType,
	enabled: boolean,
	primaryColor: Color3,
	accentColor: Color3,
}

local MAX_COSMETIC_ID_LENGTH = 64

local function validateDefinition(definition: CosmeticDefinition): (boolean, string?)
	if
		definition.id == ""
		or #definition.id > MAX_COSMETIC_ID_LENGTH
		or definition.id:match("^[a-z][a-z0-9_]*$") ~= definition.id
	then
		return false, "id must be bounded lower snake_case"
	end
	if definition.displayName:match("%S") == nil then
		return false, `{definition.id}: displayName must not be blank`
	end
	if definition.description:match("%S") == nil then
		return false, `{definition.id}: description must not be blank`
	end
	if definition.category ~= "neckwear" then
		return false, `{definition.id}: unsupported category`
	end
	if definition.acquisitionType ~= "starter" then
		return false, `{definition.id}: unsupported acquisitionType`
	end
	if typeof(definition.enabled) ~= "boolean" then
		return false, `{definition.id}: enabled must be boolean`
	end
	if
		typeof(definition.primaryColor) ~= "Color3"
		or typeof(definition.accentColor) ~= "Color3"
	then
		return false, `{definition.id}: appearance colors must be Color3 values`
	end
	return true, nil
end

local function define(definition: CosmeticDefinition): CosmeticDefinition
	local valid, reason = validateDefinition(definition)
	assert(valid, reason or "invalid cosmetic definition")
	return table.freeze(definition)
end

-- A warm two-tone scout scarf is deliberately original code-built placeholder art.
-- Its broad knot and split tails stay outside the combat silhouette and carry no physics.
local SUNSET_SCOUT_SCARF = define({
	id = "sunset_scout_scarf",
	displayName = "Sunset Scout Scarf",
	description = "A bright camp scarf with a cream compass stitch for curious arena explorers.",
	category = "neckwear",
	acquisitionType = "starter",
	enabled = true,
	primaryColor = Color3.fromRGB(245, 112, 74),
	accentColor = Color3.fromRGB(255, 226, 153),
})

local ALL: { CosmeticDefinition } = {
	SUNSET_SCOUT_SCARF,
}

local BY_ID: { [string]: CosmeticDefinition } = {}
for _, definition in ALL do
	assert(BY_ID[definition.id] == nil, `duplicate cosmetic id: {definition.id}`)
	BY_ID[definition.id] = definition
end

Cosmetics.MAX_COSMETIC_ID_LENGTH = MAX_COSMETIC_ID_LENGTH
Cosmetics.MAX_OWNED_COSMETICS = 32
Cosmetics.STARTER_COSMETIC_ID = SUNSET_SCOUT_SCARF.id
Cosmetics.SUNSET_SCOUT_SCARF = SUNSET_SCOUT_SCARF
Cosmetics.All = table.freeze(ALL)
Cosmetics.ById = table.freeze(BY_ID)
Cosmetics.validateDefinition = validateDefinition

function Cosmetics.get(id: string): CosmeticDefinition?
	return BY_ID[id]
end

return table.freeze(Cosmetics)
