--!strict

-- Deterministic, collision-free bot aiming. The server remains responsible for
-- choosing a real target, raycast collision, authoritative firing, and turn
-- timing. This module only returns legal inputs for the shared projectile system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local Ballistics = require(ReplicatedStorage.Shared.Simulation.Ballistics)
local Wind = require(ReplicatedStorage.Shared.Simulation.Wind)

type ProjectileDefinition = Weapons.ProjectileDefinition

export type Difficulty = "Easy" | "Normal" | "Hard"

export type Request = {
	origin: Vector3,
	target: Vector3,
	wind: number,
	seed: number,
	turnIndex: number,
	difficulty: Difficulty,
	weaponIds: { string }?,
}

export type Solution = {
	weaponId: string,
	angle: number,
	power: number,
	flightTime: number,
	predictedImpact: Vector3,
	missDistance: number,
	appliedAngleError: number,
	appliedPowerError: number,
	evaluatedCandidates: number,
}

export type ErrorLimits = {
	angle: number,
	power: number,
}

local BotAim = {}

local MAX_WEAPON_CANDIDATES = 4
local PRIMARY_ANGLE_SAMPLE_COUNT = 86
local POWER_SAMPLE_COUNT = 25
local FALLBACK_TIME_SAMPLES = 32
local MINIMUM_FLIGHT_TIME = 0.05
local MAX_WORLD_COORDINATE = 1_000_000
local MAX_ABSOLUTE_WIND = 64
local SIGNED_INT32_MIN = -2_147_483_648
local SIGNED_INT32_MAX = 2_147_483_647
local QUADRATIC_EPSILON = 1e-9
local ANGLE_ERROR_SALT = 0xA341316C
local POWER_ERROR_SALT = 0xC8013EA4

local DEFAULT_WEAPON_IDS: { string } = table.freeze({
	"acorn_cannon",
	"mole_drill",
})

local ERROR_LIMITS: { [Difficulty]: ErrorLimits } = table.freeze({
	Easy = table.freeze({
		angle = 5,
		power = 0.1,
	}),
	Normal = table.freeze({
		angle = 1.25,
		power = 0.025,
	}),
	Hard = table.freeze({
		angle = 0.5,
		power = 0.01,
	}),
})

local function buildAngleSamples(): { number }
	local samples = table.create(PRIMARY_ANGLE_SAMPLE_COUNT + 1)
	local span = GameConfig.maximumAimDegrees - GameConfig.minimumAimDegrees
	local includesVertical = false
	for sampleIndex = 0, PRIMARY_ANGLE_SAMPLE_COUNT - 1 do
		local angle = GameConfig.minimumAimDegrees
			+ span * sampleIndex / (PRIMARY_ANGLE_SAMPLE_COUNT - 1)
		table.insert(samples, angle)
		includesVertical = includesVertical or math.abs(angle - 90) <= QUADRATIC_EPSILON
	end
	if
		not includesVertical
		and GameConfig.minimumAimDegrees <= 90
		and GameConfig.maximumAimDegrees >= 90
	then
		table.insert(samples, 90)
		table.sort(samples)
	end
	return table.freeze(samples)
end

local ANGLE_SAMPLES = buildAngleSamples()
local MAX_CANDIDATE_EVALUATIONS = #ANGLE_SAMPLES * POWER_SAMPLE_COUNT * MAX_WEAPON_CANDIDATES

BotAim.MAX_WEAPON_CANDIDATES = MAX_WEAPON_CANDIDATES
BotAim.MAX_CANDIDATE_EVALUATIONS = MAX_CANDIDATE_EVALUATIONS
BotAim.FALLBACK_TIME_SAMPLES = FALLBACK_TIME_SAMPLES
BotAim.MAX_ABSOLUTE_WIND = MAX_ABSOLUTE_WIND
BotAim.ERROR_LIMITS = ERROR_LIMITS

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isInt32(value: number): boolean
	return isFinite(value)
		and value == math.floor(value)
		and value >= SIGNED_INT32_MIN
		and value <= SIGNED_INT32_MAX
end

