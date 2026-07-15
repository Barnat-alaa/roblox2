--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LobbyRules = require(ReplicatedStorage.Shared.Simulation.LobbyRules)

return function()
	local testEnvironment: any = getfenv()
	local describe = testEnvironment.describe
	local it = testEnvironment.it
	local expect = testEnvironment.expect

	local function entry(userId: number, mode: LobbyRules.Mode, joinedAt: number)
		return {
			userId = userId,
			mode = mode,
			joinedAt = joinedAt,
		}
	end

	describe("LobbyRules request boundary", function()
		it("accepts the compact action protocol and rejects extra fields", function()
			expect(LobbyRules.parseRequest({ action = "Practice" }) ~= nil).to.equal(true)
			expect(LobbyRules.parseRequest({ action = "Casual" }) ~= nil).to.equal(true)
			expect(LobbyRules.parseRequest({ action = "ReturnToLobby" }) ~= nil).to.equal(true)
			expect(LobbyRules.parseRequest({ action = "Practice", mode = "Casual" })).to.equal(nil)
			expect(LobbyRules.parseRequest({ action = "Unknown" })).to.equal(nil)
			expect(LobbyRules.parseRequest("Practice")).to.equal(nil)
		end)

		it("uses optional queue tokens to make stale cancellation harmless", function()
			expect(LobbyRules.parseRequest({ action = "Cancel" }) ~= nil).to.equal(true)
			expect(LobbyRules.parseRequest({ action = "Cancel", queueToken = "queue-12" }) ~= nil).to.equal(
				true
			)
			expect(LobbyRules.cancelMatches("queue-12", nil)).to.equal(true)
			expect(LobbyRules.cancelMatches("queue-12", "queue-12")).to.equal(true)
			expect(LobbyRules.cancelMatches("queue-13", "queue-12")).to.equal(false)
		end)
	end)

	describe("LobbyRules FIFO admission", function()
		it("starts Practice with a bot immediately", function()
			local selection = LobbyRules.selectMatch({ entry(101, "Practice", 20) }, 20, 8)
			assert(selection ~= nil, "Practice should select immediately")
			expect(selection.firstIndex).to.equal(1)
			expect(selection.secondIndex).to.equal(nil)
			expect(selection.mode).to.equal("Practice")
			expect(selection.botFilled).to.equal(true)
		end)

		it("pairs Casual players in FIFO order before the deadline", function()
			local queue = {
				entry(101, "Casual", 20),
				entry(202, "Practice", 21),
				entry(303, "Casual", 22),
			}
			local selection = LobbyRules.selectMatch(queue, 22, 8)
			assert(selection ~= nil, "two Casual entries should pair")
			expect(selection.firstIndex).to.equal(1)
			expect(selection.secondIndex).to.equal(3)
			expect(selection.mode).to.equal("Casual")
			expect(selection.botFilled).to.equal(false)
		end)

		it("does not hold Practice behind a lone Casual search", function()
			local queue = {
				entry(101, "Casual", 20),
				entry(202, "Practice", 21),
			}
			local selection = LobbyRules.selectMatch(queue, 21, 8)
			assert(selection ~= nil, "Practice should use an otherwise idle arena")
			expect(selection.firstIndex).to.equal(2)
			expect(selection.secondIndex).to.equal(nil)
			expect(selection.mode).to.equal("Practice")
			expect(selection.botFilled).to.equal(true)
		end)

		it("bot-fills Casual only at its bounded deadline", function()
			local queue = { entry(101, "Casual", 20) }
			expect(LobbyRules.selectMatch(queue, 27.999, 8)).to.equal(nil)
			local selection = LobbyRules.selectMatch(queue, 28, 8)
			assert(selection ~= nil, "expired Casual should bot-fill")
			expect(selection.secondIndex).to.equal(nil)
			expect(selection.mode).to.equal("Casual")
			expect(selection.botFilled).to.equal(true)
		end)

		it("reports stable queue positions", function()
			local queue = {
				entry(101, "Casual", 20),
				entry(202, "Practice", 21),
			}
			expect(LobbyRules.queuePosition(queue, 101)).to.equal(1)
			expect(LobbyRules.queuePosition(queue, 202)).to.equal(2)
			expect(LobbyRules.queuePosition(queue, 303)).to.equal(nil)
		end)
	end)
end
