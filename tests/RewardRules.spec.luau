--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local EnvironmentConfig = require(ReplicatedStorage.Shared.Config.EnvironmentConfig)
local ProfileRules = require(ReplicatedStorage.Shared.Progression.ProfileRules)
local RewardRules = require(ReplicatedStorage.Shared.Progression.RewardRules)

local function context(
	matchId: string,
	outcome: RewardRules.MatchOutcome,
	opponentIsBot: boolean?,
	completion: RewardRules.Completion?,
	legalTurnsCompleted: number?,
	eliminated: boolean?,
	userId: number?
): RewardRules.MatchRewardContext
	return {
		matchId = matchId,
		userId = userId or 101,
		outcome = outcome,
		completion = completion or "completed",
		opponentIsBot = opponentIsBot or false,
		legalTurnsCompleted = legalTurnsCompleted or 2,
		eliminated = eliminated or false,
	}
end

return function()
	local testEnvironment: any = getfenv()
	local describe = testEnvironment.describe
	local it = testEnvironment.it
	local expect = testEnvironment.expect

	describe("RewardRules eligibility", function()
		it("accepts a winner even after a legitimate short match", function()
			local eligible, reason = RewardRules.isEligible(context("winner", "win", false, nil, 0))

			expect(eligible).to.equal(true)
			expect(reason).to.equal(nil)
		end)

		it("accepts two legal turns or elimination after one legal turn", function()
			local twoTurns = RewardRules.isEligible(context("two-turns", "loss", false, nil, 2))
			local eliminated =
				RewardRules.isEligible(context("eliminated", "loss", false, nil, 1, true))

			expect(twoTurns).to.equal(true)
			expect(eliminated).to.equal(true)
		end)

		it("rejects participation just below every eligibility boundary", function()
			local oneTurn, oneTurnReason =
				RewardRules.isEligible(context("one-turn", "loss", false, nil, 1, false))
			local eliminatedWithoutTurn, eliminatedReason =
				RewardRules.isEligible(context("zero-turn", "loss", false, nil, 0, true))

			expect(oneTurn).to.equal(false)
			expect(oneTurnReason).to.equal("insufficient_participation")
			expect(eliminatedWithoutTurn).to.equal(false)
			expect(eliminatedReason).to.equal("insufficient_participation")
		end)

		it("always rejects abandonment and disconnect", function()
			local abandonment, abandonmentReason =
				RewardRules.isEligible(context("abandon", "win", false, "abandonment", 100, true))
			local disconnect, disconnectReason =
				RewardRules.isEligible(context("disconnect", "win", false, "disconnect", 100, true))

			expect(abandonment).to.equal(false)
			expect(abandonmentReason).to.equal("abandonment")
			expect(disconnect).to.equal(false)
			expect(disconnectReason).to.equal("disconnect")
		end)

		it("bounds the legal-turn counter", function()
			local invalid: any = context("turn-overflow", "loss")
			invalid.legalTurnsCompleted = RewardRules.MAX_LEGAL_TURNS + 1

			local eligible, reason = RewardRules.isEligible(invalid)
			expect(eligible).to.equal(false)
			expect(reason).to.equal("invalid_legal_turns")
		end)
	end)

	describe("RewardRules deterministic calculation", function()
		it("calculates player completion, win, and draw rewards", function()
			local loss = RewardRules.calculateMatchReward(context("loss", "loss"))
			local win = RewardRules.calculateMatchReward(context("win", "win"))
			local draw = RewardRules.calculateMatchReward(context("draw", "draw"))
			assert(
				loss ~= nil and win ~= nil and draw ~= nil,
				"eligible player rewards should exist"
			)

			expect(loss.coins).to.equal(40)
			expect(loss.xp).to.equal(100)
			expect(win.coins).to.equal(60)
			expect(win.xp).to.equal(150)
			expect(draw.coins).to.equal(50)
			expect(draw.xp).to.equal(125)
		end)

		it("applies the bot multiplier with deterministic floor rounding", function()
			local loss = RewardRules.calculateMatchReward(context("bot-loss", "loss", true))
			local win = RewardRules.calculateMatchReward(context("bot-win", "win", true))
			local draw = RewardRules.calculateMatchReward(context("bot-draw", "draw", true))
			assert(loss ~= nil and win ~= nil and draw ~= nil, "eligible bot rewards should exist")

			expect(loss.coins).to.equal(34)
			expect(loss.xp).to.equal(85)
			expect(win.coins).to.equal(51)
			expect(win.xp).to.equal(127)
			expect(draw.coins).to.equal(42)
			expect(draw.xp).to.equal(106)
		end)
	end)

	describe("RewardRules atomic grants", function()
		it("builds a stable environment/match/user identity without economy version", function()
			local key, reason = RewardRules.buildGrantId("match-abc", 101)

			expect(reason).to.equal(nil)
			expect(key).to.equal("Development|match|match-abc|user|101")
			expect((key :: string):find("economy") == nil).to.equal(true)
			expect(EnvironmentConfig.name).to.equal("Development")
		end)

		it("supports nonzero negative Studio test-player IDs", function()
			local request = context("studio-player", "loss", false, nil, 2, false, -2)
			local key = RewardRules.buildGrantId(request.matchId, request.userId)
			local result, reason =
				RewardRules.applyMatchReward(ProfileRules.createDefault(), request, 10)

			expect(key).to.equal("Development|match|studio-player|user|-2")
			expect(reason).to.equal(nil)
			expect(result ~= nil and result.status == "Granted").to.equal(true)
		end)

		it("grants balances, stats, and ledger metadata without mutating input", function()
			local original = ProfileRules.createDefault()
			local result, reason = RewardRules.applyMatchReward(
				original,
				context("first", "win", true, nil, 0),
				1_700_000_001
			)
			assert(result ~= nil, reason)

			expect(result.status).to.equal("Granted")
			expect(result.profile.coins).to.equal(51)
			expect(result.profile.xp).to.equal(127)
			expect(result.profile.stats.matchesPlayed).to.equal(1)
			expect(result.profile.stats.wins).to.equal(1)
			expect(result.grant.outcome).to.equal("win")
			expect(result.grant.mode).to.equal("bot")
			expect(result.grant.time).to.equal(1_700_000_001)
			expect(original.coins).to.equal(0)
			expect(original.stats.matchesPlayed).to.equal(0)
			expect(#original.processedRewards).to.equal(0)
		end)

		it("returns Duplicate with the original grant and no second mutation", function()
			local request = context("duplicate", "draw")
			local first = RewardRules.applyMatchReward(ProfileRules.createDefault(), request, 10)
			assert(first ~= nil, "first eligible reward should be granted")
			first.profile.economyVersion = EconomyConfig.version + 1

			local duplicate, reason = RewardRules.applyMatchReward(first.profile, request, 999)
			assert(duplicate ~= nil, reason)

			expect(duplicate.status).to.equal("Duplicate")
			expect(duplicate.profile.coins).to.equal(first.profile.coins)
			expect(duplicate.profile.xp).to.equal(first.profile.xp)
			expect(duplicate.profile.stats.matchesPlayed).to.equal(1)
			expect(duplicate.profile.stats.draws).to.equal(1)
			expect(#duplicate.profile.processedRewards).to.equal(1)
			expect(duplicate.grant.time).to.equal(10)
		end)

		it("increments exactly one outcome counter", function()
			local profile = ProfileRules.createDefault()
			for _, outcome in { "win", "loss", "draw" } :: { RewardRules.MatchOutcome } do
				local result, reason = RewardRules.applyMatchReward(
					profile,
					context("stats-" .. outcome, outcome),
					100
				)
				assert(result ~= nil, reason)
				profile = result.profile
			end

			expect(profile.stats.matchesPlayed).to.equal(3)
			expect(profile.stats.wins).to.equal(1)
			expect(profile.stats.losses).to.equal(1)
			expect(profile.stats.draws).to.equal(1)
		end)

		it("retains only the latest 64 processed grants", function()
			local profile = ProfileRules.createDefault()
			for index = 1, ProfileRules.MAX_PROCESSED_REWARDS + 1 do
				local result, reason = RewardRules.applyMatchReward(
					profile,
					context("retention-" .. index, "loss"),
					index
				)
				assert(result ~= nil, reason)
				profile = result.profile
			end

			expect(#profile.processedRewards).to.equal(64)
			expect(profile.processedRewards[1].key).to.equal(
				"Development|match|retention-2|user|101"
			)
			expect(profile.processedRewards[64].key).to.equal(
				"Development|match|retention-65|user|101"
			)
			expect(profile.stats.matchesPlayed).to.equal(65)
		end)

		it("fails atomically when a balance would overflow", function()
			local profile = ProfileRules.createDefault()
			profile.coins = EconomyConfig.maxCoins
			local result, reason =
				RewardRules.applyMatchReward(profile, context("overflow", "loss"), 1)

			expect(result).to.equal(nil)
			expect(reason).to.equal("coins_overflow")
			expect(profile.coins).to.equal(EconomyConfig.maxCoins)
			expect(profile.stats.matchesPlayed).to.equal(0)
			expect(#profile.processedRewards).to.equal(0)
		end)

		it("does not mutate or record ineligible results", function()
			local profile = ProfileRules.createDefault()
			local result, reason = RewardRules.applyMatchReward(
				profile,
				context("afk", "loss", false, nil, 1, false),
				1
			)

			expect(result).to.equal(nil)
			expect(reason).to.equal("insufficient_participation")
			expect(profile.stats.matchesPlayed).to.equal(0)
			expect(#profile.processedRewards).to.equal(0)
		end)
	end)
end