local function validateWorldPosition(value: Vector3, name: string)
	assert(typeof(value) == "Vector3", `{name} must be a Vector3`)
	assert(isFinite(value.X) and isFinite(value.Y) and isFinite(value.Z), `{name} must be finite`)
	assert(
		math.abs(value.X) <= MAX_WORLD_COORDINATE
			and math.abs(value.Y) <= MAX_WORLD_COORDINATE
			and math.abs(value.Z) <= MAX_WORLD_COORDINATE,
		`{name} is outside the supported world bounds`
	)
end

local function validateDifficulty(value: Difficulty): ErrorLimits
	local limits = ERROR_LIMITS[value]
	assert(limits ~= nil, "difficulty must be Easy, Normal, or Hard")
	return limits
end

local function collectDefinitions(weaponIds: { string }?): { ProjectileDefinition }
	local source = weaponIds or DEFAULT_WEAPON_IDS
	assert(typeof(source) == "table", "weaponIds must be an array")
	local rawSource = source :: { [any]: any }
	local length = #rawSource
	assert(length >= 1, "weaponIds must not be empty")
	assert(
		length <= MAX_WEAPON_CANDIDATES,
		`weaponIds must contain at most {MAX_WEAPON_CANDIDATES} entries`
	)

	local entryCount = 0
	for rawIndex in rawSource do
		assert(
			type(rawIndex) == "number"
				and rawIndex == math.floor(rawIndex)
				and rawIndex >= 1
				and rawIndex <= length,
			"weaponIds must be a dense array"
		)
		entryCount += 1
	end
	assert(entryCount == length, "weaponIds must be a dense array")

	local seen: { [string]: boolean } = {}
	local definitions = table.create(length) :: { ProjectileDefinition }
	for index = 1, length do
		local weaponId = rawSource[index]
		assert(typeof(weaponId) == "string", "weaponIds entries must be strings")
		assert(not seen[weaponId], "weaponIds must not contain duplicates")
		seen[weaponId] = true
		local definition = Weapons.get(weaponId)
		assert(definition ~= nil, `unknown weapon id: {weaponId}`)
		table.insert(definitions, definition)
	end
	return definitions
end

local function xorshift32(value: number): number
	local state = bit32.bxor(value, bit32.lshift(value, 13))
	state = bit32.bxor(state, bit32.rshift(state, 17))
	return bit32.bxor(state, bit32.lshift(state, 5))
end

local function mixedBits(seed: number, turnIndex: number, salt: number): number
	local turnBits = bit32.band(turnIndex, 0xFFFFFFFF)
	local rotatedTurn = bit32.bor(bit32.lshift(turnBits, 16), bit32.rshift(turnBits, 16))
	local state = bit32.bxor(bit32.band(seed, 0xFFFFFFFF), rotatedTurn, salt)
	state = xorshift32(state)
	state = xorshift32(state)
	return xorshift32(state)
end

-- Error never has zero magnitude, but its sign and magnitude are deterministic.
local function signedErrorCoefficient(bits: number): number
	local sign = if bit32.band(bits, 1) == 0 then -1 else 1
	local magnitudeBits = bit32.band(bit32.rshift(bits, 1), 0xFFFF)
	local magnitude = 0.35 + 0.65 * magnitudeBits / 0xFFFF
	return sign * magnitude
end

local function axisRoots(
	initial: number,
	velocity: number,
	acceleration: number,
	target: number
): (number?, number?)
	local offset = initial - target
	if math.abs(acceleration) <= QUADRATIC_EPSILON then
		if math.abs(velocity) <= QUADRATIC_EPSILON then
			if math.abs(offset) <= QUADRATIC_EPSILON then
				return MINIMUM_FLIGHT_TIME, nil
			end
			return nil, nil
		end
		return -offset / velocity, nil
	end

	local discriminant = velocity * velocity - 2 * acceleration * offset
	if discriminant < -QUADRATIC_EPSILON then
		return nil, nil
	end
	discriminant = math.max(0, discriminant)
	local squareRoot = math.sqrt(discriminant)
	local first = (-velocity - squareRoot) / acceleration
	local second = (-velocity + squareRoot) / acceleration
	if first > second then
		first, second = second, first
	end
	if math.abs(first - second) <= QUADRATIC_EPSILON then
		return first, nil
	end
	return first, second
