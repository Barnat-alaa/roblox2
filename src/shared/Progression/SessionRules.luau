--!strict

local EnvironmentConfig = require(script.Parent.Parent.Config.EnvironmentConfig)

local SessionRules = {}

export type Lease = {
	ownerId: string,
	acquiredAt: number,
	expiresAt: number,
}

export type AcquireStatus = "Acquired" | "Renewed" | "Locked"
export type AcquireResult = {
	status: AcquireStatus,
	lease: Lease,
}

local MAX_SAFE_INTEGER = 9_007_199_254_740_991
local MAX_OWNER_ID_LENGTH = 160
local MAX_LEASE_SECONDS = 600
local LEASE_FIELDS = table.freeze({
	ownerId = true,
	acquiredAt = true,
	expiresAt = true,
})

SessionRules.DEFAULT_LEASE_SECONDS = EnvironmentConfig.leaseDurationSeconds
SessionRules.MAX_LEASE_SECONDS = MAX_LEASE_SECONDS
SessionRules.MAX_OWNER_ID_LENGTH = MAX_OWNER_ID_LENGTH

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isIntegerInRange(value: unknown, minimum: number, maximum: number): boolean
	if typeof(value) ~= "number" then
		return false
	end
	local numberValue = value :: number
	return isFinite(numberValue)
		and numberValue == math.floor(numberValue)
		and numberValue >= minimum
		and numberValue <= maximum
end

local function cloneLease(lease: Lease): Lease
	return {
		ownerId = lease.ownerId,
		acquiredAt = lease.acquiredAt,
		expiresAt = lease.expiresAt,
	}
end

function SessionRules.validateOwnerId(ownerId: unknown): (boolean, string?)
	if
		type(ownerId) ~= "string"
		or #ownerId < 1
		or #ownerId > MAX_OWNER_ID_LENGTH
		or ownerId:find("[%c%s]") ~= nil
	then
		return false, "invalid_owner_id"
	end
	return true, nil
end

function SessionRules.validateLease(value: unknown): (boolean, string?)
	if typeof(value) ~= "table" then
		return false, "invalid_lease"
	end
	local lease = value :: { [any]: any }
	for field in lease do
		if typeof(field) ~= "string" or not LEASE_FIELDS[field :: string] then
			return false, "invalid_lease_fields"
		end
	end
	local ownerValid, ownerReason = SessionRules.validateOwnerId(lease.ownerId)
	if not ownerValid then
		return false, ownerReason
	end
	if not isIntegerInRange(lease.acquiredAt, 0, MAX_SAFE_INTEGER) then
		return false, "invalid_acquired_at"
	end
	if not isIntegerInRange(lease.expiresAt, 0, MAX_SAFE_INTEGER) then
		return false, "invalid_expires_at"
	end
	if lease.expiresAt <= lease.acquiredAt then
		return false, "invalid_lease_interval"
	end
	return true, nil
end

function SessionRules.isExpired(lease: Lease, now: number): boolean
	assert(isIntegerInRange(now, 0, MAX_SAFE_INTEGER), "now must be a non-negative integer")
	return now >= lease.expiresAt
end

function SessionRules.isOwnedBy(lease: Lease, ownerId: string): boolean
	return lease.ownerId == ownerId
end

function SessionRules.isActiveOwner(lease: Lease, ownerId: string, now: number): boolean
	return SessionRules.isOwnedBy(lease, ownerId) and not SessionRules.isExpired(lease, now)
end

function SessionRules.remainingSeconds(lease: Lease, now: number): number
	assert(isIntegerInRange(now, 0, MAX_SAFE_INTEGER), "now must be a non-negative integer")
	return math.max(0, lease.expiresAt - now)
end

function SessionRules.acquire(
	currentLease: unknown,
	ownerId: string,
	now: number,
	leaseSeconds: number?
): (AcquireResult?, string?)
	local ownerValid, ownerReason = SessionRules.validateOwnerId(ownerId)
	if not ownerValid then
		return nil, ownerReason
	end
	if not isIntegerInRange(now, 0, MAX_SAFE_INTEGER) then
		return nil, "invalid_now"
	end
	local duration = leaseSeconds or EnvironmentConfig.leaseDurationSeconds
	if not isIntegerInRange(duration, 1, MAX_LEASE_SECONDS) then
		return nil, "invalid_lease_duration"
	end
	if now > MAX_SAFE_INTEGER - duration then
		return nil, "lease_time_overflow"
	end

	if currentLease == nil then
		return {
			status = "Acquired",
			lease = {
				ownerId = ownerId,
				acquiredAt = now,
				expiresAt = now + duration,
			},
		},
			nil
	end

	local leaseValid, leaseReason = SessionRules.validateLease(currentLease)
	if not leaseValid then
		return nil, leaseReason
	end
	local existing: Lease = currentLease :: any
	if existing.expiresAt - now > MAX_LEASE_SECONDS then
		return nil, "lease_remaining_too_long"
	end
	if existing.ownerId == ownerId then
		if now < existing.acquiredAt then
			return nil, "time_before_acquire"
		end
		return {
			status = "Renewed",
			lease = {
				ownerId = ownerId,
				acquiredAt = existing.acquiredAt,
				expiresAt = now + duration,
			},
		},
			nil
	end
	if SessionRules.isExpired(existing, now) then
		return {
			status = "Acquired",
			lease = {
				ownerId = ownerId,
				acquiredAt = now,
				expiresAt = now + duration,
			},
		},
			nil
	end
	return {
		status = "Locked",
		lease = cloneLease(existing),
	}, nil
end

return table.freeze(SessionRules)
