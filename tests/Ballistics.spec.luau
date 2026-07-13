--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ballistics = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Simulation"):WaitForChild("Ballistics") :: ModuleScript
)

-- Vector3 components use float precision in the engine; repeated fixed steps can
-- accumulate a few ten-thousandths while remaining physically equivalent.
local EPSILON = 5e-5

return function()
	-- TestEZ injects these functions into the spec environment at execution time.
	local testEnvironment: any = getfenv()
	local describe = testEnvironment.describe
	local it = testEnvironment.it
	local expect = testEnvironment.expect

	local function expectNear(actual: number, expected: number)
		expect(math.abs(actual - expected) <= EPSILON).to.equal(true)
	end

	local function expectVectorNear(actual: Vector3, expected: Vector3)
		expectNear(actual.X, expected.X)
		expectNear(actual.Y, expected.Y)
		expectNear(actual.Z, expected.Z)
	end

	describe("Ballistics", function()
		it("evaluates a gravity-only trajectory", function()
			local acceleration = Ballistics.acceleration({
				gravity = Vector3.new(0, -10, 0),
				wind = Vector3.zero,
				gravityScale = 1,
				windScale = 1,
			})
			local position =
				Ballistics.positionAt(Vector3.zero, Vector3.new(10, 20, 0), acceleration, 2)

			expectVectorNear(position, Vector3.new(20, 20, 0))
		end)

		it("adds wind as horizontal acceleration", function()
			local acceleration = Ballistics.acceleration({
				gravity = Vector3.new(0, -10, 0),
				wind = Vector3.new(4, 0, 0),
				gravityScale = 1,
				windScale = 1,
			})
			local position =
				Ballistics.positionAt(Vector3.zero, Vector3.new(10, 20, 0), acceleration, 2)

			expectVectorNear(position, Vector3.new(28, 20, 0))
		end)

		it("handles negative wind without changing vertical motion", function()
			local acceleration = Ballistics.acceleration({
				gravity = Vector3.new(0, -10, 0),
				wind = Vector3.new(-4, 0, 0),
				gravityScale = 1,
				windScale = 1,
			})
			local position =
				Ballistics.positionAt(Vector3.zero, Vector3.new(10, 20, 0), acceleration, 2)

			expectVectorNear(position, Vector3.new(12, 20, 0))
		end)

		it("scales gravity independently from wind", function()
			local acceleration = Ballistics.acceleration({
				gravity = Vector3.new(0, -10, 0),
				wind = Vector3.new(8, 0, 0),
				gravityScale = 0.5,
				windScale = 0.25,
			})

			expectVectorNear(acceleration, Vector3.new(2, -5, 0))
		end)

		it("uses the shared world-angle convention", function()
			expectVectorNear(Ballistics.worldLaunchVelocity(90, 60), Vector3.new(0, 60, 0))
			expectVectorNear(Ballistics.worldLaunchVelocity(180, 60), Vector3.new(-60, 0, 0))
			expectVectorNear(
				Ballistics.launchVelocity(30, 60, -1),
				Ballistics.worldLaunchVelocity(150, 60)
			)
		end)

		it("keeps fixed stepping consistent with closed-form evaluation", function()
			local acceleration = Vector3.new(3, -12, 0)
			local state = Ballistics.createState(Vector3.new(2, 5, 0), Vector3.new(7, 18, 0))

			for _ = 1, 60 do
				state = Ballistics.step(state, acceleration, 1 / 60)
			end

			local expectedPosition =
				Ballistics.positionAt(Vector3.new(2, 5, 0), Vector3.new(7, 18, 0), acceleration, 1)
			local expectedVelocity = Ballistics.velocityAt(Vector3.new(7, 18, 0), acceleration, 1)

			expectVectorNear(state.position, expectedPosition)
			expectVectorNear(state.velocity, expectedVelocity)
			expectNear(state.elapsed, 1)
		end)

		it("bounds individual simulation steps and preview allocation", function()
			local state = Ballistics.createState(Vector3.zero, Vector3.new(10, 10, 0))
			local points = Ballistics.simulatePreview(state, Vector3.new(0, -10, 0), 1 / 60, 10)
			local acceptedOversizedStep = pcall(function()
				Ballistics.step(state, Vector3.zero, Ballistics.MAX_STEP + 0.001)
			end)

			expect(#points).to.equal(11)
			expectVectorNear(points[1], Vector3.zero)
			expect(acceptedOversizedStep).to.equal(false)
		end)
	end)
end