end

local function detonationHorizon(definition: ProjectileDefinition): number
	if definition.fuseTime then
		return math.min(definition.maxLifetime, definition.fuseTime)
	end
	return definition.maxLifetime
end

local function accelerationFor(definition: ProjectileDefinition, windStrength: number): Vector3
	return Ballistics.acceleration({
		gravity = Vector3.new(0, -GameConfig.projectileWorldGravity, 0),
		wind = Wind.asAcceleration(windStrength),
		gravityScale = definition.gravityScale,
		windScale = definition.windScale,
	})
end

local function missSquared(position: Vector3, target: Vector3): number
	local offset = position - target
	return offset:Dot(offset)
end

local function validRoot(root: number?, horizon: number): boolean
	return root ~= nil and root >= MINIMUM_FLIGHT_TIME and root <= horizon and isFinite(root)
end

local function rootsForTargetAxis(
	origin: Vector3,
	target: Vector3,
	velocity: Vector3,
	acceleration: Vector3,
	useXAxis: boolean
): (number?, number?)
	if useXAxis then
		return axisRoots(origin.X, velocity.X, acceleration.X, target.X)
	end
	return axisRoots(origin.Y, velocity.Y, acceleration.Y, target.Y)
end

local function predictBestForShot(
	origin: Vector3,
	target: Vector3,
	definition: ProjectileDefinition,
	angle: number,
	power: number,
	windStrength: number,
	useXAxis: boolean
): (number, Vector3, number)
	local speed = Weapons.resolveSpeed(definition, power)
	local velocity = Ballistics.worldLaunchVelocity(angle, speed)
	local acceleration = accelerationFor(definition, windStrength)
	local horizon = detonationHorizon(definition)
	local firstRoot, secondRoot =
		rootsForTargetAxis(origin, target, velocity, acceleration, useXAxis)

	local bestTime: number? = nil
	local bestPosition: Vector3? = nil
	local bestMissSquared = math.huge
	if validRoot(firstRoot, horizon) then
		local time = firstRoot :: number
		local position = Ballistics.positionAt(origin, velocity, acceleration, time)
		bestTime = time
		bestPosition = position
		bestMissSquared = missSquared(position, target)
	end
	if validRoot(secondRoot, horizon) then
		local time = secondRoot :: number
		local position = Ballistics.positionAt(origin, velocity, acceleration, time)
		local candidateMissSquared = missSquared(position, target)
		if candidateMissSquared < bestMissSquared then
			bestTime = time
			bestPosition = position
			bestMissSquared = candidateMissSquared
		end
	end

	if not bestTime or not bestPosition then
		for sampleIndex = 1, FALLBACK_TIME_SAMPLES do
			local time = horizon * sampleIndex / FALLBACK_TIME_SAMPLES
			local position = Ballistics.positionAt(origin, velocity, acceleration, time)
			local candidateMissSquared = missSquared(position, target)
			if candidateMissSquared < bestMissSquared then
				bestTime = time
				bestPosition = position
				bestMissSquared = candidateMissSquared
			end
		end
	end

	assert(
		bestTime ~= nil and bestPosition ~= nil,
		"a weapon must have a positive prediction horizon"
	)
	return bestTime, bestPosition, math.sqrt(bestMissSquared)
end

local function perturbWithinBounds(
	value: number,
	errorValue: number,
	minimum: number,
	maximum: number
): number
	local perturbed = math.clamp(value + errorValue, minimum, maximum)
	if perturbed == value then
		perturbed = math.clamp(value - errorValue, minimum, maximum)
	end
	return perturbed
end

