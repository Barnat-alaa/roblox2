--!strict

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BotConfig = require(ReplicatedStorage.Shared.Config.BotConfig)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MatchRules = require(ReplicatedStorage.Shared.Simulation.MatchRules)
local Wind = require(ReplicatedStorage.Shared.Simulation.Wind)

local ArenaService = require(script.Parent.ArenaService)
local CharacterService = require(script.Parent.CharacterService)
local EconomyService = require(script.Parent.EconomyService)
local NetworkService = require(script.Parent.NetworkService)
local TelemetryService = require(script.Parent.TelemetryService)
local TerrainService = require(script.Parent.TerrainService)

type Remotes = NetworkService.Remotes
type Outcome = MatchRules.Outcome

type MatchPhase =
	"WaitingForPlayers"
	| "Countdown"
	| "TurnStart"
	| "Aiming"
	| "ProjectileResolving"
	| "EnvironmentalResolution"
	| "TurnEnd"
	| "MatchEnd"
	| "Results"

type ParticipantRecord = {
	userId: number,
	displayName: string,
	isNpc: boolean,
	eliminated: boolean,
	abandoned: boolean,
	returnedToLobby: boolean,
	legalTurnsCompleted: number,
	player: Player?,
	model: Model?,
}

type ResultParticipant = {
	userId: number,
	displayName: string,
	eliminated: boolean,
	isNpc: boolean,
}

type ResultPayload = {
	matchId: string,
	winnerUserId: number,
	isDraw: boolean,
	reason: string,
	participants: { ResultParticipant },
	rewards: { EconomyService.ResultReward },
	serverTime: number,
	expiresAt: number,
}

export type ProjectileLease = {
	matchId: string,
	resolutionToken: number,
}

export type BotTurnContext = {
	matchId: string,
	userId: number,
	turnToken: number,
	roundNumber: number,
	wind: number,
	seed: number,
	deadline: number,
	model: Model,
	targetPlayer: Player,
}

type BotTurnHandler = (context: BotTurnContext) -> ()

export type LifecycleKind = "MatchStarted" | "ReturnedToLobby"

export type LifecycleSnapshot = {
	kind: LifecycleKind,
	matchId: string,
	humanPlayers: { Player },
}

export type LifecycleHandler = (snapshot: LifecycleSnapshot) -> ()

local MATCH_SEED = 2_026_071_3
local MAX_HUMAN_PARTICIPANTS = 2
local COUNTDOWN_SECONDS = 1.5
local TURN_START_SECONDS = 0.65
local TURN_END_SECONDS = 0.55
local CHARACTER_READY_RETRY_SECONDS = 0.25
local MATCH_EVENT_TIME_STEP = 1e-6
local REMATCH_RATE_LIMIT_SECONDS = 0.2
local SERVER_SESSION_IDENTITY = if game.JobId ~= ""
	then game.JobId
	else "studio-" .. HttpService:GenerateGUID(false)

local MatchService = {}

local remotes: Remotes? = nil
local arena: Model? = nil
local phase: MatchPhase = "WaitingForPlayers"
local activeParticipant: ParticipantRecord? = nil
local deadline = 0
local roundNumber = 0
local lastActorUserId: number? = nil
local lastActorWasNpc = false
local currentWind = 0
local matchStartedAt = 0
local transitionToken = 0
local matchSequence = 0
local currentMatchId = ""
local participants: { ParticipantRecord } = {}
local participantByUserId: { [number]: ParticipantRecord } = {}
local resultPayload: ResultPayload? = nil
local resultExpiresAt = 0
local readyByUserId: { [number]: boolean } = {}
local lastRematchRequestAt: { [Player]: number } = {}
local departingUserIds: { [number]: boolean } = {}
local humanDeathConnections: { [Player]: RBXScriptConnection? } = {}
local targetDeathConnection: RBXScriptConnection? = nil
local restartInProgress = false
local pendingResolutionReason: string? = nil
local lastMatchEventTime = 0
local resultEmissionCount = 0
local rematchRestartCount = 0
local botTurnHandler: BotTurnHandler? = nil
local lifecycleHandler: LifecycleHandler? = nil
local characterReadyDeadline = 0
local started = false

local beginNextTurn: () -> ()
local enterWaitingState: () -> ()
local eliminateParticipant: (participant: ParticipantRecord, reason: string, expectedMatchId: string) -> ()
local startMatch: (humanPlayers: { Player }, resetWorld: boolean, suppliedMatchId: string?) -> ()
local startMatchSafely: (humanPlayers: { Player }, resetWorld: boolean, suppliedMatchId: string?) -> boolean

local function nextMatchEventTime(): number
	local current = Workspace:GetServerTimeNow()
	if current <= lastMatchEventTime then
		current = lastMatchEventTime + MATCH_EVENT_TIME_STEP
	end
	lastMatchEventTime = current
	return current
end

local function newMatchId(): string
	matchSequence += 1
	local matchId = string.format("%s-%d", SERVER_SESSION_IDENTITY, matchSequence)
	assert(MatchRules.isValidMatchId(matchId), "generated match ID must satisfy network bounds")
	return matchId
end

