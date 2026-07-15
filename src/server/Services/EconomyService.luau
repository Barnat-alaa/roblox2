--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local ProfileRules = require(ReplicatedStorage.Shared.Progression.ProfileRules)
local RewardRules = require(ReplicatedStorage.Shared.Progression.RewardRules)

local DataService = require(script.Parent.DataService)
local NetworkService = require(script.Parent.NetworkService)

export type MatchMode = ProfileRules.RewardMode
export type ParticipantOutcome = ProfileRules.RewardOutcome

export type CompletionParticipant = {
	player: Player?,
	userId: number,
	isNpc: boolean,
	eliminated: boolean,
	abandoned: boolean,
	legalTurnsCompleted: number,
	outcome: ParticipantOutcome,
}

export type MatchCompletion = {
	schemaVersion: number,
	resultId: string,
	matchId: string,
	mode: MatchMode,
	startedAt: number,
	completedAt: number,
	winnerUserId: number,
	isDraw: boolean,
	reason: string,
	economyVersion: number,
	participants: { CompletionParticipant },
}

export type RewardStatus =
	"Pending"
	| "Granted"
	| "Duplicate"
	| "Ineligible"
	| "ReadOnly"
	| "Unavailable"

export type ResultReward = {
	userId: number,
	status: RewardStatus,
	coins: number,
	experience: number,
}

type Diagnostics = {
	queued: number,
	granted: number,
	duplicate: number,
	ineligible: number,
	readOnly: number,
	unavailable: number,
}

local EconomyService = {}

local started = false
local remotes: NetworkService.Remotes? = nil
local lastRewardEventTime = 0
local diagnostics: Diagnostics = {
	queued = 0,
	granted = 0,
	duplicate = 0,
	ineligible = 0,
	readOnly = 0,
	unavailable = 0,
}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function setDiagnostics()
	Workspace:SetAttribute("CritterClashRewardsQueued", diagnostics.queued)
	Workspace:SetAttribute("CritterClashRewardsGranted", diagnostics.granted)
	Workspace:SetAttribute("CritterClashRewardsDuplicate", diagnostics.duplicate)
	Workspace:SetAttribute("CritterClashRewardsIneligible", diagnostics.ineligible)
	Workspace:SetAttribute("CritterClashRewardsReadOnly", diagnostics.readOnly)
	Workspace:SetAttribute("CritterClashRewardsUnavailable", diagnostics.unavailable)
end

local function nextRewardEventTime(minimum: number): number
	local nextTime =
		math.max(Workspace:GetServerTimeNow(), minimum + 1e-6, lastRewardEventTime + 1e-6)
	lastRewardEventTime = nextTime
	return nextTime
end

local function resultReward(
	userId: number,
	status: RewardStatus,
	coins: number,
	experience: number
): ResultReward
	return {
		userId = userId,
		status = status,
		coins = coins,
		experience = experience,
	}
end

local function completionStatus(
	completion: MatchCompletion,
	participant: CompletionParticipant
): RewardRules.Completion
	if participant.abandoned then
		return "abandonment"
	end
	if completion.reason == "disconnect" then
		return "disconnect"
	end
	return "completed"
end

