--!strict

-- Authoritative, data-driven MVP weapon catalogue. Clients may read these values
-- for UI and prediction; the server must resolve the id from this catalogue and
-- must never accept a client-supplied definition or damage value.

local Weapons = {}

export type DetonationMode = "Impact" | "Fuse" | "Drill" | "BounceLimit"
export type CameraMode = "Follow" | "Wide"

export type ProjectileDefinition = {
	id: string,
	displayName: string,
	description: string,
	detonationMode: DetonationMode,

	initialSpeedMin: number,
	initialSpeedMax: number,
	gravityScale: number,
	windScale: number,

	fuseTime: number?,
	maxLifetime: number,
	bounceCount: number,
	restitution: number,
	penetrationDepth: number,

	explosionRadius: number,
	terrainRadius: number,
	maxDamage: number,
	minDamage: number,
	knockbackStrength: number,

	projectileCount: number,
	spreadAngle: number,
	canDamageOwner: boolean,
	cameraMode: CameraMode,
}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isInteger(value: number): boolean
	return isFinite(value) and value == math.floor(value)
end

function Weapons.validateDefinition(definition: ProjectileDefinition): (boolean, string?)
	if definition.id == "" or definition.id:match("^[a-z][a-z0-9_]*$") ~= definition.id then
		return false, "id must be lower snake_case"
	end
	if definition.displayName:match("%S") == nil then
		return false, `{definition.id}: displayName must not be blank`
	end
	if definition.description:match("%S") == nil then
		return false, `{definition.id}: description must not be blank`
	end

	if
		definition.detonationMode ~= "Impact"
		and definition.detonationMode ~= "Fuse"
		and definition.detonationMode ~= "Drill"
		and definition.detonationMode ~= "BounceLimit"
	then
		return false, `{definition.id}: unsupported detonationMode`
	end
	if definition.cameraMode ~= "Follow" and definition.cameraMode ~= "Wide" then
		return false, `{definition.id}: unsupported cameraMode`
	end

	if not isFinite(definition.initialSpeedMin) or definition.initialSpeedMin <= 0 then
		return false, `{definition.id}: initialSpeedMin must be positive`
	end
	if
		not isFinite(definition.initialSpeedMax)
		or definition.initialSpeedMax < definition.initialSpeedMin
	then
		return false, `{definition.id}: initialSpeedMax must be at least initialSpeedMin`
	end
	if definition.initialSpeedMax > 200 then
		return false, `{definition.id}: initialSpeedMax exceeds the simulation safety cap`
	end
	if
		not isFinite(definition.gravityScale)
		or definition.gravityScale < 0
		or definition.gravityScale > 3
	then
		return false, `{definition.id}: gravityScale must be in [0, 3]`
	end
	if
		not isFinite(definition.windScale)
		or definition.windScale < 0
		or definition.windScale > 3
	then
		return false, `{definition.id}: windScale must be in [0, 3]`
	end

	if
		not isFinite(definition.maxLifetime)
		or definition.maxLifetime <= 0
		or definition.maxLifetime > 15
	then
		return false, `{definition.id}: maxLifetime must be in (0, 15]`
	end
	if
		not isInteger(definition.bounceCount)
		or definition.bounceCount < 0
		or definition.bounceCount > 10
	then
		return false, `{definition.id}: bounceCount must be an integer in [0, 10]`
	end
	if
		not isFinite(definition.restitution)
		or definition.restitution < 0
		or definition.restitution > 1
	then
		return false, `{definition.id}: restitution must be in [0, 1]`
	end
	if
		not isFinite(definition.penetrationDepth)
		or definition.penetrationDepth < 0
		or definition.penetrationDepth > 64
	then
		return false, `{definition.id}: penetrationDepth must be in [0, 64]`
	end
	if definition.fuseTime ~= nil then
		if
			not isFinite(definition.fuseTime)
			or definition.fuseTime <= 0
			or definition.fuseTime > definition.maxLifetime
		then
			return false, `{definition.id}: fuseTime must be in (0, maxLifetime]`
		end
	end

	if
		not isFinite(definition.explosionRadius)
		or definition.explosionRadius <= 0
		or definition.explosionRadius > 64
	then
		return false, `{definition.id}: explosionRadius must be in (0, 64]`
	end
	if
		not isFinite(definition.terrainRadius)
		or definition.terrainRadius < 0
		or definition.terrainRadius > 64
	then
		return false, `{definition.id}: terrainRadius must be in [0, 64]`
	end
	if not isFinite(definition.minDamage) or definition.minDamage < 0 then
		return false, `{definition.id}: minDamage must be non-negative`
	end
	if
		not isFinite(definition.maxDamage)
		or definition.maxDamage < definition.minDamage
		or definition.maxDamage > 100
	then
		return false, `{definition.id}: maxDamage must be in [minDamage, 100]`
	end
	if
		not isFinite(definition.knockbackStrength)
		or definition.knockbackStrength < 0
		or definition.knockbackStrength > 150
	then
		return false, `{definition.id}: knockbackStrength must be in [0, 150]`
	end

	if
		not isInteger(definition.projectileCount)
		or definition.projectileCount < 1
		or definition.projectileCount > 16
	then
		return false, `{definition.id}: projectileCount must be an integer in [1, 16]`
	end
	if
		not isFinite(definition.spreadAngle)
		or definition.spreadAngle < 0
		or definition.spreadAngle > 90
	then
		return false, `{definition.id}: spreadAngle must be in [0, 90]`
	end
	if definition.projectileCount == 1 and definition.spreadAngle ~= 0 then
		return false, `{definition.id}: a single projectile must have zero spreadAngle`
	end

	if definition.bounceCount == 0 and definition.restitution ~= 0 then
		return false, `{definition.id}: a non-bouncing projectile must have zero restitution`
	end
	if definition.bounceCount > 0 and definition.restitution <= 0 then
		return false, `{definition.id}: a bouncing projectile needs positive restitution`
	end

	if definition.detonationMode == "Impact" then
		if
			definition.fuseTime ~= nil
			or definition.bounceCount ~= 0
			or definition.penetrationDepth ~= 0
		then
			return false, `{definition.id}: Impact mode cannot fuse, bounce, or penetrate`
		end
	elseif definition.detonationMode == "Fuse" then
		if
			definition.fuseTime == nil
			or definition.bounceCount < 1
			or definition.penetrationDepth ~= 0
		then
			return false, `{definition.id}: Fuse mode needs a fuse and bounce, with no penetration`
		end
	elseif definition.detonationMode == "Drill" then
		if
			definition.fuseTime ~= nil
			or definition.bounceCount ~= 0
			or definition.penetrationDepth <= 0
			or definition.terrainRadius <= definition.explosionRadius
		then
			return false,
				`{definition.id}: Drill mode needs penetration and a larger terrain radius`
		end
	elseif definition.detonationMode == "BounceLimit" then
		if
			definition.fuseTime ~= nil
			or definition.bounceCount < 2
			or definition.restitution < 0.6
			or definition.penetrationDepth ~= 0
		then
			return false, `{definition.id}: BounceLimit mode needs at least two elastic bounces`
		end
	end

	return true, nil
