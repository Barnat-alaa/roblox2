--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BotAim = require(ReplicatedStorage.Shared.Simulation.BotAim)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local Wind = require(ReplicatedStorage.Shared.Simulation.Wind)

local EPSILON = 1e-9

return function()
	local testEnvironment: any = getfenv()
	local describe = testEnvironment.describe
	local it = testEnvironment.it
	local expect = testEnvironment.expect

	local function standardRequest(): BotAim.Request
		return {
			origin = Vector3.new(-48, 12, 0),
			target = Vector3.new(24, 12, 0),
			wind = 0,
			seed = 73_421,
			turnIndex = 4,
			difficulty = "Normal",
		}
	end

	local function expectFinite(value: number)
		expect(value == value and value > -math.huge and value < math.huge).to.equal(true)
	end

	local function expectLegal(solution: BotAim.Solution)
		local definition = Weapons.get(solution.weaponId)
		expect(definition ~= nil).to.equal(true)
		expect(solution.angle >= GameConfig.minimumAimDegrees).to.equal(true)
		expect(solution.angle <= GameConfig.maximumAimDegrees).to.equal(true)
		expect(solution.power >= GameConfig.minimumPower).to.equal(true)
		expect(solution.power <= GameConfig.maximumPower).to.equal(true)
		expect(solution.flightTime > 0).to.equal(true)
		if definition then
			expect(solution.flightTime <= definition.maxLifetime).to.equal(true)
		end
		expect(solution.evaluatedCandidates <= BotAim.MAX_CANDIDATE_EVALUATIONS).to.equal(true)
		expectFinite(solution.missDistance)
		expectFinite(solution.predictedImpact.X)
		expectFinite(solution.predictedImpact.Y)
		expectFinite(solution.predictedImpact.Z)
	end

	describe("BotAim deterministic search", function()
		it("returns the same complete solution without mutating a frozen request", function()
			local weaponIds = table.freeze({ "acorn_cannon", "mole_drill" })
			local request = table.freeze({
				origin = Vector3.new(-48, 12, 0),
				target = Vector3.new(24, 12, 0),
				wind = 2.5,
				seed = -193_771,
				turnIndex = 8,
				difficulty = "Normal" :: BotAim.Difficulty,
				weaponIds = weaponIds,
			})

			local first = BotAim.solve(request)
			local second = BotAim.solve(request)

			expect(first.weaponId).to.equal(second.weaponId)
			expect(first.angle).to.equal(second.angle)
			expect(first.power).to.equal(second.power)
			expect(first.flightTime).to.equal(second.flightTime)
			expect(first.predictedImpact).to.equal(second.predictedImpact)
			expect(first.missDistance).to.equal(second.missDistance)
			expect(first.appliedAngleError).to.equal(second.appliedAngleError)
			expect(first.appliedPowerError).to.equal(second.appliedPowerError)
			expect(first.evaluatedCandidates).to.equal(second.evaluatedCandidates)
			expect(#weaponIds).to.equal(2)
			expect(weaponIds[1]).to.equal("acorn_cannon")
			expect(weaponIds[2]).to.equal("mole_drill")
		end)

		it("returns legal finite shots across target directions, wind, and difficulty", function()
			local cases: { BotAim.Request } = {
				standardRequest(),
				{
					origin = Vector3.new(52, 10, 0),
					target = Vector3.new(-30, 15, 0),
					wind = -8,
					seed = 1,
					turnIndex = 0,
					difficulty = "Easy",
				},
				{
					origin = Vector3.new(-64, 15, 0),
					target = Vector3.new(48, 10.5, 0),
					wind = 8,
					seed = 2_147_483_647,
					turnIndex = 42,
					difficulty = "Hard",
				},
			}

			for _, request in cases do
				expectLegal(BotAim.solve(request))
			end
		end)

		it("uses the correct world-angle hemisphere for reachable targets", function()
			local rightRequest = standardRequest()
			rightRequest.target = Vector3.new(-8, 12, 0)
			rightRequest.difficulty = "Hard"
			local leftRequest = standardRequest()
			leftRequest.origin = Vector3.new(48, 12, 0)
			leftRequest.target = Vector3.new(8, 12, 0)
			leftRequest.difficulty = "Hard"

			local right = BotAim.solve(rightRequest)
			local left = BotAim.solve(leftRequest)

			expect(right.angle < 90).to.equal(true)
			expect(left.angle > 90).to.equal(true)
			expect(right.missDistance <= 12).to.equal(true)
			expect(left.missDistance <= 12).to.equal(true)
		end)

		it("changes its solution to compensate for signed wind", function()
			local leftWindRequest = standardRequest()
			leftWindRequest.wind = -8
			leftWindRequest.difficulty = "Hard"
			local rightWindRequest = standardRequest()
			rightWindRequest.wind = 8
			rightWindRequest.difficulty = "Hard"

			local leftWind = BotAim.solve(leftWindRequest)
			local rightWind = BotAim.solve(rightWindRequest)
			local changed = leftWind.weaponId ~= rightWind.weaponId
				or math.abs(leftWind.angle - rightWind.angle) > EPSILON
				or math.abs(leftWind.power - rightWind.power) > EPSILON

			expect(changed).to.equal(true)
			expectLegal(leftWind)
			expectLegal(rightWind)
		end)
	end)

	describe("BotAim controlled inaccuracy and bounds", function()
		it("keeps initial Normal shots threatening across default solo match seeds", function()
			for matchSequence = 1, 12 do
				local roundNumber = 1
				local seed = bit32.band(
					bit32.bxor(
						bit32.band(matchSequence, 0x7FFFFFFF),
						bit32.lshift(bit32.band(roundNumber, 0x7FFF), 12),
						0x4F1BBCDC
					),
					0x7FFFFFFF
				)
				local solution = BotAim.solve({
					origin = Vector3.new(48, 12.9, 0),
					target = Vector3.new(-64, 12, 0),
					wind = Wind.forRound(20_260_713 + matchSequence, 0),
					seed = seed,
					turnIndex = roundNumber,
					difficulty = "Normal",
				})
				local definition = Weapons.get(solution.weaponId)
				expect(definition ~= nil).to.equal(true)
				if definition then
					expect(solution.missDistance <= definition.explosionRadius).to.equal(true)
				end
			end
		end)

		it("keeps deterministic non-zero error inside each difficulty profile", function()
			local function expectBoundedError(difficulty: BotAim.Difficulty)
				local request = standardRequest()
				request.difficulty = difficulty
				local solution = BotAim.solve(request)
				local limits = BotAim.ERROR_LIMITS[difficulty]

				expect(math.abs(solution.appliedAngleError) <= limits.angle + EPSILON).to.equal(
					true
				)
				expect(math.abs(solution.appliedPowerError) <= limits.power + EPSILON).to.equal(
					true
				)
				expect(
					math.abs(solution.appliedAngleError) > EPSILON
						or math.abs(solution.appliedPowerError) > EPSILON
				).to.equal(true)
			end

			expectBoundedError("Easy")
			expectBoundedError("Normal")
			expectBoundedError("Hard")
		end)

		it("varies controlled error across deterministic seeds", function()
			local seen: { [string]: boolean } = {}
			for seed = 1, 16 do
				local request = standardRequest()
				request.seed = seed
				local solution = BotAim.solve(request)
				seen[string.format("%.8f:%.8f", solution.angle, solution.power)] = true
			end

			local uniqueCount = 0
			for _ in seen do
				uniqueCount += 1
			end
			expect(uniqueCount > 1).to.equal(true)
		end)

		it("never exceeds the advertised candidate budget", function()
			local request = standardRequest()
			request.weaponIds = {
				"acorn_cannon",
				"fizzy_bomb",
				"mole_drill",
				"bubble_bouncer",
			}
			local solution = BotAim.solve(request)

			expect(solution.evaluatedCandidates).to.equal(BotAim.MAX_CANDIDATE_EVALUATIONS)
			expectLegal(solution)
		end)

		it("returns a finite legal fallback for an unreachable vertical target", function()
			local request = standardRequest()
			request.origin = Vector3.zero
			request.target = Vector3.new(0, 1_000, 0)
			request.weaponIds = { "acorn_cannon" }
			local solution = BotAim.solve(request)

			expectLegal(solution)
			expect(solution.weaponId).to.equal("acorn_cannon")
			expect(solution.evaluatedCandidates < BotAim.MAX_CANDIDATE_EVALUATIONS).to.equal(true)
		end)

		it("rejects malformed and unbounded requests", function()
			local invalidWind = standardRequest()
			invalidWind.wind = 0 / 0
			local emptyWeapons = standardRequest()
			emptyWeapons.weaponIds = {}
			local duplicateWeapons = standardRequest()
			duplicateWeapons.weaponIds = { "acorn_cannon", "acorn_cannon" }
			local tooManyWeapons = standardRequest()
			tooManyWeapons.weaponIds = {
				"acorn_cannon",
				"fizzy_bomb",
				"mole_drill",
				"bubble_bouncer",
				"acorn_cannon",
			}
			local badDifficulty: any = standardRequest()
			badDifficulty.difficulty = "Impossible"

			expect(pcall(BotAim.solve, invalidWind)).to.equal(false)
			expect(pcall(BotAim.solve, emptyWeapons)).to.equal(false)
			expect(pcall(BotAim.solve, duplicateWeapons)).to.equal(false)
			expect(pcall(BotAim.solve, tooManyWeapons)).to.equal(false)
			expect(pcall(BotAim.solve, badDifficulty)).to.equal(false)
		end)
	end)
end