local function validateCompletion(completion: MatchCompletion)
	assert(completion.schemaVersion == 1, "unsupported match-completion schema")
	assert(completion.resultId == completion.matchId, "result and match identities must agree")
	assert(
		completion.economyVersion == EconomyConfig.version,
		"match-completion economy version must be current"
	)
	assert(completion.mode == "player" or completion.mode == "bot", "invalid match mode")
	assert(isFinite(completion.startedAt) and completion.startedAt >= 0, "invalid match start")
	assert(
		isFinite(completion.completedAt) and completion.completedAt >= completion.startedAt,
		"invalid match completion time"
	)
	assert(#completion.participants >= 1 and #completion.participants <= 4, "invalid roster size")

	local seenUserIds: { [number]: boolean } = {}
	local hasNpc = false
	for _, participant in completion.participants do
		assert(not seenUserIds[participant.userId], "duplicate completion participant")
		seenUserIds[participant.userId] = true
		if participant.isNpc then
			hasNpc = true
			assert(participant.player == nil, "NPC completion participant cannot own a Player")
		else
			local player = participant.player
			assert(
				player ~= nil and player.UserId == participant.userId,
				"invalid human participant"
			)
		end
	end
	assert((completion.mode == "bot") == hasNpc, "match mode does not match roster")
end

local function recordResolution(status: DataService.RewardResultStatus)
	if status == "Granted" then
		diagnostics.granted += 1
	elseif status == "Duplicate" then
		diagnostics.duplicate += 1
	elseif status == "ReadOnly" then
		diagnostics.readOnly += 1
	else
		diagnostics.unavailable += 1
	end
	setDiagnostics()
end

function EconomyService.start(networkRemotes: NetworkService.Remotes)
	assert(not started, "EconomyService may only be started once")
	started = true
	remotes = networkRemotes
	Workspace:SetAttribute("CritterClashEconomyVersion", EconomyConfig.version)
	setDiagnostics()
end

function EconomyService.enqueueMatchCompletion(completion: MatchCompletion): { ResultReward }
	assert(started and remotes ~= nil, "EconomyService must be started before match rewards")
	validateCompletion(completion)

	local rewards: { ResultReward } = {}
	local opponentIsBot = completion.mode == "bot"
	local grantedAt = os.time()
	for _, participant in completion.participants do
		if participant.isNpc then
			continue
		end

		local context: RewardRules.MatchRewardContext = table.freeze({
			matchId = completion.matchId,
			userId = participant.userId,
			outcome = participant.outcome,
			completion = completionStatus(completion, participant),
			opponentIsBot = opponentIsBot,
			eliminated = participant.eliminated,
			legalTurnsCompleted = participant.legalTurnsCompleted,
		}) :: RewardRules.MatchRewardContext
		local amount = RewardRules.calculateMatchReward(context)
		if not amount then
			diagnostics.ineligible += 1
			setDiagnostics()
			table.insert(rewards, resultReward(participant.userId, "Ineligible", 0, 0))
			continue
		end

		local player = participant.player :: Player
		local rewardUserId = participant.userId
		local rewardMatchId = completion.matchId
		local rewardCompletedAt = completion.completedAt
		local pendingReward = resultReward(rewardUserId, "Pending", amount.coins, amount.xp)
		local accepted = false
		local request: DataService.RewardRequest = {
			matchId = context.matchId,
			userId = context.userId,
			outcome = context.outcome,
			completion = context.completion,
			opponentIsBot = context.opponentIsBot,
			eliminated = context.eliminated,
			legalTurnsCompleted = context.legalTurnsCompleted,
			grantedAt = grantedAt,
		}
		local enqueueSucceeded, enqueueResult = pcall(function()
			return DataService.enqueueMatchReward(player, request, function(result)
				if not accepted then
					return
				end
				-- Keep the server's retained Result payload current as well as notifying
				-- the live client. Late joins/reconnects can then recover a terminal
				-- reward state instead of replaying Pending forever.
				pendingReward.status = result.status
				pendingReward.coins = result.coins
				pendingReward.experience = result.experience
				recordResolution(result.status)
				local recipient = Players:GetPlayerByUserId(rewardUserId)
				if recipient then
					local currentRemotes = remotes
					if currentRemotes then
						currentRemotes.matchEvent:FireClient(recipient, "RewardResolved", {
							matchId = rewardMatchId,
							userId = rewardUserId,
							status = result.status,
							coins = result.coins,
							experience = result.experience,
							serverTime = nextRewardEventTime(rewardCompletedAt),
						})
					end
				end
			end)
		end)
		if not enqueueSucceeded then
			diagnostics.unavailable += 1
			setDiagnostics()
			warn(string.format("[CritterClash] Reward queue rejected: %s", tostring(enqueueResult)))
			table.insert(rewards, resultReward(participant.userId, "Unavailable", 0, 0))
			continue
		end

		local enqueueStatus = enqueueResult :: DataService.EnqueueStatus
		if enqueueStatus == "Accepted" then
			accepted = true
			diagnostics.queued += 1
			setDiagnostics()
			table.insert(rewards, pendingReward)
		elseif enqueueStatus == "ReadOnly" then
			diagnostics.readOnly += 1
			setDiagnostics()
			table.insert(rewards, resultReward(participant.userId, "ReadOnly", 0, 0))
		else
			diagnostics.unavailable += 1
			setDiagnostics()
			table.insert(rewards, resultReward(participant.userId, "Unavailable", 0, 0))
		end
	end

	return table.freeze(rewards)
end

return EconomyService
