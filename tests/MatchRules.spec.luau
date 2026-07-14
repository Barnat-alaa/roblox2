--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MatchRules = require(ReplicatedStorage.Shared.Simulation.MatchRules)

return function()
	local testEnvironment: any = getfenv()
	local describe = testEnvironment.describe
	local it = testEnvironment.it
	local expect = testEnvironment.expect

	local function participant(
		userId: number,
		eliminated: boolean,
		isNpc: boolean?
	): MatchRules.ParticipantState
		return {
			userId = userId,
			eliminated = eliminated,
			isNpc = isNpc or false,
		}
	end

	local function requireOutcome(outcome: MatchRules.Outcome?): MatchRules.Outcome
		assert(outcome ~= nil, "expected a terminal match outcome")
		return outcome
	end

	describe("MatchRules outcomes", function()
		it("does not resolve while multiple roster participants survive", function()
			local roster = {
				participant(101, false),
				participant(202, false),
			}

			expect(MatchRules.evaluate(roster)).to.equal(nil)
		end)

		it("resolves one survivor as winner with an idempotent outcome", function()
			local roster = {
				participant(101, false),
				participant(202, true),
			}
			local first = requireOutcome(MatchRules.evaluate(roster))
			local second = requireOutcome(MatchRules.evaluate(roster))

			expect(first.winnerUserId).to.equal(101)
			expect(first.isDraw).to.equal(false)
			expect(first.reason).to.equal("last_participant_standing")
			expect(second.winnerUserId).to.equal(first.winnerUserId)
			expect(second.isDraw).to.equal(first.isDraw)
			expect(second.reason).to.equal(first.reason)
		end)

		it("resolves an all-dead roster as a draw", function()
			local outcome = requireOutcome(MatchRules.evaluate({
				participant(101, true),
				participant(202, true),
			}))

			expect(outcome.winnerUserId).to.equal(0)
			expect(outcome.isDraw).to.equal(true)
			expect(outcome.reason).to.equal("all_participants_eliminated")
		end)

		it("resolves NPC practice outcomes through the same roster rules", function()
			local humanWin = requireOutcome(MatchRules.evaluate({
				participant(101, false),
				participant(-1, true, true),
			}))
			local npcWin = requireOutcome(MatchRules.evaluate({
				participant(101, true),
				participant(-1, false, true),
			}))

			expect(humanWin.winnerUserId).to.equal(101)
			expect(humanWin.isDraw).to.equal(false)
			expect(npcWin.winnerUserId).to.equal(-1)
			expect(npcWin.isDraw).to.equal(false)
		end)

		it("resolves a disconnected roster member once runtime marks them eliminated", function()
			local outcome = requireOutcome(MatchRules.evaluate({
				participant(101, false),
				participant(202, true),
			}))

			expect(outcome.winnerUserId).to.equal(101)
			expect(outcome.isDraw).to.equal(false)
			expect(outcome.reason).to.equal("last_participant_standing")
		end)

		it("preserves eliminated roster state across respawn-like reevaluation", function()
			local eliminatedParticipant = table.freeze(participant(101, true))
			local survivingParticipant = table.freeze(participant(202, false))
			local roster = table.freeze({
				eliminatedParticipant,
				survivingParticipant,
			})

			local first = requireOutcome(MatchRules.evaluate(roster))
			-- Character respawns are runtime state and must not rewrite this retained roster.
			local second = requireOutcome(MatchRules.evaluate(roster))

			expect(eliminatedParticipant.eliminated).to.equal(true)
			expect(first.winnerUserId).to.equal(202)
			expect(second.winnerUserId).to.equal(202)
		end)
	end)

	describe("MatchRules rematch readiness", function()
		it("requires only connected humans without treating disconnect as elimination", function()
			local roster = {
				participant(303, false),
				participant(-1, false, true),
				participant(101, false),
				participant(202, false),
			}
			local required = MatchRules.requiredHumanUserIds(roster, {
				[101] = true,
				[202] = false,
				[303] = true,
			})

			expect(#required).to.equal(2)
			expect(required[1]).to.equal(101)
			expect(required[2]).to.equal(303)
			expect(MatchRules.evaluate(roster)).to.equal(nil)
		end)

		it("deduplicates repeated readiness writes and supports toggling", function()
			local required = { 101, 202 }
			local readyByUserId: { [number]: boolean } = {}

			expect(MatchRules.isUnanimousReady(required, readyByUserId)).to.equal(false)

			readyByUserId[101] = true
			readyByUserId[101] = true
			local oneReady = MatchRules.readyHumanUserIds(required, readyByUserId)
			expect(#oneReady).to.equal(1)
			expect(oneReady[1]).to.equal(101)
			expect(MatchRules.isUnanimousReady(required, readyByUserId)).to.equal(false)

			readyByUserId[202] = true
			local allReady = MatchRules.readyHumanUserIds(required, readyByUserId)
			expect(#allReady).to.equal(2)
			expect(allReady[1]).to.equal(101)
			expect(allReady[2]).to.equal(202)
			expect(MatchRules.isUnanimousReady(required, readyByUserId)).to.equal(true)

			readyByUserId[101] = false
			local toggled = MatchRules.readyHumanUserIds(required, readyByUserId)
			expect(#toggled).to.equal(1)
			expect(toggled[1]).to.equal(202)
			expect(MatchRules.isUnanimousReady(required, readyByUserId)).to.equal(false)
		end)

		it("does not start a rematch when no connected human is required", function()
			local required = MatchRules.requiredHumanUserIds({
				participant(-1, false, true),
				participant(101, false),
			}, {
				[101] = false,
			})

			expect(#required).to.equal(0)
			expect(MatchRules.isUnanimousReady(required, {})).to.equal(false)
		end)
	end)

	describe("MatchRules match identity", function()
		it("accepts bounded opaque identities and rejects malformed values", function()
			expect(MatchRules.isValidMatchId("match-20260713-0001")).to.equal(true)
			expect(MatchRules.isValidMatchId(string.rep("a", MatchRules.MAX_MATCH_ID_LENGTH))).to.equal(
				true
			)
			expect(MatchRules.isValidMatchId("")).to.equal(false)
			expect(MatchRules.isValidMatchId("match id")).to.equal(false)
			expect(MatchRules.isValidMatchId("match\nid")).to.equal(false)
			expect(MatchRules.isValidMatchId(string.rep("a", MatchRules.MAX_MATCH_ID_LENGTH + 1))).to.equal(
				false
			)
			expect(MatchRules.isValidMatchId(101)).to.equal(false)
		end)
	end)
end
