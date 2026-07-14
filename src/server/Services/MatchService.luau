--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MatchRules = require(ReplicatedStorage.Shared.Simulation.MatchRules)
local Wind = require(ReplicatedStorage.Shared.Simulation.Wind)

local ArenaService = require(script.Parent.ArenaService)
local CharacterService = require(script.Parent.CharacterService)
local NetworkService = require(script.Parent.NetworkService)
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
	serverTime: number,
}

local MATCH_SEED = 2_026_071_3
local NPC_USER_ID = 0
local MAX_HUMAN_PARTICIPANTS = 2
local INITIAL_MATCH_DELAY_SECONDS = 1
local COUNTDOWN_SECONDS = 1.5
local TURN_START_SECONDS = 0.65
local TURN_END_SECONDS = 0.55
local ENVIRONMENT_SETTLE_SECONDS = 0.8
local CHARACTER_READY_RETRY_SECONDS = 0.25
local MATCH_EVENT_TIME_STEP = 1e-6
local REMATCH_RATE_LIMIT_SECONDS = 0.2

local MatchService = {}

local remotes: Remotes? = nil
local arena: Model? = nil
local phase: MatchPhase = "WaitingForPlayers"
local activePlayer: Player? = nil
local deadline = 0
local roundNumber = 0
local lastActorUserId = 0
local currentWind = 0
local transitionToken = 0
local matchSequence = 0
local currentMatchId = ""
local participants: { ParticipantRecord } = {}
local participantByUserId: { [number]: ParticipantRecord } = {}
local resultPayload: ResultPayload? = nil
local readyByUserId: { [number]: boolean } = {}
local lastRematchRequestAt: { [Player]: number } = {}
local departingUserIds: { [number]: boolean } = {}
local humanDeathConnections: { [Player]: RBXScriptConnection? } = {}
local targetDeathConnection: RBXScriptConnection? = nil
local waitingStartScheduled = false
local restartInProgress = false
local pendingResolutionReason: string? = nil
local lastMatchEventTime = 0
local resultEmissionCount = 0
local rematchRestartCount = 0
local started = false

local beginNextTurn: () -> ()
local enterWaitingState: () -> ()
local eliminateParticipant: (participant: ParticipantRecord, reason: string, expectedMatchId: string) -> ()
local scheduleMatchIfNeeded: () -> ()
local startMatch: (humanPlayers: { Player }, resetWorld: boolean, suppliedMatchId: string?) -> ()

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
	local serverIdentity = if game.JobId ~= "" then game.JobId else "studio"
	local matchId = string.format("%s-%d", serverIdentity, matchSequence)
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