end

function Weapons.validateCatalogue(catalogue: { ProjectileDefinition }): (boolean, string?)
	local seen: { [string]: boolean } = {}

	for _, definition in catalogue do
		local valid, reason = Weapons.validateDefinition(definition)
		if not valid then
			return false, reason
		end
		if seen[definition.id] then
			return false, `duplicate weapon id: {definition.id}`
		end
		seen[definition.id] = true
	end

	return true, nil
end

local function define(definition: ProjectileDefinition): ProjectileDefinition
	local valid, reason = Weapons.validateDefinition(definition)
	assert(valid, reason or "invalid weapon definition")
	return table.freeze(definition)
end

local ACORN_CANNON = define({
	id = "acorn_cannon",
	displayName = "Acorn Cannon",
	description = "A dependable impact shot with balanced damage, wind response, and terrain removal.",
	detonationMode = "Impact",
	initialSpeedMin = 58,
	initialSpeedMax = 92,
	gravityScale = 1,
	windScale = 1,
	fuseTime = nil,
	maxLifetime = 5,
	bounceCount = 0,
	restitution = 0,
	penetrationDepth = 0,
	explosionRadius = 12,
	terrainRadius = 10,
	maxDamage = 38,
	minDamage = 12,
	knockbackStrength = 40,
	projectileCount = 1,
	spreadAngle = 0,
	canDamageOwner = true,
	cameraMode = "Follow",
})

