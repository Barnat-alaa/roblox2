--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Wind = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Simulation"):WaitForChild("Wind") :: ModuleScript
)

local EPSILON = 1e-9

return function()
	local testEnvironment: any = getfenv()
	local describe = testEnvironment.describe
	local it = testEnvironment.it
	local expect = testEnvironment.expect

	describe("Wind", function()
		it("is deterministic for a match seed and round", function()
			local first = Wind.forRound(1_337_042, 12)

			for _ = 1, 20 do
				expect(Wind.forRound(1_337_042, 12)).to.equal(first)
			end
		end)

		it("stays inside the configured signed range", function()
			local config = {
				minimum = -3.5,
				maximum = 5.25,
				deadZone = 0,
				quantum = 0.25,
			}

			for roundIndex = 0, 1_024 do
				local strength = Wind.forRound(-923_741, roundIndex, config)
				expect(strength >= config.minimum).to.equal(true)
				expect(strength <= config.maximum).to.equal(true)
				expect(
					math.abs(strength / config.quantum - math.round(strength / config.quantum))
						<= EPSILON
				).to.equal(true)
			end
		end)

		it("produces varied round values without losing replay determinism", function()
			local seen: { [number]: boolean } = {}
			local sawLeft = false
			local sawRight = false
			for roundIndex = 0, 63 do
				local strength = Wind.forRound(77, roundIndex)
				seen[strength] = true
				sawLeft = sawLeft or strength < 0
				sawRight = sawRight or strength > 0
			end

			local uniqueCount = 0
			for _ in seen do
				uniqueCount += 1
			end

			expect(uniqueCount > 8).to.equal(true)
			expect(sawLeft).to.equal(true)
			expect(sawRight).to.equal(true)
		end)

		it("maps all sufficiently light values into a deterministic calm zone", function()
			local alwaysCalm = {
				minimum = -0.1,
				maximum = 0.1,
				deadZone = 0.1,
				quantum = 0,
			}

			for roundIndex = 0, 32 do
				expect(Wind.forRound(100, roundIndex, alwaysCalm)).to.equal(0)
			end
		end)

		it("reports direction and converts strength to horizontal acceleration", function()
			expect(Wind.direction(-2)).to.equal("Left")
			expect(Wind.direction(0.2, 0.5)).to.equal("Calm")
			expect(Wind.direction(2)).to.equal("Right")
			expect(Wind.asAcceleration(3)).to.equal(Vector3.new(3, 0, 0))
		end)

		it("validates that wind ranges contain zero", function()
			local valid, reason = Wind.validateConfig({
				minimum = 1,
				maximum = 5,
				deadZone = 0,
				quantum = 0.25,
			})

			expect(valid).to.equal(false)
			expect(reason ~= nil).to.equal(true)
		end)
	end)
end