function BotAim.solve(request: Request): Solution
	assert(typeof(request) == "table", "request must be a table")
	validateWorldPosition(request.origin, "origin")
	validateWorldPosition(request.target, "target")
	assert(isFinite(request.wind), "wind must be finite")
	assert(math.abs(request.wind) <= MAX_ABSOLUTE_WIND, "wind exceeds the supported bound")
	assert(isInt32(request.seed), "seed must be a signed 32-bit integer")
	assert(
		isInt32(request.turnIndex) and request.turnIndex >= 0,
		"turnIndex must be a non-negative signed 32-bit integer"
	)
	local errorLimits = validateDifficulty(request.difficulty)
	local definitions = collectDefinitions(request.weaponIds)

	local displacement = request.target - request.origin
	local useXAxis = math.abs(displacement.X) >= math.abs(displacement.Y)
	local evaluatedCandidates = 0
	local bestDefinition: ProjectileDefinition? = nil
	local bestAngle = 0
	local bestPower = 0
	local bestMissSquared = math.huge

	for _, definition in definitions do
		local acceleration = accelerationFor(definition, request.wind)
		local horizon = detonationHorizon(definition)
		for _, angle in ANGLE_SAMPLES do
			for powerIndex = 0, POWER_SAMPLE_COUNT - 1 do
				evaluatedCandidates += 1
				local power = GameConfig.minimumPower
					+ (GameConfig.maximumPower - GameConfig.minimumPower)
						* powerIndex
						/ (POWER_SAMPLE_COUNT - 1)
				local speed = Weapons.resolveSpeed(definition, power)
				local velocity = Ballistics.worldLaunchVelocity(angle, speed)
				local firstRoot, secondRoot = rootsForTargetAxis(
					request.origin,
					request.target,
					velocity,
					acceleration,
					useXAxis
				)

				if validRoot(firstRoot, horizon) then
					local position = Ballistics.positionAt(
						request.origin,
						velocity,
						acceleration,
						firstRoot :: number
					)
					local candidateMissSquared = missSquared(position, request.target)
					if candidateMissSquared < bestMissSquared then
						bestDefinition = definition
						bestAngle = angle
						bestPower = power
						bestMissSquared = candidateMissSquared
					end
				end
				if validRoot(secondRoot, horizon) then
					local position = Ballistics.positionAt(
						request.origin,
						velocity,
						acceleration,
						secondRoot :: number
					)
					local candidateMissSquared = missSquared(position, request.target)
					if candidateMissSquared < bestMissSquared then
						bestDefinition = definition
						bestAngle = angle
						bestPower = power
						bestMissSquared = candidateMissSquared
					end
				end
			end
		end
	end

	if not bestDefinition then
		bestDefinition = definitions[1]
		if math.abs(displacement.X) <= QUADRATIC_EPSILON then
			bestAngle = 90
		elseif displacement.X > 0 then
			bestAngle = 45
		else
			bestAngle = 135
		end
		bestAngle =
			math.clamp(bestAngle, GameConfig.minimumAimDegrees, GameConfig.maximumAimDegrees)
		bestPower = (GameConfig.minimumPower + GameConfig.maximumPower) * 0.5
	end
	local selectedDefinition = bestDefinition
	assert(selectedDefinition ~= nil, "a validated weapon list must produce a selection")

	local angleError = signedErrorCoefficient(
		mixedBits(request.seed, request.turnIndex, ANGLE_ERROR_SALT)
	) * errorLimits.angle
	local powerError = signedErrorCoefficient(
		mixedBits(request.seed, request.turnIndex, POWER_ERROR_SALT)
	) * errorLimits.power
	local finalAngle = perturbWithinBounds(
		bestAngle,
		angleError,
		GameConfig.minimumAimDegrees,
		GameConfig.maximumAimDegrees
	)
	local finalPower =
		perturbWithinBounds(bestPower, powerError, GameConfig.minimumPower, GameConfig.maximumPower)
	local flightTime, predictedImpact, missDistance = predictBestForShot(
		request.origin,
		request.target,
		selectedDefinition,
		finalAngle,
		finalPower,
		request.wind,
		useXAxis
	)

	return {
		weaponId = selectedDefinition.id,
		angle = finalAngle,
		power = finalPower,
		flightTime = flightTime,
		predictedImpact = predictedImpact,
		missDistance = missDistance,
		appliedAngleError = finalAngle - bestAngle,
		appliedPowerError = finalPower - bestPower,
		evaluatedCandidates = evaluatedCandidates,
	}
end

return table.freeze(BotAim)