local FIZZY_BOMB = define({
	id = "fizzy_bomb",
	displayName = "Fizzy Bomb",
	description = "A short-fuse capsule that bounces behind cover before bursting into foam.",
	detonationMode = "Fuse",
	initialSpeedMin = 45,
	initialSpeedMax = 74,
	gravityScale = 1.1,
	windScale = 0.85,
	fuseTime = 2.25,
	maxLifetime = 6,
	bounceCount = 2,
	restitution = 0.5,
	penetrationDepth = 0,
	explosionRadius = 11,
	terrainRadius = 9,
	maxDamage = 32,
	minDamage = 10,
	knockbackStrength = 44,
	projectileCount = 1,
	spreadAngle = 0,
	canDamageOwner = true,
	cameraMode = "Wide",
})

local MOLE_DRILL = define({
	id = "mole_drill",
	displayName = "Mole Drill",
	description = "A heavy, wind-resistant tunnelling shot that trades damage for terrain control.",
	detonationMode = "Drill",
	initialSpeedMin = 52,
	initialSpeedMax = 78,
	gravityScale = 0.35,
	windScale = 0.2,
	fuseTime = nil,
	maxLifetime = 4,
	bounceCount = 0,
	restitution = 0,
	penetrationDepth = 24,
	explosionRadius = 7,
	terrainRadius = 16,
	maxDamage = 20,
	minDamage = 5,
	knockbackStrength = 18,
	projectileCount = 1,
	spreadAngle = 0,
	canDamageOwner = true,
	cameraMode = "Follow",
})

local BUBBLE_BOUNCER = define({
	id = "bubble_bouncer",
	displayName = "Bubble Bouncer",
	description = "A light, wind-sensitive orb that rewards planned ricochets with a flexible attack angle.",
	detonationMode = "BounceLimit",
	initialSpeedMin = 50,
	initialSpeedMax = 80,
	gravityScale = 0.75,
	windScale = 1.3,
	fuseTime = nil,
	maxLifetime = 7,
	bounceCount = 3,
	restitution = 0.8,
	penetrationDepth = 0,
	explosionRadius = 10,
	terrainRadius = 6,
	maxDamage = 30,
	minDamage = 10,
	knockbackStrength = 38,
	projectileCount = 1,
	spreadAngle = 0,
	canDamageOwner = true,
	cameraMode = "Wide",
})

local ALL: { ProjectileDefinition } = {
	ACORN_CANNON,
	FIZZY_BOMB,
	MOLE_DRILL,
	BUBBLE_BOUNCER,
}

local catalogueValid, catalogueReason = Weapons.validateCatalogue(ALL)
assert(catalogueValid, catalogueReason or "invalid weapon catalogue")

local BY_ID: { [string]: ProjectileDefinition } = {}
for _, definition in ALL do
	BY_ID[definition.id] = definition
end

Weapons.ACORN_CANNON = ACORN_CANNON
Weapons.FIZZY_BOMB = FIZZY_BOMB
Weapons.MOLE_DRILL = MOLE_DRILL
Weapons.BUBBLE_BOUNCER = BUBBLE_BOUNCER
Weapons.All = table.freeze(ALL)
Weapons.ById = table.freeze(BY_ID)

function Weapons.get(id: string): ProjectileDefinition?
	return BY_ID[id]
end

function Weapons.isValidPower(power: number): boolean
	return isFinite(power) and power >= 0 and power <= 1
end

-- The normalized power must already have passed the server's request validation;
-- this function intentionally rejects rather than clamps invalid values.
function Weapons.resolveSpeed(definition: ProjectileDefinition, power: number): number
	assert(Weapons.isValidPower(power), "power must be in [0, 1]")
	return definition.initialSpeedMin
		+ (definition.initialSpeedMax - definition.initialSpeedMin) * power
end

return table.freeze(Weapons)
