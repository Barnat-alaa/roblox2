--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local CosmeticRules = require(ReplicatedStorage.Shared.Progression.CosmeticRules)

return function()
	local testEnvironment: any = getfenv()
	local describe = testEnvironment.describe
	local it = testEnvironment.it
	local expect = testEnvironment.expect

	describe("CosmeticRules catalogue and inventory", function()
		it("ships one valid original starter cosmetic", function()
			expect(#Cosmetics.All).to.equal(1)
			expect(Cosmetics.STARTER_COSMETIC_ID).to.equal("sunset_scout_scarf")
			expect(Cosmetics.validateDefinition(Cosmetics.SUNSET_SCOUT_SCARF)).to.equal(true)
			expect(Cosmetics.SUNSET_SCOUT_SCARF.category).to.equal("neckwear")
		end)

		it("creates independent owned and equipped starter inventory", function()
			local first = CosmeticRules.createDefault()
			local second = CosmeticRules.createDefault()

			expect(CosmeticRules.validate(first)).to.equal(true)
			expect(first.equippedCosmetic).to.equal(Cosmetics.STARTER_COSMETIC_ID)
			expect(CosmeticRules.owns(first, Cosmetics.STARTER_COSMETIC_ID)).to.equal(true)
			first.ownedCosmetics[1] = "changed"
			expect(second.ownedCosmetics[1]).to.equal(Cosmetics.STARTER_COSMETIC_ID)
		end)

		it("requires dense unique known ownership and an owned equip", function()
			local sparse: any = CosmeticRules.createDefault()
			sparse.ownedCosmetics = {}
			sparse.ownedCosmetics[2] = Cosmetics.STARTER_COSMETIC_ID
			local duplicate = CosmeticRules.createDefault()
			table.insert(duplicate.ownedCosmetics, Cosmetics.STARTER_COSMETIC_ID)
			local unknown = CosmeticRules.createDefault()
			unknown.ownedCosmetics[1] = "copied_unknown_item"
			unknown.equippedCosmetic = "copied_unknown_item"
			local unowned = CosmeticRules.createDefault()
			unowned.ownedCosmetics = {}

			expect(CosmeticRules.validate(sparse)).to.equal(false)
			expect(CosmeticRules.validate(duplicate)).to.equal(false)
			expect(CosmeticRules.validate(unknown)).to.equal(false)
			expect(CosmeticRules.validate(unowned)).to.equal(false)
		end)

		it("equips only catalogue-owned items without mutating input", function()
			local original = CosmeticRules.createDefault()
			local equipped, reason = CosmeticRules.equip(original, Cosmetics.STARTER_COSMETIC_ID)
			assert(equipped ~= nil, reason)

			expect(equipped.equippedCosmetic).to.equal(Cosmetics.STARTER_COSMETIC_ID)
			expect(original.equippedCosmetic).to.equal(Cosmetics.STARTER_COSMETIC_ID)
			expect(equipped == original).to.equal(false)
			expect(equipped.ownedCosmetics == original.ownedCosmetics).to.equal(false)

			local rejected, rejectedReason = CosmeticRules.equip(original, "unowned_copy_item")
			expect(rejected).to.equal(nil)
			expect(rejectedReason).to.equal("unknown_cosmetic")
		end)

		it("rejects extra persisted inventory fields", function()
			local inventory: any = CosmeticRules.createDefault()
			inventory.combatBonus = 10

			expect(CosmeticRules.validate(inventory)).to.equal(false)
		end)
	end)
end
