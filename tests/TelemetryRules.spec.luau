--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TelemetryRules = require(ReplicatedStorage.Shared.Analytics.TelemetryRules)

return function()
	local testEnvironment: any = getfenv()
	local describe = testEnvironment.describe
	local it = testEnvironment.it
	local expect = testEnvironment.expect

	describe("TelemetryRules", function()
		it("accepts and clones an allowlisted event", function()
			local source = { mode = "Casual", opponent = "Bot", waitSeconds = 8 }
			local payload, reason = TelemetryRules.sanitize("queue_matched", source)

			expect(reason).to.equal(nil)
			expect(payload ~= nil).to.equal(true)
			expect((payload :: TelemetryRules.Payload).opponent).to.equal("Bot")
			expect(payload == source).to.equal(false)
		end)

		it("rejects unknown events and extra fields", function()
			local unknown, unknownReason = TelemetryRules.sanitize("player_email", {})
			local extra, extraReason = TelemetryRules.sanitize("queue_joined", {
				mode = "Practice",
				userId = 123,
			})

			expect(unknown).to.equal(nil)
			expect(unknownReason).to.equal("unknown_event")
			expect(extra).to.equal(nil)
			expect(extraReason).to.equal("unexpected_field")
		end)

		it("rejects missing, non-finite, and out-of-range values", function()
			local missing = TelemetryRules.sanitize("shot_fired", { weaponId = "acorn_cannon" })
			local infinite = TelemetryRules.sanitize("queue_cancelled", {
				mode = "Casual",
				waitSeconds = math.huge,
			})
			local scale = TelemetryRules.sanitize("settings_changed", {
				reducedEffects = false,
				cameraShake = 0.5,
				uiScale = 2,
			})

			expect(missing).to.equal(nil)
			expect(infinite).to.equal(nil)
			expect(scale).to.equal(nil)
		end)

		it("rejects control characters and oversized text", function()
			local control = TelemetryRules.sanitize("telemetry_error", {
				source = "Lobby\nInjected",
				code = "bad",
			})
			local long = TelemetryRules.sanitize("projectile_impacted", {
				weaponId = string.rep("a", 65),
				terrainCellsChanged = 1,
			})

			expect(control).to.equal(nil)
			expect(long).to.equal(nil)
		end)
	end)
end