local function setDiagnostics()
	local eliminatedCount = 0
	for _, participant in participants do
		if participant.eliminated then
			eliminatedCount += 1
		end
	end

	Workspace:SetAttribute("CritterClashMatchId", currentMatchId)
	Workspace:SetAttribute("CritterClashMatchPhase", phase)
	Workspace:SetAttribute("CritterClashParticipantCount", #participants)
	Workspace:SetAttribute("CritterClashEliminatedCount", eliminatedCount)
	Workspace:SetAttribute("CritterClashResultEmissionCount", resultEmissionCount)
	Workspace:SetAttribute("CritterClashRematchRestartCount", rematchRestartCount)
end

local function emitLifecycle(kind: LifecycleKind, matchId: string, humanPlayers: { Player })
	local handler = lifecycleHandler
	if not handler then
		return
	end

	local roster = table.create(#humanPlayers)
	for _, player in humanPlayers do
		table.insert(roster, player)
	end
	local snapshot = table.freeze({
		kind = kind,
		matchId = matchId,
		humanPlayers = table.freeze(roster),
	}) :: LifecycleSnapshot
	local problem: any = nil
	local succeeded = xpcall(function()
		handler(snapshot)
	end, function(message: any): any
		problem = message
		return message
	end)
	if not succeeded then
		warn(string.format("[CritterClash] Match lifecycle handler failed: %s", tostring(problem)))
	end
end

local function statePayload()
	return {
		matchId = currentMatchId,
		turnToken = transitionToken,
		phase = phase,
		activeUserId = if activeParticipant then activeParticipant.userId else 0,
		deadline = deadline,
		roundNumber = roundNumber,
		wind = currentWind,
		serverTime = Workspace:GetServerTimeNow(),
	}
end

local function broadcastState(target: Player?)
	local currentRemotes = remotes
	if not currentRemotes then
		return
	end

	setDiagnostics()
	if target then
		if target.Parent == Players then
			currentRemotes.matchState:FireClient(target, statePayload())
		end
	else
		currentRemotes.matchState:FireAllClients(statePayload())
	end
end

local function isCurrentTransition(token: number, expectedPhase: MatchPhase): boolean
	return token == transitionToken and phase == expectedPhase
end

local function clearDeathConnections()
	for player, connection in humanDeathConnections do
		if connection then
			connection:Disconnect()
		end
		humanDeathConnections[player] = nil
	end
	if targetDeathConnection then
		targetDeathConnection:Disconnect()
		targetDeathConnection = nil
	end
end

local function participantStates(): { MatchRules.ParticipantState }
	local states: { MatchRules.ParticipantState } = table.create(#participants)
	for index, participant in participants do
		states[index] = {
			userId = participant.userId,
			eliminated = participant.eliminated,
			isNpc = participant.isNpc,
		}
	end
	return states
end

local function connectedByUserId(): { [number]: boolean }
	local connected: { [number]: boolean } = {}
	for _, participant in participants do
		local player = participant.player
		if
			not participant.isNpc
			and not participant.returnedToLobby
			and player ~= nil
			and player.Parent == Players
			and not departingUserIds[player.UserId]
		then
			-- Bind readiness to the exact Player object frozen into this roster. A
			-- reconnect with the same UserId is a spectator until the next boundary.
			connected[participant.userId] = true
		end
	end
	return connected
end

local function requiredHumanUserIds(): { number }
	return MatchRules.requiredHumanUserIds(participantStates(), connectedByUserId())
end

local function resultParticipants(): { ResultParticipant }
	local result: { ResultParticipant } = table.create(#participants)
	for index, participant in participants do
		result[index] = {
			userId = participant.userId,
			displayName = participant.displayName,
			eliminated = participant.eliminated,
			isNpc = participant.isNpc,
		}
	end
	return result
end

local function includesNpcParticipant(): boolean
	for _, participant in participants do
		if participant.isNpc then
			return true
		end
	end
	return false
end

local function completionSnapshot(
	outcome: Outcome,
	finalReason: string,
	completedAt: number
): EconomyService.MatchCompletion
	local mode: EconomyService.MatchMode = "player"
	for _, participant in participants do
		if participant.isNpc then
			mode = "bot"
			break
		end
	end

	local completionParticipants: { EconomyService.CompletionParticipant } =
		table.create(#participants)
	for index, participant in participants do
		local participantOutcome: EconomyService.ParticipantOutcome = if outcome.isDraw
			then "draw"
			else if participant.userId == outcome.winnerUserId then "win" else "loss"
		completionParticipants[index] = table.freeze({
			player = participant.player,
			userId = participant.userId,
			isNpc = participant.isNpc,
			eliminated = participant.eliminated,
			abandoned = participant.abandoned,
			legalTurnsCompleted = participant.legalTurnsCompleted,
			outcome = participantOutcome,
		}) :: EconomyService.CompletionParticipant
	end

	return table.freeze({
		schemaVersion = 1,
		resultId = currentMatchId,
		matchId = currentMatchId,
		mode = mode,
		startedAt = matchStartedAt,
		completedAt = completedAt,
		winnerUserId = outcome.winnerUserId,
		isDraw = outcome.isDraw,
		reason = finalReason,
		economyVersion = EconomyConfig.version,
		participants = table.freeze(completionParticipants),
	}) :: EconomyService.MatchCompletion
end

local function rematchStatusPayload()
	local required = requiredHumanUserIds()
	return {
		matchId = currentMatchId,
		readyUserIds = MatchRules.readyHumanUserIds(required, readyByUserId),
		requiredUserIds = required,
		serverTime = nextMatchEventTime(),
	}
end

local function broadcastRematchStatus(target: Player?)
	local currentRemotes = remotes
	if not currentRemotes or phase ~= "Results" or currentMatchId == "" then
		return
	end

	local payload = rematchStatusPayload()
	if target then
		if target.Parent == Players then
			currentRemotes.matchEvent:FireClient(target, "RematchStatus", payload)
		end
	else
		currentRemotes.matchEvent:FireAllClients("RematchStatus", payload)
	end
end

local function reconcileDeadHumans()
	for _, participant in participants do
		local player = participant.player
		if
			participant.eliminated
			or participant.isNpc
			or not player
			or player.Parent ~= Players
		then
			continue
		end

		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanDeathConnections[player] and humanoid and humanoid.Health <= 0 then
			participant.eliminated = true
			CharacterService.markEliminated(player)
		end
	end
end

local function enterResults(outcome: Outcome, reasonOverride: string?)
	if resultPayload ~= nil or currentMatchId == "" then
		return
	end

	transitionToken += 1
	phase = "MatchEnd"
	activeParticipant = nil
	deadline = 0
	CharacterService.setActivePlayer(nil)
	broadcastState(nil)

	local finalReason = if reasonOverride == "disconnect" and not outcome.isDraw
		then "disconnect"
		else outcome.reason
	resultExpiresAt = Workspace:GetServerTimeNow() + GameConfig.resultsDurationSeconds
	local completedAt = nextMatchEventTime()
	local payload: ResultPayload = {
		matchId = currentMatchId,
		winnerUserId = outcome.winnerUserId,
		isDraw = outcome.isDraw,
		reason = finalReason,
		participants = resultParticipants(),
		rewards = {},
		serverTime = completedAt,
		expiresAt = resultExpiresAt,
	}
	-- Reserve this exact result synchronously before dispatching any asynchronous
	-- profile work. Repeated death/disconnect callbacks can no longer enqueue a
	-- second logical reward for the same match.
	resultPayload = payload
	TelemetryService.emit("match_completed", {
		reason = finalReason,
		versusBot = includesNpcParticipant(),
		durationSeconds = math.clamp(completedAt - matchStartedAt, 0, 7_200),
	})
	local completion = completionSnapshot(outcome, finalReason, completedAt)
	local rewardsQueued, queuedRewards = pcall(EconomyService.enqueueMatchCompletion, completion)
	if rewardsQueued then
		payload.rewards = queuedRewards :: { EconomyService.ResultReward }
	else
		warn(string.format("[CritterClash] Reward enqueue failed: %s", tostring(queuedRewards)))
		local unavailableRewards: { EconomyService.ResultReward } = {}
		for _, participant in completion.participants do
			if not participant.isNpc then
				table.insert(unavailableRewards, {
					userId = participant.userId,
					status = "Unavailable",
					coins = 0,
					experience = 0,
				})
			end
		end
		payload.rewards = unavailableRewards
	end
	resultEmissionCount += 1
	Workspace:SetAttribute("CritterClashWinnerUserId", outcome.winnerUserId)
	Workspace:SetAttribute("CritterClashResultIsDraw", outcome.isDraw)
	setDiagnostics()

	local currentRemotes = remotes
	if currentRemotes then
		currentRemotes.matchEvent:FireAllClients("Result", payload)
	end

	phase = "Results"
	deadline = resultExpiresAt
	broadcastState(nil)
	broadcastRematchStatus(nil)
	local completedMatchId = currentMatchId
	local resultsToken = transitionToken
	task.delay(GameConfig.resultsDurationSeconds, function()
		if
			phase == "Results"
			and currentMatchId == completedMatchId
			and transitionToken == resultsToken
			and resultPayload == payload
		then
			enterWaitingState()
		end
	end)

	if #requiredHumanUserIds() == 0 then
		task.defer(function()
			if phase == "Results" and currentMatchId == completedMatchId then
				enterWaitingState()
			end
		end)
	end
end

local function resolveOutcomeNow(reason: string?): boolean
	if currentMatchId == "" or resultPayload ~= nil then
		return resultPayload ~= nil
	end

	reconcileDeadHumans()
	local outcome = MatchRules.evaluate(participantStates())
	if not outcome then
		return false
	end
	enterResults(outcome, reason)
	return true
end

local function requestOutcomeResolution(reason: string)
	if phase == "ProjectileResolving" or phase == "EnvironmentalResolution" then
		if pendingResolutionReason ~= "disconnect" then
			pendingResolutionReason = reason
		end
		return
	end

	if resolveOutcomeNow(reason) then
		return
	end

	if activeParticipant == nil and phase ~= "WaitingForPlayers" and phase ~= "Results" then
		transitionToken += 1
		local token = transitionToken
		phase = "TurnEnd"
		deadline = 0
		CharacterService.setActivePlayer(nil)
		broadcastState(nil)
		task.delay(TURN_END_SECONDS, function()
			if isCurrentTransition(token, "TurnEnd") then
				beginNextTurn()
			end
		end)
	end
end

eliminateParticipant = function(
	participant: ParticipantRecord,
	reason: string,
	expectedMatchId: string
)
	if
		expectedMatchId ~= currentMatchId
		or currentMatchId == ""
		or participant.eliminated
		or resultPayload ~= nil
	then
		return
	end

	participant.eliminated = true
	local player = participant.player
	if player then
		CharacterService.markEliminated(player)
	end
	if activeParticipant == participant then
		activeParticipant = nil
	end
	setDiagnostics()
	requestOutcomeResolution(reason)
end

local function watchHumanCharacter(player: Player, character: Model)
	local participant = participantByUserId[player.UserId]
	local observedMatchId = currentMatchId
	if
		not participant
		or participant.player ~= player
		or participant.eliminated
		or observedMatchId == ""
	then
		return
	end
	local existing = humanDeathConnections[player]
	if existing then
		existing:Disconnect()
		humanDeathConnections[player] = nil
	end

	task.spawn(function()
		local humanoidInstance = character:WaitForChild("Humanoid", 10)
		if
			currentMatchId ~= observedMatchId
			or participant.eliminated
			or player.Character ~= character
			or not humanoidInstance
			or not humanoidInstance:IsA("Humanoid")
		then
			return
		end

		if humanoidInstance.Health <= 0 then
			eliminateParticipant(participant, "elimination", observedMatchId)
			return
		end
		humanDeathConnections[player] = humanoidInstance.Died:Connect(function()
			eliminateParticipant(participant, "elimination", observedMatchId)
		end)
	end)
end

local function watchBotCritter(target: Model, participant: ParticipantRecord)
	local observedMatchId = currentMatchId
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	assert(humanoid ~= nil, "BotCritter must have a Humanoid")
	if humanoid.Health <= 0 then
		eliminateParticipant(participant, "elimination", observedMatchId)
		return
	end
	targetDeathConnection = humanoid.Died:Connect(function()
		eliminateParticipant(participant, "elimination", observedMatchId)
	end)
end

local function isTurnEligible(participant: ParticipantRecord): boolean
	if participant.eliminated then
		return false
	end
	if participant.isNpc then
		local model = participant.model
		return model ~= nil and model.Parent ~= nil and CharacterService.isModelReadyForTurn(model)
	end

	local player = participant.player
	return player ~= nil
		and player.Parent == Players
		and not departingUserIds[player.UserId]
		and CharacterService.isReadyForTurn(player)
		and humanDeathConnections[player] ~= nil
end

local function turnCandidates(): { ParticipantRecord }
	-- Never advance with a partial living roster. Humans may still be loading and
	-- the physical bot may have lost a required component without firing Died.
	-- The bounded readiness deadline recovers either case instead of silently
	-- granting endless turns to the remaining candidate.
	for _, participant in participants do
		if not participant.eliminated and not isTurnEligible(participant) then
			return {}
		end
	end

	local candidates = {}
	for _, participant in participants do
		if isTurnEligible(participant) then
			table.insert(candidates, participant)
		end
	end
	table.sort(candidates, function(left, right)
		if left.isNpc ~= right.isNpc then
			return not left.isNpc
		end
		return left.userId < right.userId
	end)
	return candidates
end

local function currentCombatantModels(): { Model }
	local models = {}
	local included: { [Model]: boolean } = {}
	for _, participant in participants do
		if participant.eliminated then
			continue
		end
		local model = if participant.isNpc
			then participant.model
			else if participant.player then participant.player.Character else nil
		if
			model
			and model.Parent ~= nil
			and CharacterService.isCombatantModel(model)
			and not included[model]
		then
			included[model] = true
			table.insert(models, model)
		end
	end
	return models
end

local function settleEnvironmentThenEndTurn(settlementModels: { Model }, expectedMatchId: string)
	transitionToken += 1
	local token = transitionToken
	phase = "EnvironmentalResolution"
	activeParticipant = nil
	deadline = 0
	CharacterService.setActivePlayer(nil)
	broadcastState(nil)
	task.spawn(function()
		local settlement = CharacterService.awaitEnvironmentSettled(settlementModels, function()
			return currentMatchId == expectedMatchId
				and isCurrentTransition(token, "EnvironmentalResolution")
		end)
		if
			not settlement.completed or not isCurrentTransition(token, "EnvironmentalResolution")
		then
			return
		end

		local resolutionReason = pendingResolutionReason
		pendingResolutionReason = nil
		if resolveOutcomeNow(resolutionReason) then
			return
		end

		phase = "TurnEnd"
		broadcastState(nil)
		task.delay(TURN_END_SECONDS, function()
			if isCurrentTransition(token, "TurnEnd") then
				beginNextTurn()
			end
		end)
	end)
end

local function targetPlayerForBot(): Player?
	for _, participant in participants do
		local player = participant.player
		if
			not participant.isNpc
			and not participant.eliminated
			and player
			and isTurnEligible(participant)
		then
			return player
		end
	end
	return nil
end

beginNextTurn = function()
	if currentMatchId == "" or phase == "Results" or phase == "MatchEnd" then
		return
	end
	if resolveOutcomeNow(pendingResolutionReason) then
		pendingResolutionReason = nil
		return
	end
	pendingResolutionReason = nil

	local candidates = turnCandidates()
	if #candidates == 0 then
		local currentTime = Workspace:GetServerTimeNow()
		if characterReadyDeadline <= 0 then
			characterReadyDeadline = currentTime + GameConfig.characterReadyTimeoutSeconds
		end
		if currentTime >= characterReadyDeadline then
			warn("[CritterClash] Character readiness timed out; returning to waiting state")
			enterWaitingState()
			return
		end
		transitionToken += 1
		local token = transitionToken
		phase = "Countdown"
		activeParticipant = nil
		deadline = 0
		CharacterService.setActivePlayer(nil)
		broadcastState(nil)
		task.delay(CHARACTER_READY_RETRY_SECONDS, function()
			if isCurrentTransition(token, "Countdown") and activeParticipant == nil then
				beginNextTurn()
			end
		end)
		return
	end
	characterReadyDeadline = 0

	local selectedIndex = 1
	local wrappedRoster = lastActorUserId ~= nil
	if lastActorUserId ~= nil and not lastActorWasNpc then
		for index, candidate in candidates do
			if candidate.isNpc or candidate.userId > lastActorUserId then
				selectedIndex = index
				wrappedRoster = false
				break
			end
		end
	end
	local selectedParticipant = candidates[selectedIndex]
	if lastActorUserId == nil or wrappedRoster then
		roundNumber += 1
		currentWind = Wind.forRound(MATCH_SEED + matchSequence, roundNumber - 1)
	end

	transitionToken += 1
	local token = transitionToken
	activeParticipant = selectedParticipant
	lastActorUserId = selectedParticipant.userId
	lastActorWasNpc = selectedParticipant.isNpc
	phase = "TurnStart"
	deadline = 0
	-- TurnStart is presentation-only. Movement begins with the timed Aiming phase,
	-- preventing a free movement window before the authoritative deadline exists.
	CharacterService.setActivePlayer(nil)
	broadcastState(nil)

	task.delay(TURN_START_SECONDS, function()
		if
			not isCurrentTransition(token, "TurnStart")
			or activeParticipant ~= selectedParticipant
		then
			return
		end
		if not isTurnEligible(selectedParticipant) then
			transitionToken += 1
			local recoveryToken = transitionToken
			phase = "TurnEnd"
			activeParticipant = nil
			deadline = 0
			CharacterService.setActivePlayer(nil)
			broadcastState(nil)
			task.delay(TURN_END_SECONDS, function()
				if isCurrentTransition(recoveryToken, "TurnEnd") then
					beginNextTurn()
				end
			end)
			return
		end
		phase = "Aiming"
		deadline = Workspace:GetServerTimeNow() + GameConfig.turnDurationSeconds
		CharacterService.setActivePlayer(selectedParticipant.player, token)
		broadcastState(nil)

		if selectedParticipant.isNpc then
			local handler = botTurnHandler
			local model = selectedParticipant.model
			local targetPlayer = targetPlayerForBot()
			if not handler or not model or not targetPlayer then
				warn("[CritterClash] Bot turn could not be scheduled")
				return
			end
			local seed = bit32.band(
				bit32.bxor(
					bit32.band(matchSequence, 0x7FFFFFFF),
					bit32.lshift(bit32.band(roundNumber, 0x7FFF), 12),
					0x4F1BBCDC
				),
				0x7FFFFFFF
			)
			local context: BotTurnContext = table.freeze({
				matchId = currentMatchId,
				userId = selectedParticipant.userId,
				turnToken = token,
				roundNumber = roundNumber,
				wind = currentWind,
				seed = seed,
				deadline = deadline,
				model = model,
				targetPlayer = targetPlayer,
			}) :: BotTurnContext
			task.spawn(function()
				local handleError: any = nil
				local handled = xpcall(function()
					handler(context)
				end, function(problem: any): any
					handleError = problem
					return problem
				end)
				if not handled then
					warn(
						string.format(
							"[CritterClash] Bot turn handler failed: %s",
							tostring(handleError)
						)
					)
				end
			end)
		end
	end)
end

local function sortedConnectedPlayers(players: { Player }): { Player }
	local result = {}
	local included: { [Player]: boolean } = {}
	for _, player in players do
		if
			player.Parent == Players
			and not departingUserIds[player.UserId]
			and not included[player]
		then
			included[player] = true
			table.insert(result, player)
		end
	end
	table.sort(result, function(left, right)
		return left.UserId < right.UserId
	end)
	while #result > MAX_HUMAN_PARTICIPANTS do
		table.remove(result)
	end
	return result
end

startMatch = function(humanPlayers: { Player }, resetWorld: boolean, suppliedMatchId: string?)
	local currentArena = arena
	assert(currentArena ~= nil, "MatchService arena must exist")

	local humans = sortedConnectedPlayers(humanPlayers)
	if #humans == 0 then
		enterWaitingState()
		return
	end

	clearDeathConnections()
	transitionToken += 1
	currentMatchId = suppliedMatchId or newMatchId()
	assert(MatchRules.isValidMatchId(currentMatchId), "match ID must satisfy network bounds")
	matchStartedAt = Workspace:GetServerTimeNow()
	resultPayload = nil
	resultExpiresAt = 0
	table.clear(readyByUserId)
	table.clear(participants)
	table.clear(participantByUserId)
	restartInProgress = false
	pendingResolutionReason = nil
	activeParticipant = nil
	deadline = 0
	roundNumber = 0
	lastActorUserId = nil
	lastActorWasNpc = false
	currentWind = 0
	characterReadyDeadline = Workspace:GetServerTimeNow() + GameConfig.characterReadyTimeoutSeconds
	Workspace:SetAttribute("CritterClashWinnerUserId", nil)
	Workspace:SetAttribute("CritterClashResultIsDraw", nil)

	-- Loading participants are synchronously parked before authoritative collision
	-- is rebuilt; CharacterService keeps them ineligible until a fresh character arrives.
	CharacterService.configureMatch(humans, resetWorld)
	local includeBot = #humans == 1
	CharacterService.setNpcCombatant(nil)
	ArenaService.resetBotCritter(currentArena, false)
	if resetWorld then
		TerrainService.reset()
	end
	local target = ArenaService.resetBotCritter(currentArena, includeBot)
	CharacterService.setNpcCombatant(target)

	for _, player in humans do
		local participant: ParticipantRecord = {
			userId = player.UserId,
			displayName = player.DisplayName,
			isNpc = false,
			eliminated = false,
			abandoned = false,
			returnedToLobby = false,
			legalTurnsCompleted = 0,
			player = player,
			model = nil,
		}
		table.insert(participants, participant)
		participantByUserId[participant.userId] = participant
	end
	if target then
		local humanoid = target:FindFirstChildOfClass("Humanoid")
		local targetParticipant: ParticipantRecord = {
			userId = BotConfig.userId,
			displayName = if humanoid then humanoid.DisplayName else BotConfig.displayName,
			isNpc = true,
			eliminated = false,
			abandoned = false,
			returnedToLobby = false,
			legalTurnsCompleted = 0,
			player = nil,
			model = target,
		}
		table.insert(participants, targetParticipant)
		participantByUserId[targetParticipant.userId] = targetParticipant
		watchBotCritter(target, targetParticipant)
	end

	if not resetWorld then
		for _, player in humans do
			local character = player.Character
			if character then
				watchHumanCharacter(player, character)
			end
		end
	end

	phase = "Countdown"
	deadline = Workspace:GetServerTimeNow() + COUNTDOWN_SECONDS
	CharacterService.setActivePlayer(nil)
	broadcastState(nil)
	emitLifecycle("MatchStarted", currentMatchId, humans)
	if suppliedMatchId ~= nil then
		TelemetryService.emit("match_started", {
			mode = "Rematch",
			versusBot = target ~= nil,
			participantCount = #participants,
		})
	end
	local token = transitionToken
	task.delay(COUNTDOWN_SECONDS, function()
		if isCurrentTransition(token, "Countdown") then
			beginNextTurn()
		end
	end)
end

startMatchSafely = function(humanPlayers: { Player }, resetWorld: boolean, suppliedMatchId: string?)
	local startError = "unknown match setup error"
	local succeeded = xpcall(function()
		startMatch(humanPlayers, resetWorld, suppliedMatchId)
	end, function(message)
		startError = tostring(message)
		return message
	end)
	if not succeeded then
		warn(string.format("[CritterClash] Match setup failed: %s", startError))
		enterWaitingState()
	end
	return succeeded
end

enterWaitingState = function()
	local completedMatchId = currentMatchId
	local completedHumans: { Player } = {}
	for _, participant in participants do
		local player = participant.player
		if not participant.isNpc and player then
			table.insert(completedHumans, player)
		end
	end
	local shouldResetWorld = currentMatchId ~= ""
	transitionToken += 1
	clearDeathConnections()
	phase = "WaitingForPlayers"
	activeParticipant = nil
	deadline = 0
	roundNumber = 0
	lastActorUserId = nil
	lastActorWasNpc = false
	currentWind = 0
	currentMatchId = ""
	matchStartedAt = 0
	resultExpiresAt = 0
	characterReadyDeadline = 0
	Workspace:SetAttribute("CritterClashWinnerUserId", nil)
	Workspace:SetAttribute("CritterClashResultIsDraw", nil)
	resultPayload = nil
	restartInProgress = false
	pendingResolutionReason = nil
	table.clear(participants)
	table.clear(participantByUserId)
	table.clear(readyByUserId)
	CharacterService.setActivePlayer(nil)
	CharacterService.configureMatch({}, false)
	CharacterService.setNpcCombatant(nil)
	local currentArena = arena
	if currentArena then
		ArenaService.resetBotCritter(currentArena, false)
	end
	if shouldResetWorld then
		local resetError = "unknown reset error"
		local resetSucceeded = xpcall(function()
			TerrainService.reset()
		end, function(message)
			resetError = tostring(message)
			return message
		end)
		if not resetSucceeded then
			warn(
				string.format(
					"[CritterClash] Waiting-state terrain reset failed: %s",
					tostring(resetError)
				)
			)
		end
	end
	broadcastState(nil)
	emitLifecycle("ReturnedToLobby", completedMatchId, completedHumans)
end

local function connectedCurrentHumans(): { Player }
	local humans = {}
	for _, participant in participants do
		local player = participant.player
		if
			not participant.isNpc
			and not participant.returnedToLobby
			and player
			and player.Parent == Players
		then
			table.insert(humans, player)
		end
	end
	return sortedConnectedPlayers(humans)
end

local function beginRematch()
	if restartInProgress or phase ~= "Results" or currentMatchId == "" then
		return
	end
	local required = requiredHumanUserIds()
	if not MatchRules.isUnanimousReady(required, readyByUserId) then
		return
	end

	-- Rematches may only retain connected members of the completed human roster.
	-- Spectators and queued players are admitted exclusively by LobbyService.
	local humans = connectedCurrentHumans()
	if #humans == 0 then
		enterWaitingState()
		return
	end

	restartInProgress = true
	local completedMatchId = currentMatchId
	-- Reserve the transition immediately so a Results-expiry callback cannot race
	-- an already accepted unanimous rematch before the deferred reset begins.
	transitionToken += 1
	local rematchReservationToken = transitionToken
	local nextMatchId = newMatchId()
	local currentRemotes = remotes
	if currentRemotes then
		currentRemotes.matchEvent:FireAllClients("MatchRestarting", {
			matchId = completedMatchId,
			nextMatchId = nextMatchId,
			serverTime = nextMatchEventTime(),
		})
	end
	rematchRestartCount += 1
	TelemetryService.emit("rematch_selected", {
		versusBot = includesNpcParticipant(),
	})
	setDiagnostics()

	task.defer(function()
		if
			phase ~= "Results"
			or currentMatchId ~= completedMatchId
			or transitionToken ~= rematchReservationToken
		then
			return
		end
		startMatchSafely(humans, true, nextMatchId)
	end)
end

local function validateRematchRequest(request: unknown): (string?, boolean?)
	if typeof(request) ~= "table" then
		return nil, nil
	end
	local requestTable = request :: { [any]: any }
	local fieldCount = 0
	for key in requestTable do
		if key ~= "matchId" and key ~= "ready" then
			return nil, nil
		end
		fieldCount += 1
	end
	if fieldCount ~= 2 then
		return nil, nil
	end

	local matchId = requestTable.matchId
	local ready = requestTable.ready
	if not MatchRules.isValidMatchId(matchId) or typeof(ready) ~= "boolean" then
		return nil, nil
	end
	return matchId :: string, ready :: boolean
end

local function onRematchRequested(player: Player, request: unknown)
	local now = os.clock()
	local previous = lastRematchRequestAt[player]
	if previous and now - previous < REMATCH_RATE_LIMIT_SECONDS then
		broadcastRematchStatus(player)
		return
	end
	lastRematchRequestAt[player] = now

	if phase ~= "Results" or restartInProgress then
		return
	end
	local requestedMatchId, requestedReady = validateRematchRequest(request)
	if not requestedMatchId or requestedReady == nil or requestedMatchId ~= currentMatchId then
		return
	end

	local participant = participantByUserId[player.UserId]
	if
		not participant
		or participant.isNpc
		or participant.player ~= player
		or player.Parent ~= Players
	then
		return
	end

	local requiredSet: { [number]: boolean } = {}
	for _, userId in requiredHumanUserIds() do
		requiredSet[userId] = true
	end
	if not requiredSet[player.UserId] then
		return
	end

	if readyByUserId[player.UserId] == requestedReady then
		broadcastRematchStatus(player)
		return
	end
	readyByUserId[player.UserId] = requestedReady
	broadcastRematchStatus(nil)
	beginRematch()
end

local function observePlayer(player: Player)
	departingUserIds[player.UserId] = nil
	player.CharacterAdded:Connect(function(character)
		watchHumanCharacter(player, character)
	end)

	local participant = participantByUserId[player.UserId]
	if not participant or participant.player ~= player then
		CharacterService.setSpectator(player)
	elseif player.Character then
		watchHumanCharacter(player, player.Character)
	end

	task.delay(0.25, function()
		if player.Parent ~= Players then
			return
		end
		broadcastState(player)
		local currentRemotes = remotes
		local currentResult = resultPayload
		if currentRemotes and currentResult and phase == "Results" then
			currentRemotes.matchEvent:FireClient(player, "Result", currentResult)
			broadcastRematchStatus(player)
		end
	end)
end

function MatchService.start(networkRemotes: Remotes, matchArena: Model)
	assert(not started, "MatchService may only be started once")
	started = true
	remotes = networkRemotes
	arena = matchArena

	networkRemotes.requestRematch.OnServerEvent:Connect(function(player, request)
		onRematchRequested(player, request)
	end)

	for _, player in Players:GetPlayers() do
		observePlayer(player)
	end
	Players.PlayerAdded:Connect(observePlayer)

	Players.PlayerRemoving:Connect(function(player)
		departingUserIds[player.UserId] = true
		lastRematchRequestAt[player] = nil
		readyByUserId[player.UserId] = nil
		local connection = humanDeathConnections[player]
		if connection then
			connection:Disconnect()
			humanDeathConnections[player] = nil
		end

		local participant = participantByUserId[player.UserId]
		if participant and participant.player == player and currentMatchId ~= "" then
			if phase ~= "Results" then
				participant.abandoned = true
				eliminateParticipant(participant, "disconnect", currentMatchId)
			end
		end
		local observedMatchId = currentMatchId
		task.defer(function()
			if phase == "Results" and currentMatchId == observedMatchId then
				local required = requiredHumanUserIds()
				if #required == 0 then
					enterWaitingState()
				else
					broadcastRematchStatus(nil)
					beginRematch()
				end
			end
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			if
				activeParticipant
				and phase == "Aiming"
				and Workspace:GetServerTimeNow() >= deadline
			then
				settleEnvironmentThenEndTurn(currentCombatantModels(), currentMatchId)
			end
		end
	end)

	enterWaitingState()
end

-- LobbyService is the only normal caller of this admission boundary. The roster
-- is validated without substitution: invalid, duplicate, or disconnected
-- players never get silently replaced by server spectators.
function MatchService.tryStartMatch(humanPlayers: { Player }): (boolean, string?)
	if not started then
		return false, "service_not_started"
	end
	if phase ~= "WaitingForPlayers" or currentMatchId ~= "" or restartInProgress then
		return false, "match_busy"
	end
	if #humanPlayers < 1 or #humanPlayers > MAX_HUMAN_PARTICIPANTS then
		return false, "invalid_roster"
	end

	local included: { [Player]: boolean } = {}
	local includedUserIds: { [number]: boolean } = {}
	local roster: { Player } = {}
	for _, player in humanPlayers do
		if
			player.Parent ~= Players
			or departingUserIds[player.UserId]
			or included[player]
			or includedUserIds[player.UserId]
		then
			return false, "invalid_roster"
		end
		included[player] = true
		includedUserIds[player.UserId] = true
		table.insert(roster, player)
	end

	if not startMatchSafely(roster, false, nil) then
		return false, "setup_failed"
	end
	return true, nil
end

function MatchService.isAvailableForLobby(): boolean
	return started
		and phase == "WaitingForPlayers"
		and currentMatchId == ""
		and not restartInProgress
end

function MatchService.isPlayerInCurrentMatch(player: Player): boolean
	if currentMatchId == "" then
		return false
	end
	local participant = participantByUserId[player.UserId]
	return participant ~= nil
		and not participant.isNpc
		and not participant.returnedToLobby
		and participant.player == player
end

-- Results membership and rematch consent are separate from the immutable result
-- payload. Opting out leaves rewards/results intact while excluding the player
-- from the next roster.
function MatchService.returnPlayerToLobby(player: Player): (boolean, string?)
	if phase ~= "Results" or currentMatchId == "" then
		return false, "not_in_results"
	end
	if restartInProgress then
		return false, "rematch_starting"
	end
	local participant = participantByUserId[player.UserId]
	if
		not participant
		or participant.isNpc
		or participant.player ~= player
		or player.Parent ~= Players
	then
		return false, "not_a_participant"
	end
	if participant.returnedToLobby then
		return true, nil
	end

	participant.returnedToLobby = true
	readyByUserId[player.UserId] = nil
	CharacterService.setSpectator(player)
	broadcastRematchStatus(nil)
	if #requiredHumanUserIds() == 0 then
		enterWaitingState()
	else
		beginRematch()
	end
	return true, nil
end

function MatchService.setLifecycleHandler(handler: LifecycleHandler)
	assert(lifecycleHandler == nil, "match lifecycle handler may only be registered once")
	lifecycleHandler = handler
	if currentMatchId == "" then
		emitLifecycle("ReturnedToLobby", "", {})
	else
		emitLifecycle("MatchStarted", currentMatchId, connectedCurrentHumans())
	end
end

function MatchService.canFire(player: Player): (boolean, string?)
	if phase ~= "Aiming" then
		return false, "match_not_aiming"
	end
	local active = activeParticipant
	if not active or active.isNpc or active.player ~= player then
		return false, "not_your_turn"
	end
	if Workspace:GetServerTimeNow() >= deadline then
		return false, "turn_expired"
	end

	local participant = participantByUserId[player.UserId]
	if
		not participant
		or participant.player ~= player
		or participant.eliminated
		or not CharacterService.isEligible(player)
	then
		return false, "player_not_alive"
	end

	return true, nil
end

function MatchService.canMove(
	player: Player,
	expectedMatchId: string,
	expectedTurnToken: number
): (boolean, string?)
	if expectedMatchId ~= currentMatchId or currentMatchId == "" then
		return false, "stale_match"
	end
	if phase ~= "Aiming" then
		return false, "movement_locked"
	end
	if expectedTurnToken ~= transitionToken then
		return false, "stale_turn"
	end
	if Workspace:GetServerTimeNow() >= deadline then
		return false, "turn_expired"
	end
	local participant = activeParticipant
	if
		not participant
		or participant.isNpc
		or participant.player ~= player
		or participant.eliminated
		or not CharacterService.isEligible(player)
	then
		return false, "not_your_turn"
	end
	return true, nil
end

local function enterProjectileResolution(): ProjectileLease
	local participant = activeParticipant
	if participant then
		participant.legalTurnsCompleted += 1
	end
	transitionToken += 1
	phase = "ProjectileResolving"
	deadline = 0
	pendingResolutionReason = nil
	CharacterService.setActivePlayer(nil)
	broadcastState(nil)
	return table.freeze({
		matchId = currentMatchId,
		resolutionToken = transitionToken,
	}) :: ProjectileLease
end

function MatchService.beginProjectile(player: Player): (boolean, string?, ProjectileLease?)
	local allowed, reason = MatchService.canFire(player)
	if not allowed then
		return false, reason, nil
	end

	return true, nil, enterProjectileResolution()
end

function MatchService.beginBotProjectile(
	userId: number,
	expectedMatchId: string,
	expectedTurnToken: number,
	model: Model
): (boolean, string?, ProjectileLease?)
	if expectedMatchId ~= currentMatchId or currentMatchId == "" then
		return false, "stale_match", nil
	end
	if phase ~= "Aiming" then
		return false, "match_not_aiming", nil
	end
	if expectedTurnToken ~= transitionToken then
		return false, "stale_turn", nil
	end
	if Workspace:GetServerTimeNow() >= deadline then
		return false, "turn_expired", nil
	end

	local participant = activeParticipant
	if
		not participant
		or not participant.isNpc
		or participant.userId ~= userId
		or participant.model ~= model
		or participant.eliminated
		or not isTurnEligible(participant)
	then
		return false, "bot_not_active", nil
	end

	return true, nil, enterProjectileResolution()
end

function MatchService.isProjectileLeaseActive(lease: ProjectileLease): boolean
	return phase == "ProjectileResolving"
		and currentMatchId ~= ""
		and lease.matchId == currentMatchId
		and lease.resolutionToken == transitionToken
end

function MatchService.getProjectileDamageTargets(lease: ProjectileLease): { Model }
	if not MatchService.isProjectileLeaseActive(lease) then
		return {}
	end
	return currentCombatantModels()
end

function MatchService.finishProjectile(lease: ProjectileLease): boolean
	if not MatchService.isProjectileLeaseActive(lease) then
		return false
	end

	settleEnvironmentThenEndTurn(MatchService.getProjectileDamageTargets(lease), lease.matchId)
	return true
end

function MatchService.setBotTurnHandler(handler: BotTurnHandler)
	assert(botTurnHandler == nil, "bot turn handler may only be registered once")
	botTurnHandler = handler
end

function MatchService.getWind(): number
	return currentWind
end

function MatchService.getRoundNumber(): number
	return roundNumber
end

return MatchService
