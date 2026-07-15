--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MovementRules = require(
	ReplicatedStorage:WaitForChild("Shared")
		:WaitForChild("Simulation")
		:WaitForChild("MovementRules") :: ModuleScript
)

local CONFIG: MovementRules.Config = table.freeze({
	minimumX = -87,
	maximumX = 87,
	movementAllowance = 22,
	maxHorizontalSpeed = 20,
	stepTolerance = 0.1,
	maxSampleInterval = 0.25,
})

return function()
	local testEnvironment: any = getfenv()
	local describe = testEnvironment.describe
	local it = testEnvironment.it
	local expect = testEnvironment.expect

	describe("MovementRules horizontal authority", function()
		it("accepts legal movement and charges absolute path distance", function()
			local state = MovementRules.createState(0, 10)
			local first = MovementRules.applyHorizontalSample(state, 2, 10.1, CONFIG, false)
			local second = MovementRules.applyHorizontalSample(state, 1, 10.2, CONFIG, false)

			expect(first.corrected).to.equal(false)
			expect(first.acceptedX).to.equal(2)
			expect(second.acceptedX).to.equal(1)
			expect(second.distanceUsed).to.equal(3)
		end)

		it("limits speed before accepting a sample", function()
			local state = MovementRules.createState(0, 1)
			local decision = MovementRules.applyHorizontalSample(state, 10, 1.1, CONFIG, false)

			expect(decision.corrected).to.equal(true)
			expect(decision.reason).to.equal("horizontal_speed")
			expect(math.abs(decision.acceptedX - 2.1) < 1e-9).to.equal(true)
		end)

		it("charges backtracking instead of allowing an endpoint-only exploit", function()
			local budgetConfig: MovementRules.Config = {
				minimumX = CONFIG.minimumX,
				maximumX = CONFIG.maximumX,
				movementAllowance = CONFIG.movementAllowance,
				maxHorizontalSpeed = 100,
				stepTolerance = 0,
				maxSampleInterval = 1,
			}
			local state = MovementRules.createState(0, 0)
			MovementRules.applyHorizontalSample(state, 10, 1, budgetConfig, false)
			MovementRules.applyHorizontalSample(state, 0, 2, budgetConfig, false)
			local decision = MovementRules.applyHorizontalSample(state, 10, 3, budgetConfig, false)

			expect(decision.reason).to.equal("movement_budget")
			expect(decision.acceptedX).to.equal(2)
			expect(decision.distanceUsed).to.equal(22)
			expect(MovementRules.remainingDistance(state, budgetConfig)).to.equal(0)
		end)

		it("constrains movement to arena bounds", function()
			local state = MovementRules.createState(86, 0)
			local decision = MovementRules.applyHorizontalSample(state, 100, 1, CONFIG, false)

			expect(decision.corrected).to.equal(true)
			expect(decision.reason).to.equal("arena_bounds")
			expect(decision.acceptedX).to.equal(87)
		end)

		it("does not charge authoritative knockback against turn movement", function()
			local state = MovementRules.createState(0, 0)
			local knockback = MovementRules.applyHorizontalSample(state, 14, 0.1, CONFIG, true)
			local movement = MovementRules.applyHorizontalSample(state, 16, 0.2, CONFIG, false)

			expect(knockback.acceptedX).to.equal(14)
			expect(knockback.distanceUsed).to.equal(0)
			expect(movement.acceptedX).to.equal(16)
			expect(movement.distanceUsed).to.equal(2)
		end)

		it("rejects non-monotonic sample time without mutating state", function()
			local state = MovementRules.createState(3, 5)
			local decision = MovementRules.applyHorizontalSample(state, 4, 4, CONFIG, false)

			expect(decision.reason).to.equal("invalid_sample")
			expect(state.lastX).to.equal(3)
			expect(state.lastSampleAt).to.equal(5)
			expect(state.distanceUsed).to.equal(0)
		end)
	end)

	describe("MovementRules jump authority", function()
		it("allows a grounded first jump", function()
			local allowed, reason = MovementRules.canStartJump(nil, 10, true, 0.65)
			expect(allowed).to.equal(true)
			expect(reason).to.equal(nil)
		end)

		it("rejects airborne and repeated jumps", function()
			local airborne, airborneReason = MovementRules.canStartJump(nil, 10, false, 0.65)
			local repeated, repeatedReason = MovementRules.canStartJump(10, 10.4, true, 0.65)

			expect(airborne).to.equal(false)
			expect(airborneReason).to.equal("not_grounded")
			expect(repeated).to.equal(false)
			expect(repeatedReason).to.equal("jump_frequency")
		end)

		it("allows another grounded jump after the interval", function()
			local allowed, reason = MovementRules.canStartJump(10, 10.65, true, 0.65)
			expect(allowed).to.equal(true)
			expect(reason).to.equal(nil)
		end)
	end)
end
