--!strict

-- Pure radial damage and knockback calculations. This module returns values only;
-- the authoritative server remains responsible for line-of-sight checks, friendly
-- fire rules, duplicate-hit suppression, health mutation, and velocity caps.

local Damage = {}

export type RadialProfile = {
	radius: number,
	maxDamage: number,
	minDamage: number,
}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function Damage.validateProfile(profile: RadialProfile): (boolean, string?)
	if not isFinite(profile.radius) or profile.radius <= 0 then
		return false, "radius must be finite and positive"
	end
	if not isFinite(profile.maxDamage) or profile.maxDamage < 0 then
		return false, "maxDamage must be finite and non-negative"
	end
	if not isFinite(profile.minDamage) or profile.minDamage < 0 then
		return false, "minDamage must be finite and non-negative"
	end
	if profile.minDamage > profile.maxDamage then
		return false, "minDamage must not exceed maxDamage"
	end

	return true, nil
end

local function assertValidProfile(profile: RadialProfile)
	local valid, reason = Damage.validateProfile(profile)
	assert(valid, reason or "invalid radial damage profile")
end

-- The centre receives maxDamage. A target exactly on the radius receives
-- minDamage; a target beyond it receives zero. Damage is intentionally left as a
-- real number so the server can choose one consistent rounding policy at the
-- health boundary.
function Damage.atDistance(profile: RadialProfile, distance: number): number
	assertValidProfile(profile)
	assert(isFinite(distance) and distance >= 0, "distance must be finite and non-negative")

	if distance > profile.radius then
		return 0
	end

	local normalizedDistance = distance / profile.radius
	return profile.maxDamage + (profile.minDamage - profile.maxDamage) * normalizedDistance
end

function Damage.atPosition(profile: RadialProfile, origin: Vector3, target: Vector3): number
	return Damage.atDistance(profile, (target - origin).Magnitude)
end

-- Knockback tapers to zero at the blast edge. It is separate from damage falloff
-- because minimum edge damage should not imply a non-zero launch impulse.
function Damage.knockbackMagnitude(distance: number, radius: number, strength: number): number
	assert(isFinite(distance) and distance >= 0, "distance must be finite and non-negative")
	assert(isFinite(radius) and radius > 0, "radius must be finite and positive")
	assert(isFinite(strength) and strength >= 0, "strength must be finite and non-negative")

	if distance >= radius then
		return 0
	end

	return strength * (1 - distance / radius)
end

-- At the exact blast centre there is no unambiguous radial direction, so this
-- returns zero and lets the authoritative caller supply a game-specific fallback.
function Damage.knockbackVector(
	origin: Vector3,
	target: Vector3,
	radius: number,
	strength: number
): Vector3
	local offset = target - origin
	local distance = offset.Magnitude
	local magnitude = Damage.knockbackMagnitude(distance, radius, strength)

	if distance == 0 or magnitude == 0 then
		return Vector3.zero
	end

	return offset.Unit * magnitude
end

return table.freeze(Damage)
