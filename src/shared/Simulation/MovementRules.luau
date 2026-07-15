--!strict

-- Pure movement-budget and jump-admission rules. Runtime character code owns
-- Humanoids and physics, while this module keeps the security decisions small,
-- deterministic, and directly testable.

local MovementRules = {}

export type Config = {
	minimumX: number,
	maximumX: number,
	movementAllowance: number,
	maxHorizontalSpeed: number,
	stepTolerance: number,
	maxSampleInterval: number,
}

export type State = {
	lastX: number,
	lastSampleAt: number,
	distanceUsed: number,
}

export type CorrectionReason =
	"invalid_sample"
	| "arena_bounds"
	| "horizontal_speed"
	| "movement_budget"

export type Decision = {
	acceptedX: number,
	distanceUsed: number,
	corrected: boolean,
	reason: CorrectionReason?,
}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function MovementRules.validateConfig(config: Config): (boolean, string?)
	if not isFinite(config.minimumX) or not isFinite(config.maximumX) then
		return false, "movement bounds must be finite"
	end
	if config.minimumX >= config.maximumX then
		return false, "minimumX must be below maximumX"
	end
	if not isFinite(config.movementAllowance) or config.movementAllowance < 0 then
		return false, "movementAllowance must be finite and non-negative"
	end
	if not isFinite(config.maxHorizontalSpeed) or config.maxHorizontalSpeed <= 0 then
		return false, "maxHorizontalSpeed must be finite and positive"
	end
	if not isFinite(config.stepTolerance) or config.stepTolerance < 0 then
		return false, "stepTolerance must be finite and non-negative"
	end
	if not isFinite(config.maxSampleInterval) or config.maxSampleInterval <= 0 then
		return false, "maxSampleInterval must be finite and positive"
	end
	return true, nil
end

function MovementRules.createState(initialX: number, now: number): State
	assert(isFinite(initialX), "initialX must be finite")
	assert(isFinite(now), "now must be finite")
	return {
		lastX = initialX,
		lastSampleAt = now,
		distanceUsed = 0,
	}
end

function MovementRules.remainingDistance(state: State, config: Config): number
	return math.max(0, config.movementAllowance - state.distanceUsed)
end

-- External motion is still constrained to arena bounds, but does not consume a
-- player's turn movement allowance. DamageService grants this path briefly for
-- authoritative knockback; ordinary client-driven movement never receives it.
function MovementRules.applyHorizontalSample(
	state: State,
	requestedX: number,
	now: number,
	config: Config,
	allowExternalMotion: boolean
): Decision
	local valid, reason = MovementRules.validateConfig(config)
	assert(valid, reason or "invalid movement config")

	if not isFinite(requestedX) or not isFinite(now) or now < state.lastSampleAt then
		return {
			acceptedX = state.lastX,
			distanceUsed = state.distanceUsed,
			corrected = true,
			reason = "invalid_sample",
		}
	end

	local correctionReason: CorrectionReason? = nil
	local boundedX = math.clamp(requestedX, config.minimumX, config.maximumX)
	if boundedX ~= requestedX then
		correctionReason = "arena_bounds"
	end

	if allowExternalMotion then
		state.lastX = boundedX
		state.lastSampleAt = now
		return {
			acceptedX = boundedX,
			distanceUsed = state.distanceUsed,
			corrected = correctionReason ~= nil,
			reason = correctionReason,
		}
	end

	local elapsed = math.min(now - state.lastSampleAt, config.maxSampleInterval)
	local requestedDelta = boundedX - state.lastX
	local maximumStep = config.maxHorizontalSpeed * elapsed + config.stepTolerance
	local acceptedDelta = math.clamp(requestedDelta, -maximumStep, maximumStep)
	if acceptedDelta ~= requestedDelta then
		correctionReason = "horizontal_speed"
	end

	local remaining = MovementRules.remainingDistance(state, config)
	if math.abs(acceptedDelta) > remaining then
		acceptedDelta = math.sign(acceptedDelta) * remaining
		correctionReason = "movement_budget"
	end

	local acceptedX = state.lastX + acceptedDelta
	state.lastX = acceptedX
	state.lastSampleAt = now
	state.distanceUsed += math.abs(acceptedDelta)

	return {
		acceptedX = acceptedX,
		distanceUsed = state.distanceUsed,
		corrected = correctionReason ~= nil,
		reason = correctionReason,
	}
end

function MovementRules.canStartJump(
	lastAcceptedJumpAt: number?,
	now: number,
	groundedRecently: boolean,
	minimumInterval: number
): (boolean, string?)
	if not isFinite(now) or not isFinite(minimumInterval) or minimumInterval < 0 then
		return false, "invalid_jump_sample"
	end
	if not groundedRecently then
		return false, "not_grounded"
	end
	if lastAcceptedJumpAt ~= nil then
		if not isFinite(lastAcceptedJumpAt) or now < lastAcceptedJumpAt then
			return false, "invalid_jump_sample"
		end
		if now - lastAcceptedJumpAt < minimumInterval then
			return false, "jump_frequency"
		end
	end
	return true, nil
end

return table.freeze(MovementRules)
