--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Damage = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Simulation"):WaitForChild("Damage") :: ModuleScript
)
local Weapons = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Weapons") :: ModuleScript
)

local EPSILON = 1e-6

return function()
	local testEnvironment: any = getfenv()
	local describe = testEnvironment.describe
	local it = testEnvironment.it
	local expect = testEnvironment.expect

	local function expectNear(actual: number, expected: number)
		expect(math.abs(actual - expected) <= EPSILON).to.equal(true)
	end

	describe("Damage", function()
		local profile = {
			radius = 10,
			maxDamage = 100,
			minDamage = 20,
		}

		it("deals maximum damage at the blast centre", function()
			expectNear(Damage.atDistance(profile, 0), 100)
		end)

		it("uses linear damage falloff inside the blast", function()
			expectNear(Damage.atDistance(profile, 2.5), 80)
			expectNear(Damage.atDistance(profile, 5), 60)
			expectNear(Damage.atDistance(profile, 7.5), 40)
		end)

		it("deals minimum damage on the edge and zero beyond it", function()
			expectNear(Damage.atDistance(profile, 10), 20)
			expectNear(Damage.atDistance(profile, 10.001), 0)
		end)

		it("calculates falloff from world positions", function()
			local amount = Damage.atPosition(profile, Vector3.new(10, 0, 0), Vector3.new(13, 4, 0))
			expectNear(amount, 60)
		end)

		it("tapers knockback separately to zero at the edge", function()
			expectNear(Damage.knockbackMagnitude(0, 10, 50), 50)
			expectNear(Damage.knockbackMagnitude(5, 10, 50), 25)
			expectNear(Damage.knockbackMagnitude(10, 10, 50), 0)
		end)

		it("rejects inverted damage profiles", function()
			local valid, reason = Damage.validateProfile({
				radius = 10,
				maxDamage = 20,
				minDamage = 30,
			})

			expect(valid).to.equal(false)
			expect(reason ~= nil).to.equal(true)
		end)
	end)

	describe("MVP weapon catalogue", function()
		it("contains four valid, distinct weapon behaviours", function()
			local valid, reason = Weapons.validateCatalogue(Weapons.All)
			local modes: { [string]: boolean } = {}

			for _, definition in Weapons.All do
				modes[definition.detonationMode] = true
				local damageValid = Damage.validateProfile({
					radius = definition.explosionRadius,
					maxDamage = definition.maxDamage,
					minDamage = definition.minDamage,
				})
				expect(damageValid).to.equal(true)
			end

			local modeCount = 0
			for _ in modes do
				modeCount += 1
			end

			expect(valid).to.equal(true)
			expect(reason).to.equal(nil)
			expect(#Weapons.All).to.equal(4)
			expect(modeCount).to.equal(4)
		end)

		it("resolves normalized power without accepting client-side overcharge", function()
			local definition = Weapons.ACORN_CANNON
			expectNear(Weapons.resolveSpeed(definition, 0), definition.initialSpeedMin)
			expectNear(Weapons.resolveSpeed(definition, 1), definition.initialSpeedMax)
			expect(Weapons.isValidPower(1.01)).to.equal(false)
		end)
	end)
end
