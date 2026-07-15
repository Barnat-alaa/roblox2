--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SettingsConfig = require(ReplicatedStorage.Shared.Config.SettingsConfig)
local SettingsRules = require(ReplicatedStorage.Shared.Progression.SettingsRules)

return function()
	local testEnvironment: any = getfenv()
	local describe = testEnvironment.describe
	local it = testEnvironment.it
	local expect = testEnvironment.expect

	describe("SettingsRules", function()
		it("creates independent valid comfort and audio defaults", function()
			local first = SettingsRules.createDefault()
			local second = SettingsRules.createDefault()

			expect(SettingsRules.validate(first)).to.equal(true)
			expect(first.musicVolume).to.equal(0.5)
			expect(first.sfxVolume).to.equal(0.8)
			expect(first.cameraShake).to.equal(0.65)
			expect(first.reducedEffects).to.equal(false)
			expect(first.uiScale).to.equal(1)
			first.cameraShake = 0
			expect(second.cameraShake).to.equal(0.65)
		end)

		it("accepts inclusive control bounds", function()
			local minimum = SettingsRules.createDefault()
			minimum.musicVolume = SettingsConfig.minimumVolume
			minimum.sfxVolume = SettingsConfig.minimumVolume
			minimum.cameraShake = SettingsConfig.minimumCameraShake
			minimum.uiScale = SettingsConfig.minimumUiScale
			local maximum = SettingsRules.createDefault()
			maximum.musicVolume = SettingsConfig.maximumVolume
			maximum.sfxVolume = SettingsConfig.maximumVolume
			maximum.cameraShake = SettingsConfig.maximumCameraShake
			maximum.uiScale = SettingsConfig.maximumUiScale

			expect(SettingsRules.validate(minimum)).to.equal(true)
			expect(SettingsRules.validate(maximum)).to.equal(true)
		end)

		it("rejects non-finite, out-of-range, mistyped, and extra values", function()
			local infinite = SettingsRules.createDefault()
			infinite.cameraShake = math.huge
			local notANumber = SettingsRules.createDefault()
			notANumber.musicVolume = 0 / 0
			local tooLarge = SettingsRules.createDefault()
			tooLarge.uiScale = SettingsConfig.maximumUiScale + 0.01
			local mistyped: any = SettingsRules.createDefault()
			mistyped.reducedEffects = "yes"
			local extra: any = SettingsRules.createDefault()
			extra.disableHitboxes = true

			expect(SettingsRules.validate(infinite)).to.equal(false)
			expect(SettingsRules.validate(notANumber)).to.equal(false)
			expect(SettingsRules.validate(tooLarge)).to.equal(false)
			expect(SettingsRules.validate(mistyped)).to.equal(false)
			expect(SettingsRules.validate(extra)).to.equal(false)
		end)

		it("applies partial patches atomically without mutating current settings", function()
			local current = SettingsRules.createDefault()
			local updated, reason = SettingsRules.applyPatch(current, {
				reducedEffects = true,
				cameraShake = 0.25,
				uiScale = 1.1,
			})
			assert(updated ~= nil, reason)

			expect(updated.reducedEffects).to.equal(true)
			expect(updated.cameraShake).to.equal(0.25)
			expect(updated.uiScale).to.equal(1.1)
			expect(updated.musicVolume).to.equal(current.musicVolume)
			expect(updated.sfxVolume).to.equal(current.sfxVolume)
			expect(current.reducedEffects).to.equal(false)
			expect(current.cameraShake).to.equal(0.65)
		end)

		it("rejects invalid partial patches without partial mutation", function()
			local current = SettingsRules.createDefault()
			local invalid, invalidReason = SettingsRules.applyPatch(current, {
				reducedEffects = true,
				cameraShake = 2,
			})
			local unexpected, unexpectedReason = SettingsRules.applyPatch(current, {
				developerMode = true,
			})

			expect(invalid).to.equal(nil)
			expect(invalidReason).to.equal("invalid_camera_shake")
			expect(unexpected).to.equal(nil)
			expect(unexpectedReason).to.equal("invalid_settings_patch_fields")
			expect(current.reducedEffects).to.equal(false)
			expect(current.cameraShake).to.equal(0.65)
		end)
	end)
end
