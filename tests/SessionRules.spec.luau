--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnvironmentConfig = require(ReplicatedStorage.Shared.Config.EnvironmentConfig)
local SessionRules = require(ReplicatedStorage.Shared.Progression.SessionRules)

local function lease(ownerId: string, acquiredAt: number, expiresAt: number): SessionRules.Lease
	return {
		ownerId = ownerId,
		acquiredAt = acquiredAt,
		expiresAt = expiresAt,
	}
end

return function()
	local testEnvironment: any = getfenv()
	local describe = testEnvironment.describe
	local it = testEnvironment.it
	local expect = testEnvironment.expect

	describe("SessionRules validation", function()
		it("accepts a strict finite lease", function()
			local valid, reason = SessionRules.validateLease(lease("job-a:session-a", 100, 220))

			expect(valid).to.equal(true)
			expect(reason).to.equal(nil)
		end)

		it("rejects malformed owner, time, interval, and extra fields", function()
			local badOwner = lease("job a", 100, 220)
			local badTime = lease("job-a", -1, 220)
			local badInterval = lease("job-a", 100, 100)
			local extra: any = lease("job-a", 100, 220)
			extra.force = true

			expect(SessionRules.validateLease(badOwner)).to.equal(false)
			expect(SessionRules.validateLease(badTime)).to.equal(false)
			expect(SessionRules.validateLease(badInterval)).to.equal(false)
			expect(SessionRules.validateLease(extra)).to.equal(false)
		end)
	end)

	describe("SessionRules ownership and expiry", function()
		it("treats expiry as inclusive and reports bounded remaining time", function()
			local current = lease("job-a", 100, 220)

			expect(SessionRules.isExpired(current, 219)).to.equal(false)
			expect(SessionRules.isExpired(current, 220)).to.equal(true)
			expect(SessionRules.remainingSeconds(current, 219)).to.equal(1)
			expect(SessionRules.remainingSeconds(current, 300)).to.equal(0)
		end)

		it("separates identity ownership from active ownership", function()
			local current = lease("job-a", 100, 220)

			expect(SessionRules.isOwnedBy(current, "job-a")).to.equal(true)
			expect(SessionRules.isActiveOwner(current, "job-a", 219)).to.equal(true)
			expect(SessionRules.isActiveOwner(current, "job-a", 220)).to.equal(false)
			expect(SessionRules.isActiveOwner(current, "job-b", 150)).to.equal(false)
		end)
	end)

	describe("SessionRules acquisition", function()
		it("acquires an absent lease using the configured duration", function()
			local result, reason = SessionRules.acquire(nil, "job-a:session-a", 100)
			assert(result ~= nil, reason)

			expect(result.status).to.equal("Acquired")
			expect(result.lease.ownerId).to.equal("job-a:session-a")
			expect(result.lease.acquiredAt).to.equal(100)
			expect(result.lease.expiresAt).to.equal(100 + EnvironmentConfig.leaseDurationSeconds)
		end)

		it("renews the same owner without changing original acquisition time", function()
			local original = lease("job-a", 100, 220)
			local result, reason = SessionRules.acquire(original, "job-a", 200, 60)
			assert(result ~= nil, reason)

			expect(result.status).to.equal("Renewed")
			expect(result.lease.acquiredAt).to.equal(100)
			expect(result.lease.expiresAt).to.equal(260)
			expect(original.expiresAt).to.equal(220)
		end)

		it("allows long-lived renewals but rejects implausible remaining leases", function()
			local longLived = lease("job-a", 100, 1_120)
			local renewed, renewReason = SessionRules.acquire(longLived, "job-a", 1_000, 120)
			assert(renewed ~= nil, renewReason)

			local invalid, invalidReason =
				SessionRules.acquire(lease("job-a", 100, 701), "job-b", 100)
			expect(renewed.status).to.equal("Renewed")
			expect(renewed.lease.acquiredAt).to.equal(100)
			expect(renewed.lease.expiresAt).to.equal(1_120)
			expect(invalid).to.equal(nil)
			expect(invalidReason).to.equal("lease_remaining_too_long")
		end)

		it("refuses a different owner while the lease is active", function()
			local original = lease("job-a", 100, 220)
			local result, reason = SessionRules.acquire(original, "job-b", 150, 60)
			assert(result ~= nil, reason)

			expect(result.status).to.equal("Locked")
			expect(result.lease.ownerId).to.equal("job-a")
			result.lease.expiresAt = 999
			expect(original.expiresAt).to.equal(220)
		end)

		it("takes over an expired foreign lease exactly at expiry", function()
			local result, reason = SessionRules.acquire(lease("job-a", 100, 220), "job-b", 220, 60)
			assert(result ~= nil, reason)

			expect(result.status).to.equal("Acquired")
			expect(result.lease.ownerId).to.equal("job-b")
			expect(result.lease.acquiredAt).to.equal(220)
			expect(result.lease.expiresAt).to.equal(280)
		end)

		it("never overwrites a malformed current lease", function()
			local result, reason = SessionRules.acquire({
				ownerId = "job-a",
				acquiredAt = 100,
				expiresAt = 50,
			}, "job-b", 200)

			expect(result).to.equal(nil)
			expect(reason).to.equal("invalid_lease_interval")
		end)

		it("rejects invalid owner, clock, duration, and non-monotonic renewal", function()
			local badOwner = SessionRules.acquire(nil, "job a", 100)
			local badClock = SessionRules.acquire(nil, "job-a", -1)
			local badDuration = SessionRules.acquire(nil, "job-a", 100, 0)
			local backward, backwardReason =
				SessionRules.acquire(lease("job-a", 100, 220), "job-a", 99)

			expect(badOwner).to.equal(nil)
			expect(badClock).to.equal(nil)
			expect(badDuration).to.equal(nil)
			expect(backward).to.equal(nil)
			expect(backwardReason).to.equal("time_before_acquire")
		end)
	end)
end