local function statePayload()
	return {
		phase = phase,
		activeUserId = if activePlayer then activePlayer.UserId else 0,
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
	activePlayer = nil
	deadline = 0
	CharacterService.setActivePlayer(nil)
	broadcastState(nil)

	local finalReason = if reasonOverride == "disconnect" and not outcome.isDraw
		then "disconnect"
		else outcome.reason
	local payload: ResultPayload = {
		matchId = currentMatchId,
		winnerUserId = outcome.winnerUserId,
		isDraw = outcome.isDraw,
		reason = finalReason,
		participants = resultParticipants(),
		serverTime = nextMatchEventTime(),
	}
	resultPayload = payload
	resultEmissionCount += 1
	Workspace:SetAttribute("CritterClashWinnerUserId", outcome.winnerUserId)
	Workspace:SetAttribute("CritterClashResultIsDraw", outcome.isDraw)
	setDiagnostics()

	local currentRemotes = remotes
	if currentRemotes then
		currentRemotes.matchEvent:FireAllClients("Result", payload)
	end

	phase = "Results"
	broadcastState(nil)
	broadcastRematchStatus(nil)

	if #requiredHumanUserIds() == 0 then
		local completedMatchId = currentMatchId
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

	if activePlayer == nil and phase ~= "WaitingForPlayers" and phase ~= "Results" then
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
		if activePlayer == player then
			activePlayer = nil
		end
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

local function watchTrainingTarget(target: Model, participant: ParticipantRecord)
	local observedMatchId = currentMatchId
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	assert(humanoid ~= nil, "TrainingTarget must have a Humanoid")
	if humanoid.Health <= 0 then
		eliminateParticipant(participant, "elimination", observedMatchId)
		return
	end
	targetDeathConnection = humanoid.Died:Connect(function()
		eliminateParticipant(participant, "elimination", observedMatchId)
	end)
end

local function humanTurnCandidates(): { Player }
	local candidates = {}
	for _, participant in participants do
		local player = participant.player
		if
			not participant.isNpc
			and not participant.eliminated
			and player ~= nil
			and player.Parent == Players
			and not departingUserIds[player.UserId]
			and CharacterService.isEligible(player)
			and humanDeathConnections[player] ~= nil
		then
			table.insert(candidates, player)
		end
	end
	table.sort(candidates, function(left, right)
		return left.UserId < right.UserId
	end)
	return candidates
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

	local candidates = humanTurnCandidates()
	if #candidates == 0 then
		transitionToken += 1
		local token = transitionToken
		phase = "Countdown"
		activePlayer = nil
		deadline = 0
		CharacterService.setActivePlayer(nil)
		broadcastState(nil)
		task.delay(CHARACTER_READY_RETRY_SECONDS, function()
			if isCurrentTransition(token, "Countdown") and activePlayer == nil then
				beginNextTurn()
			end
		end)
		return
	end

	local selectedIndex = 1
	for index, candidate in candidates do
		if candidate.UserId > lastActorUserId then
			selectedIndex = index
			break
		end
	end
	local selectedPlayer = candidates[selectedIndex]
	local wrappedRoster = lastActorUserId ~= 0 and selectedPlayer.UserId <= lastActorUserId
	if roundNumber == 0 or wrappedRoster then
		roundNumber += 1
		currentWind = Wind.forRound(MATCH_SEED + matchSequence, roundNumber - 1)
	end

	transitionToken += 1
	local token = transitionToken
	activePlayer = selectedPlayer
	lastActorUserId = selectedPlayer.UserId
	phase = "TurnStart"
	deadline = 0
	CharacterService.setActivePlayer(selectedPlayer)
	broadcastState(nil)

	task.delay(TURN_START_SECONDS, function()
		if not isCurrentTransition(token, "TurnStart") or activePlayer ~= selectedPlayer then
			return
		end
		if not CharacterService.isEligible(selectedPlayer) then
			transitionToken += 1
			local recoveryToken = transitionToken
			phase = "TurnEnd"
			activePlayer = nil
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
		broadcastState(nil)
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
	resultPayload = nil
	table.clear(readyByUserId)
	table.clear(participants)
	table.clear(participantByUserId)
	restartInProgress = false
	pendingResolutionReason = nil
	activePlayer = nil
	deadline = 0
	roundNumber = 0
	lastActorUserId = 0
	currentWind = 0
	Workspace:SetAttribute("CritterClashWinnerUserId", nil)
	Workspace:SetAttribute("CritterClashResultIsDraw", nil)

	-- Loading participants are synchronously parked before authoritative collision
	-- is rebuilt; CharacterService keeps them ineligible until a fresh character arrives.
	CharacterService.configureMatch(humans, resetWorld)
	local includeTrainingTarget = #humans == 1
	local target = ArenaService.resetTrainingTarget(currentArena, includeTrainingTarget)
	if resetWorld then
		TerrainService.reset()
	end

	for _, player in humans do
		local participant: ParticipantRecord = {
			userId = player.UserId,
			displayName = player.DisplayName,
			isNpc = false,
			eliminated = false,
			player = player,
			model = nil,
		}
		table.insert(participants, participant)
		participantByUserId[participant.userId] = participant
	end
	if target then
		local humanoid = target:FindFirstChildOfClass("Humanoid")
		local targetParticipant: ParticipantRecord = {
			userId = NPC_USER_ID,
			displayName = if humanoid then humanoid.DisplayName else "Training Critter",
			isNpc = true,
			eliminated = false,
			player = nil,
			model = target,
		}
		table.insert(participants, targetParticipant)
		participantByUserId[targetParticipant.userId] = targetParticipant
		watchTrainingTarget(target, targetParticipant)
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
	local token = transitionToken
	task.delay(COUNTDOWN_SECONDS, function()
		if isCurrentTransition(token, "Countdown") then
			beginNextTurn()
		end
	end)
end

enterWaitingState = function()
	local shouldResetWorld = currentMatchId ~= ""
	transitionToken += 1
	clearDeathConnections()
	phase = "WaitingForPlayers"
	activePlayer = nil
	deadline = 0
	roundNumber = 0
	lastActorUserId = 0
	currentWind = 0
	currentMatchId = ""
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
	local currentArena = arena
	if currentArena then
		ArenaService.resetTrainingTarget(currentArena, false)
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
	task.defer(scheduleMatchIfNeeded)
end

scheduleMatchIfNeeded = function()
	if phase ~= "WaitingForPlayers" or currentMatchId ~= "" or waitingStartScheduled then
		return
	end
	if #Players:GetPlayers() == 0 then
		return
	end

	waitingStartScheduled = true
	task.delay(INITIAL_MATCH_DELAY_SECONDS, function()
		waitingStartScheduled = false
		if phase ~= "WaitingForPlayers" or currentMatchId ~= "" then
			return
		end
		startMatch(Players:GetPlayers(), false, nil)
	end)
end

local function connectedCurrentHumans(): { Player }
	local humans = {}
	for _, participant in participants do
		local player = participant.player
		if not participant.isNpc and player and player.Parent == Players then
			table.insert(humans, player)
		end
	end
	return sortedConnectedPlayers(humans)
end

local function nextMatchHumans(): { Player }
	local humans = connectedCurrentHumans()
	local included: { [Player]: boolean } = {}
	for _, player in humans do
		included[player] = true
	end

	local waitingPlayers = sortedConnectedPlayers(Players:GetPlayers())
	for _, player in waitingPlayers do
		if #humans >= MAX_HUMAN_PARTICIPANTS then
			break
		end
		if not included[player] then
			included[player] = true
			table.insert(humans, player)
		end
	end
	return humans
end

local function beginRematch()
	if restartInProgress or phase ~= "Results" or currentMatchId == "" then
		return
	end
	local required = requiredHumanUserIds()
	if not MatchRules.isUnanimousReady(required, readyByUserId) then
		return
	end

	local humans = nextMatchHumans()
	if #humans == 0 then
		enterWaitingState()
		return
	end

	restartInProgress = true
	local completedMatchId = currentMatchId
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
	setDiagnostics()

	task.defer(function()
		if phase ~= "Results" or currentMatchId ~= completedMatchId then
			return
		end
		local resetError = "unknown reset error"
		local resetSucceeded = xpcall(function()
			startMatch(humans, true, nextMatchId)
		end, function(message)
			resetError = tostring(message)
			return message
		end)
		if not resetSucceeded then
			warn(string.format("[CritterClash] Rematch reset failed: %s", tostring(resetError)))
			enterWaitingState()
		end
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
		task.defer(scheduleMatchIfNeeded)
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
		scheduleMatchIfNeeded()
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
			else
				scheduleMatchIfNeeded()
			end
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			if phase == "WaitingForPlayers" then
				scheduleMatchIfNeeded()
			elseif
				activePlayer
				and phase == "Aiming"
				and Workspace:GetServerTimeNow() >= deadline
			then
				transitionToken += 1
				local token = transitionToken
				phase = "TurnEnd"
				activePlayer = nil
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
	end)

	enterWaitingState()
end

function MatchService.canFire(player: Player): (boolean, string?)
	if phase ~= "Aiming" then
		return false, "match_not_aiming"
	end
	if activePlayer ~= player then
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

function MatchService.beginProjectile(player: Player): (boolean, string?)
	local allowed, reason = MatchService.canFire(player)
	if not allowed then
		return false, reason
	end

	transitionToken += 1
	phase = "ProjectileResolving"
	deadline = 0
	pendingResolutionReason = nil
	CharacterService.setActivePlayer(nil)
	broadcastState(nil)
	return true, nil
end

function MatchService.finishProjectile()
	if phase ~= "ProjectileResolving" then
		return
	end

	transitionToken += 1
	local token = transitionToken
	phase = "EnvironmentalResolution"
	broadcastState(nil)
	task.delay(ENVIRONMENT_SETTLE_SECONDS, function()
		if not isCurrentTransition(token, "EnvironmentalResolution") then
			return
		end

		local resolutionReason = pendingResolutionReason
		pendingResolutionReason = nil
		if resolveOutcomeNow(resolutionReason) then
			return
		end

		phase = "TurnEnd"
		activePlayer = nil
		deadline = 0
		CharacterService.setActivePlayer(nil)
		broadcastState(nil)
		task.delay(TURN_END_SECONDS, function()
			if isCurrentTransition(token, "TurnEnd") then
				beginNextTurn()
			end
		end)
	end)
end

function MatchService.getWind(): number
	return currentWind
end

function MatchService.getRoundNumber(): number
	return roundNumber
end

return MatchService
