--!strict

-- Pure constant-acceleration projectile math shared by the server simulation and
-- client trajectory preview. Collision and Roblox instance mutation deliberately
-- live outside this module.

local Ballistics = {}

export type State = {
	position: Vector3,
	velocity: Vector3,
	elapsed: number,
}

export type Forces = {
	gravity: Vector3,
	wind: Vector3,
	gravityScale: number,
	windScale: number,
}

-- Server simulations should subdivide longer frame delays instead of integrating
-- one large interval. At 1/15 second, swept raycasts remain reasonably short even
-- if a server has a temporary frame-rate dip.
local MAX_STEP = 1 / 15
local MAX_PREVIEW_STEPS = 600

Ballistics.MAX_STEP = MAX_STEP
Ballistics.MAX_PREVIEW_STEPS = MAX_PREVIEW_STEPS

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function assertFinite(value: number, name: string)
	assert(isFinite(value), `{name} must be finite`)
end

local function assertFiniteVector(value: Vector3, name: string)
	assertFinite(value.X, `{name}.X`)
	assertFinite(value.Y, `{name}.Y`)
	assertFinite(value.Z, `{name}.Z`)
end

local function assertElapsed(elapsed: number)
	assertFinite(elapsed, "elapsed")
	assert(elapsed >= 0, "elapsed must be non-negative")
end

function Ballistics.acceleration(forces: Forces): Vector3
	assertFiniteVector(forces.gravity, "forces.gravity")
	assertFiniteVector(forces.wind, "forces.wind")
	assertFinite(forces.gravityScale, "forces.gravityScale")
	assertFinite(forces.windScale, "forces.windScale")
	assert(forces.gravityScale >= 0, "forces.gravityScale must be non-negative")
	assert(forces.windScale >= 0, "forces.windScale must be non-negative")

	return forces.gravity * forces.gravityScale + forces.wind * forces.windScale
end

function Ballistics.createState(position: Vector3, velocity: Vector3): State
	assertFiniteVector(position, "position")
	assertFiniteVector(velocity, "velocity")

	return {
		position = position,
		velocity = velocity,
		elapsed = 0,
	}
end

-- World-angle convention used by FireRequest: +X is 0 degrees, +Y is 90, and
-- -X is 180. Game-level validation can further narrow this to the configured
-- aiming range (currently 5..175 degrees).
function Ballistics.worldLaunchVelocity(angleDegrees: number, speed: number): Vector3
	assertFinite(angleDegrees, "angleDegrees")
	assertFinite(speed, "speed")
	assert(angleDegrees >= 0 and angleDegrees <= 180, "angleDegrees must be in [0, 180]")
	assert(speed >= 0, "speed must be non-negative")

	local radians = math.rad(angleDegrees)
	return Vector3.new(math.cos(radians) * speed, math.sin(radians) * speed, 0)
end

-- Angle is measured in degrees above the horizontal combat plane. Facing must be
-- exactly -1 (left) or 1 (right), which avoids accepting ambiguous client input.
function Ballistics.launchVelocity(angleDegrees: number, speed: number, facing: number): Vector3
	assertFinite(angleDegrees, "angleDegrees")
	assertFinite(speed, "speed")
	assert(angleDegrees >= 0 and angleDegrees <= 90, "angleDegrees must be in [0, 90]")
	assert(speed >= 0, "speed must be non-negative")
	assert(facing == -1 or facing == 1, "facing must be -1 or 1")

	local worldAngle = if facing == 1 then angleDegrees else 180 - angleDegrees
	return Ballistics.worldLaunchVelocity(worldAngle, speed)
end

function Ballistics.positionAt(
	initialPosition: Vector3,
	initialVelocity: Vector3,
	acceleration: Vector3,
	elapsed: number
): Vector3
	assertFiniteVector(initialPosition, "initialPosition")
	assertFiniteVector(initialVelocity, "initialVelocity")
	assertFiniteVector(acceleration, "acceleration")
	assertElapsed(elapsed)

	return initialPosition + initialVelocity * elapsed + acceleration * (0.5 * elapsed * elapsed)
end

function Ballistics.velocityAt(
	initialVelocity: Vector3,
	acceleration: Vector3,
	elapsed: number
): Vector3
	assertFiniteVector(initialVelocity, "initialVelocity")
	assertFiniteVector(acceleration, "acceleration")
	assertElapsed(elapsed)

	return initialVelocity + acceleration * elapsed
end

-- Uses the closed-form constant-acceleration update, rather than Euler position
-- integration, so a sequence of fixed steps agrees with positionAt (within normal
-- floating-point tolerance). The input state is never mutated.
function Ballistics.step(state: State, acceleration: Vector3, deltaTime: number): State
	assertFiniteVector(state.position, "state.position")
	assertFiniteVector(state.velocity, "state.velocity")
	assertElapsed(state.elapsed)
	assertFiniteVector(acceleration, "acceleration")
	assertFinite(deltaTime, "deltaTime")
	assert(deltaTime > 0, "deltaTime must be positive")
	assert(deltaTime <= MAX_STEP, `deltaTime must not exceed {MAX_STEP}`)

	return {
		position = Ballistics.positionAt(state.position, state.velocity, acceleration, deltaTime),
		velocity = Ballistics.velocityAt(state.velocity, acceleration, deltaTime),
		elapsed = state.elapsed + deltaTime,
	}
end

-- Returns the initial point followed by one point per step. This is bounded to
-- prevent an untrusted preview request from allocating an arbitrarily large table.
function Ballistics.simulatePreview(
	initialState: State,
	acceleration: Vector3,
	stepSize: number,
	stepCount: number
): { Vector3 }
	assertFiniteVector(initialState.position, "initialState.position")
	assertFiniteVector(initialState.velocity, "initialState.velocity")
	assertElapsed(initialState.elapsed)
	assertFiniteVector(acceleration, "acceleration")
	assertFinite(stepSize, "stepSize")
	assert(stepSize > 0 and stepSize <= MAX_STEP, `stepSize must be in (0, {MAX_STEP}]`)
	assertFinite(stepCount, "stepCount")
	assert(stepCount == math.floor(stepCount), "stepCount must be an integer")
	assert(
		stepCount >= 0 and stepCount <= MAX_PREVIEW_STEPS,
		`stepCount must be in [0, {MAX_PREVIEW_STEPS}]`
	)

	local points = table.create(stepCount + 1)
	local state = initialState
	points[1] = state.position

	for index = 1, stepCount do
		state = Ballistics.step(state, acceleration, stepSize)
		points[index + 1] = state.position
	end

	return points
end

return table.freeze(Ballistics)
