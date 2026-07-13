--!strict

-- Deterministic round wind. The server chooses the match seed and round index,
-- then replicates the resulting signed horizontal acceleration. Clients can use
-- the same inputs for prediction, but never choose authoritative wind.

local Wind = {}

export type Config = {
	minimum: number,
	maximum: number,
	deadZone: number,
	quantum: number,
}

export type Direction = "Left" | "Calm" | "Right"

local UINT32_MAX_PLUS_ONE = 4_294_967_296
local SIGNED_INT32_MIN = -2_147_483_648
local SIGNED_INT32_MAX = 2_147_483_647

local DEFAULT_CONFIG: Config = table.freeze({
	minimum = -8,
	maximum = 8,
	deadZone = 0.75,
	quantum = 0.25,
})

Wind.DEFAULT_CONFIG = DEFAULT_CONFIG

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isInt32(value: number): boolean
	return isFinite(value)
		and value == math.floor(value)
		and value >= SIGNED_INT32_MIN
		and value <= SIGNED_INT32_MAX
end

function Wind.validateConfig(config: Config): (boolean, string?)
	if not isFinite(config.minimum) or not isFinite(config.maximum) then
		return false, "minimum and maximum must be finite"
	end
	if config.minimum >= config.maximum then
		return false, "minimum must be less than maximum"
	end
	if config.minimum > 0 or config.maximum < 0 then
		return false, "wind range must contain zero"
	end
	if not isFinite(config.deadZone) or config.deadZone < 0 then
		return false, "deadZone must be finite and non-negative"
	end
	if config.deadZone > math.max(math.abs(config.minimum), math.abs(config.maximum)) then
		return false, "deadZone must fit inside the wind range"
	end
	if not isFinite(config.quantum) or config.quantum < 0 then
		return false, "quantum must be finite and non-negative"
	end
	if config.quantum > config.maximum - config.minimum then
		return false, "quantum must not exceed the wind range"
	end

	return true, nil
end

local function xorshift32(value: number): number
	local state = bit32.bxor(value, bit32.lshift(value, 13))
	state = bit32.bxor(state, bit32.rshift(state, 17))
	state = bit32.bxor(state, bit32.lshift(state, 5))
	return state
end

local function mix(seed: number, roundIndex: number): number
	-- Rotating the round bits before the xor keeps adjacent rounds from feeding the
	-- xorshift with adjacent states. All operations are explicitly 32-bit.
	local roundBits = bit32.band(roundIndex, 0xFFFFFFFF)
	local rotatedRoundBits = bit32.bor(bit32.lshift(roundBits, 16), bit32.rshift(roundBits, 16))
	local state = bit32.bxor(bit32.band(seed, 0xFFFFFFFF), rotatedRoundBits, 0x9E3779B9)

	state = xorshift32(state)
	state = xorshift32(state)
	return xorshift32(state)
end

local function roundToQuantum(value: number, quantum: number): number
	if quantum == 0 then
		return value
	end

	local scaled = value / quantum
	local rounded: number
	if scaled >= 0 then
		rounded = math.floor(scaled + 0.5)
	else
		rounded = math.ceil(scaled - 0.5)
	end

	return rounded * quantum
end

-- roundIndex is zero-based and should advance once per round, not once per frame.
function Wind.forRound(seed: number, roundIndex: number, configOverride: Config?): number
	assert(isInt32(seed), "seed must be a signed 32-bit integer")
	assert(
		isInt32(roundIndex) and roundIndex >= 0,
		"roundIndex must be a non-negative signed 32-bit integer"
	)

	local config = configOverride or DEFAULT_CONFIG
	local valid, reason = Wind.validateConfig(config)
	assert(valid, reason or "invalid wind config")

	local randomBits = mix(seed, roundIndex)
	local unit = (randomBits + 0.5) / UINT32_MAX_PLUS_ONE
	local value = config.minimum + (config.maximum - config.minimum) * unit
	value = math.clamp(roundToQuantum(value, config.quantum), config.minimum, config.maximum)

	if math.abs(value) < config.deadZone then
		return 0
	end

	return value
end

function Wind.asAcceleration(strength: number): Vector3
	assert(isFinite(strength), "strength must be finite")
	return Vector3.new(strength, 0, 0)
end

function Wind.direction(strength: number, calmThreshold: number?): Direction
	assert(isFinite(strength), "strength must be finite")
	local threshold = calmThreshold or 0
	assert(isFinite(threshold) and threshold >= 0, "calmThreshold must be finite and non-negative")

	if math.abs(strength) <= threshold then
		return "Calm"
	elseif strength < 0 then
		return "Left"
	else
		return "Right"
	end
end

function Wind.normalizedStrength(strength: number, configOverride: Config?): number
	assert(isFinite(strength), "strength must be finite")
	local config = configOverride or DEFAULT_CONFIG
	local valid, reason = Wind.validateConfig(config)
	assert(valid, reason or "invalid wind config")

	local maximumMagnitude = math.max(math.abs(config.minimum), math.abs(config.maximum))
	return math.clamp(math.abs(strength) / maximumMagnitude, 0, 1)
end

return table.freeze(Wind)
