--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local ProfileRules = require(ReplicatedStorage.Shared.Progression.ProfileRules)

local function reward(key: string): ProfileRules.ProcessedReward
	return {
		key = key,
		coins = 40,
		xp = 100,
		time = 1_700_000_000,
		outcome = "loss",
		mode = "player",
	}
end

return function()
	local testEnvironment: any = getfenv()
	local describe = testEnvironment.describe
	local it = testEnvironment.it
	local expect = testEnvironment.expect

	describe("ProfileRules schema", function()
		it("creates independent valid starter profiles", function()
			local first = ProfileRules.createDefault()
			local second = ProfileRules.createDefault()

			expect(ProfileRules.validate(first)).to.equal(true)
			expect(first.schemaVersion).to.equal(1)
			expect(first.economyVersion).to.equal(EconomyConfig.version)
			expect(first.coins).to.equal(0)
			expect(first.xp).to.equal(0)
			expect(first.stats.matchesPlayed).to.equal(0)
			expect(#first.processedRewards).to.equal(0)

			first.stats.matchesPlayed = 1
			table.insert(first.processedRewards, reward("Development|match|one|user|101"))
			expect(second.stats.matchesPlayed).to.equal(0)
			expect(#second.processedRewards).to.equal(0)
		end)

		it("deep-clones stats and reward entries", function()
			local original = ProfileRules.createDefault()
			original.stats.matchesPlayed = 1
			original.stats.wins = 1
			table.insert(original.processedRewards, reward("Development|match|one|user|101"))

			local copy = ProfileRules.clone(original)
			copy.stats.wins = 0
			copy.processedRewards[1].coins = 99

			expect(original.stats.wins).to.equal(1)
			expect(original.processedRewards[1].coins).to.equal(40)
		end)

		it("rejects negative, fractional, non-finite, and excessive balances", function()
			local negative = ProfileRules.createDefault()
			negative.coins = -1
			local fractional = ProfileRules.createDefault()
			fractional.xp = 0.5
			local infinite = ProfileRules.createDefault()
			infinite.coins = math.huge
			local notANumber = ProfileRules.createDefault()
			notANumber.xp = 0 / 0
			local excessive = ProfileRules.createDefault()
			excessive.coins = EconomyConfig.maxCoins + 1

			expect(ProfileRules.validate(negative)).to.equal(false)
			expect(ProfileRules.validate(fractional)).to.equal(false)
			expect(ProfileRules.validate(infinite)).to.equal(false)
			expect(ProfileRules.validate(notANumber)).to.equal(false)
			expect(ProfileRules.validate(excessive)).to.equal(false)
		end)

		it("enforces bounded internally consistent match statistics", function()
			local inconsistent = ProfileRules.createDefault()
			inconsistent.stats.matchesPlayed = 1
			inconsistent.stats.wins = 1
			inconsistent.stats.losses = 1
			local unclassified = ProfileRules.createDefault()
			unclassified.stats.matchesPlayed = 1
			local negative = ProfileRules.createDefault()
			negative.stats.draws = -1
			local fractional = ProfileRules.createDefault()
			fractional.stats.matchesPlayed = 1.5

			expect(ProfileRules.validate(inconsistent)).to.equal(false)
			expect(ProfileRules.validate(unclassified)).to.equal(false)
			expect(ProfileRules.validate(negative)).to.equal(false)
			expect(ProfileRules.validate(fractional)).to.equal(false)
		end)

		it("validates a dense unique reward ledger with outcome and mode metadata", function()
			local valid = ProfileRules.createDefault()
			valid.processedRewards = {
				reward("Development|match|one|user|101"),
				reward("Development|match|two|user|101"),
			}
			local duplicate = ProfileRules.clone(valid)
			duplicate.processedRewards[2].key = duplicate.processedRewards[1].key
			local sparse = ProfileRules.createDefault()
			local sparseRewards = sparse.processedRewards :: any
			sparseRewards[2] = reward("Development|match|two|user|101")
			local badMetadata = ProfileRules.clone(valid)
			local firstReward = badMetadata.processedRewards[1] :: any
			firstReward.mode = "unknown"

			expect(ProfileRules.validate(valid)).to.equal(true)
			expect(ProfileRules.validate(duplicate)).to.equal(false)
			expect(ProfileRules.validate(sparse)).to.equal(false)
			expect(ProfileRules.validate(badMetadata)).to.equal(false)
		end)

		it("rejects ledgers larger than the configured retention bound", function()
			local profile = ProfileRules.createDefault()
			for index = 1, ProfileRules.MAX_PROCESSED_REWARDS + 1 do
				table.insert(
					profile.processedRewards,
					reward(string.format("Development|match|%d|user|101", index))
				)
			end

			expect(ProfileRules.validate(profile)).to.equal(false)
		end)

		it("rejects unexpected fields instead of silently persisting them", function()
			local profile: any = ProfileRules.createDefault()
			profile.adminCoins = 999

			expect(ProfileRules.validate(profile)).to.equal(false)
		end)
	end)

	describe("ProfileRules migration", function()
		it("creates a starter profile only for an observed missing value", function()
			local profile, reason = ProfileRules.migrate(nil)

			expect(reason).to.equal(nil)
			expect(profile ~= nil).to.equal(true)
			expect(ProfileRules.validate(profile)).to.equal(true)
		end)

		it("migrates exact v0 xp profiles without mutating the source", function()
			local legacy = {
				schemaVersion = 0,
				coins = 75,
				xp = 350,
			}
			local profile, reason = ProfileRules.migrate(legacy)
			assert(profile ~= nil, reason)

			expect(profile.schemaVersion).to.equal(1)
			expect(profile.coins).to.equal(75)
			expect(profile.xp).to.equal(350)
			expect(profile.stats.matchesPlayed).to.equal(0)
			expect(#profile.processedRewards).to.equal(0)
			expect(legacy.schemaVersion).to.equal(0)
		end)

		it("supports the documented legacy experience alias", function()
			local profile, reason = ProfileRules.migrate({
				schemaVersion = 0,
				coins = 5,
				experience = 149,
			})
			assert(profile ~= nil, reason)

			expect(profile.xp).to.equal(149)
			expect(ProfileRules.levelFromXp(profile.xp)).to.equal(1)
		end)

		it("rejects ambiguous, corrupt, and future legacy data", function()
			local ambiguous = ProfileRules.migrate({
				schemaVersion = 0,
				coins = 0,
				xp = 1,
				experience = 1,
			})
			local corrupt = ProfileRules.migrate({
				schemaVersion = 0,
				coins = -1,
				xp = 0,
			})
			local future, futureReason = ProfileRules.migrate({
				schemaVersion = 2,
			})

			expect(ambiguous).to.equal(nil)
			expect(corrupt).to.equal(nil)
			expect(future).to.equal(nil)
			expect(futureReason).to.equal("future_schema")
		end)

		it("returns an independent clone for an already-current profile", function()
			local current = ProfileRules.createDefault()
			local migrated, reason = ProfileRules.migrate(current)
			assert(migrated ~= nil, reason)
			migrated.stats.matchesPlayed = 1

			expect(current.stats.matchesPlayed).to.equal(0)
		end)
	end)

	describe("ProfileRules derived levels", function()
		it("uses the 150 plus 50 per-level curve", function()
			expect(ProfileRules.xpRequiredForNextLevel(1)).to.equal(150)
			expect(ProfileRules.xpRequiredForNextLevel(2)).to.equal(200)
			expect(ProfileRules.xpRequiredForNextLevel(99)).to.equal(5_050)
			expect(ProfileRules.xpRequiredForNextLevel(100)).to.equal(nil)
		end)

		it("derives boundary levels and caps at level 100", function()
			expect(ProfileRules.levelFromXp(0)).to.equal(1)
			expect(ProfileRules.levelFromXp(149)).to.equal(1)
			expect(ProfileRules.levelFromXp(150)).to.equal(2)
			expect(ProfileRules.levelFromXp(349)).to.equal(2)
			expect(ProfileRules.levelFromXp(350)).to.equal(3)
			expect(ProfileRules.totalXpRequiredForLevel(100)).to.equal(257_400)
			expect(ProfileRules.levelFromXp(EconomyConfig.maxXp)).to.equal(100)
		end)
	end)
end
