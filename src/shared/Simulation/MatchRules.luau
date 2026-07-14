--!strict

-- Pure match outcome and rematch-readiness rules. Runtime services own player,
-- character, and connection lifecycles; this module only evaluates immutable
-- participant projections and numeric user-id sets.

local MatchRules = {}

export type ParticipantState = {
	userId: number,
	eliminated: boolean,
	isNpc: boolean,
}

export type Outcome = {
	winnerUserId: number,
	isDraw: boolean,
	reason: string,
}

local MAX_MATCH_ID_LENGTH = 96

MatchRules.MAX_MATCH_ID_LENGTH = MAX_MATCH_ID_LENGTH

function MatchRules.isValidMatchId(value: unknown): boolean
	if typeof(value) ~= "string" then
		return false
	end

	local matchId = value :: string
	return #matchId >= 1 and #matchId <= MAX_MATCH_ID_LENGTH and matchId:find("[%c%s]") == nil
end

-- A result exists once at most one authoritative roster member remains. Runtime
-- services defer calling this while a projectile or environment phase is active.
function MatchRules.evaluate(participants: { ParticipantState }): Outcome?
	local aliveCount = 0
	local winnerUserId = 0
	for _, participant in participants do
		if not participant.eliminated then
			aliveCount += 1
			winnerUserId = participant.userId
		end
	end

	if aliveCount > 1 then
		return nil
	end
	if aliveCount == 1 then
		return {
			winnerUserId = winnerUserId,
			isDraw = false,
			reason = "last_participant_standing",
		}
	end

	return {
		winnerUserId = 0,
		isDraw = true,
		reason = "all_participants_eliminated",
	}
end

function MatchRules.requiredHumanUserIds(
	participants: { ParticipantState },
	connectedByUserId: { [number]: boolean }
): { number }
	local required = {}
	for _, participant in participants do
		if not participant.isNpc and connectedByUserId[participant.userId] then
			table.insert(required, participant.userId)
		end
	end
	table.sort(required)
	return required
end

function MatchRules.readyHumanUserIds(
	requiredUserIds: { number },
	readyByUserId: { [number]: boolean }
): { number }
	local ready = {}
	for _, userId in requiredUserIds do
		if readyByUserId[userId] then
			table.insert(ready, userId)
		end
	end
	return ready
end

function MatchRules.isUnanimousReady(
	requiredUserIds: { number },
	readyByUserId: { [number]: boolean }
): boolean
	if #requiredUserIds == 0 then
		return false
	end

	for _, userId in requiredUserIds do
		if not readyByUserId[userId] then
			return false
		end
	end
	return true
end

return table.freeze(MatchRules)
