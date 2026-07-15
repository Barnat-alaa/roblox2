--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LobbyConfig = require(ReplicatedStorage.Shared.Config.LobbyConfig)
local LobbyRules = require(ReplicatedStorage.Shared.Simulation.LobbyRules)

local MatchService = require(script.Parent.MatchService)
local NetworkService = require(script.Parent.NetworkService)
local TelemetryService = require(script.Parent.TelemetryService)

type Remotes = NetworkService.Remotes
type Mode = LobbyRules.Mode

type RuntimeQueueEntry = {
	player: Player,
	userId: number,
	mode: Mode,
	joinedAt: number,
	token: string,
	sequence: number,
}

local LobbyService = {}

local remotes: Remotes? = nil
local queue: { RuntimeQueueEntry } = {}
local queuedByPlayer: { [Player]: RuntimeQueueEntry } = {}
local inMatch: { [Player]: boolean } = {}
local matchIdByPlayer: { [Player]: string } = {}
local lastRequestAt: { [Player]: number } = {}
local lastMalformedFeedbackAt: { [Player]: number } = {}
local queueSequence = 0
local matchesStarted = 0
local botFilledMatches = 0
local processing = false
local started = false

local processQueue: () -> ()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function setDiagnostics()
	local practiceCount = 0
	local casualCount = 0
	for _, entry in queue do
		if entry.mode == "Practice" then
			practiceCount += 1
		else
			casualCount += 1
		end
	end
	Workspace:SetAttribute("CritterClashLobbyQueueDepth", #queue)
	Workspace:SetAttribute("CritterClashLobbyPracticeQueued", practiceCount)
	Workspace:SetAttribute("CritterClashLobbyCasualQueued", casualCount)
	Workspace:SetAttribute("CritterClashLobbyMatchesStarted", matchesStarted)
	Workspace:SetAttribute("CritterClashLobbyBotFilledMatches", botFilledMatches)
end

local function queuePosition(target: RuntimeQueueEntry): number?
	for index, entry in queue do
		if entry == target then
			return index
		end
	end
	return nil
end

local function publishState(player: Player)
	if player.Parent ~= Players then
		return
	end

	local state = "Lobby"
	local mode: Mode? = nil
	local token: string? = nil
	local position: number? = nil
	local queueDeadline: number? = nil
	local matchId: string? = nil
	local entry = queuedByPlayer[player]
	if entry then
		state = "Queued"
		mode = entry.mode
		token = entry.token
		position = queuePosition(entry)
		if entry.mode == "Casual" then
			queueDeadline = entry.joinedAt + LobbyConfig.casualBotFillSeconds
		end
	elseif inMatch[player] then
		state = "InMatch"
		matchId = matchIdByPlayer[player]
	end

	player:SetAttribute("LobbyState", state)
	player:SetAttribute("LobbyQueueMode", mode)
	player:SetAttribute("LobbyQueueDeadline", queueDeadline)
	player:SetAttribute("LobbyQueuePosition", position)
	player:SetAttribute("LobbyQueueToken", token)
	player:SetAttribute("LobbyMatchId", matchId)

	local currentRemotes = remotes
	if currentRemotes then
		currentRemotes.lobbyEvent:FireClient(player, "State", {
			state = state,
			mode = mode,
			queueToken = token,
			position = position,
			deadline = queueDeadline,
			matchId = matchId,
			serverTime = now(),
		})
	end
end

local function publishQueue()
	setDiagnostics()
	for _, entry in queue do
		publishState(entry.player)
	end
end

local function reject(player: Player, reason: string)
	local currentRemotes = remotes
	if currentRemotes and player.Parent == Players then
		currentRemotes.lobbyEvent:FireClient(player, "Rejected", {
			reason = reason,
			serverTime = now(),
		})
	end
	publishState(player)
end

local function removeEntry(entry: RuntimeQueueEntry): boolean
	local position = queuePosition(entry)
	if not position then
		if queuedByPlayer[entry.player] == entry then
			queuedByPlayer[entry.player] = nil
		end
		return false
	end
	table.remove(queue, position)
	if queuedByPlayer[entry.player] == entry then
		queuedByPlayer[entry.player] = nil
	end
	return true
end

local function sortQueue()
	table.sort(queue, function(left, right)
		if left.joinedAt ~= right.joinedAt then
			return left.joinedAt < right.joinedAt
		end
		return left.sequence < right.sequence
	end)
end

local function requeue(entries: { RuntimeQueueEntry })
	for _, entry in entries do
		if
			entry.player.Parent == Players
			and queuedByPlayer[entry.player] == nil
			and not MatchService.isPlayerInCurrentMatch(entry.player)
		then
			queuedByPlayer[entry.player] = entry
			table.insert(queue, entry)
		end
	end
	sortQueue()
	publishQueue()
end

local function pruneQueue()
	local changed = false
	for index = #queue, 1, -1 do
		local entry = queue[index]
		if
			entry.player.Parent ~= Players
			or queuedByPlayer[entry.player] ~= entry
			or MatchService.isPlayerInCurrentMatch(entry.player)
		then
			table.remove(queue, index)
			if queuedByPlayer[entry.player] == entry then
				queuedByPlayer[entry.player] = nil
			end
			changed = true
		end
	end
	if changed then
		publishQueue()
	else
		setDiagnostics()
	end
end

local function projections(): { LobbyRules.QueueEntry }
	local result: { LobbyRules.QueueEntry } = table.create(#queue)
	for index, entry in queue do
		result[index] = {
			userId = entry.userId,
			mode = entry.mode,
			joinedAt = entry.joinedAt,
		}
	end
	return result
end

local function selectedEntries(selection: LobbyRules.Selection): { RuntimeQueueEntry }?
	local first = queue[selection.firstIndex]
	if not first then
		return nil
	end
	local result = { first }
	if selection.secondIndex then
		local second = queue[selection.secondIndex]
		if not second or second == first then
			return nil
		end
		table.insert(result, second)
	end
	return result
end

processQueue = function()
	if processing or not started then
		return
	end
	processing = true
	pruneQueue()

	local selection = LobbyRules.selectMatch(projections(), now(), LobbyConfig.casualBotFillSeconds)
	if not selection then
		processing = false
		return
	end
	if not MatchService.isAvailableForLobby() then
		processing = false
		return
	end
	local selected = selectedEntries(selection)
	if not selected then
		processing = false
		return
	end

	local humans: { Player } = table.create(#selected)
	for _, entry in selected do
		if entry.player.Parent ~= Players then
			removeEntry(entry)
			processing = false
			publishQueue()
			task.defer(processQueue)
			return
		end
		table.insert(humans, entry.player)
	end

	-- Remove before admission because MatchService emits MatchStarted
	-- synchronously. A failed setup restores the original FIFO timestamps.
	for _, entry in selected do
		removeEntry(entry)
	end
	local accepted, reason = MatchService.tryStartMatch(humans)
	if not accepted then
		requeue(selected)
		processing = false
		if reason ~= "match_busy" then
			warn(string.format("[CritterClash] Lobby admission failed: %s", tostring(reason)))
		end
		return
	end

	matchesStarted += 1
	if selection.botFilled then
		botFilledMatches += 1
	end
	local waitSeconds = math.clamp(now() - selected[1].joinedAt, 0, 3_600)
	TelemetryService.emit("queue_matched", {
		mode = selection.mode,
		opponent = if selection.botFilled then "Bot" else "Player",
		waitSeconds = waitSeconds,
	})
	TelemetryService.emit("match_started", {
		mode = selection.mode,
		versusBot = selection.botFilled,
		participantCount = if selection.botFilled then #humans + 1 else #humans,
	})
	for _, entry in selected do
		inMatch[entry.player] = true
		publishState(entry.player)
	end
	processing = false
	publishQueue()
end

local function enqueue(player: Player, mode: Mode)
	if MatchService.isPlayerInCurrentMatch(player) then
		inMatch[player] = true
		reject(player, "already_in_match")
		return
	end

	local existing = queuedByPlayer[player]
	if existing and existing.mode == mode then
		publishState(player)
		return
	end
	if existing then
		TelemetryService.emit("queue_cancelled", {
			mode = existing.mode,
			waitSeconds = math.clamp(now() - existing.joinedAt, 0, 3_600),
		})
		removeEntry(existing)
	end

	queueSequence += 1
	local entry: RuntimeQueueEntry = {
		player = player,
		userId = player.UserId,
		mode = mode,
		joinedAt = now(),
		token = HttpService:GenerateGUID(false),
		sequence = queueSequence,
	}
	inMatch[player] = nil
	matchIdByPlayer[player] = nil
	queuedByPlayer[player] = entry
	table.insert(queue, entry)
	TelemetryService.emit("queue_joined", {
		mode = mode,
	})
	publishQueue()
	task.defer(processQueue)
end

local function cancel(player: Player, requestedToken: string?)
	local entry = queuedByPlayer[player]
	if not entry then
		publishState(player)
		return
	end
	if not LobbyRules.cancelMatches(entry.token, requestedToken) then
		-- A cancel from an older queue generation is a successful no-op.
		publishState(player)
		return
	end
	TelemetryService.emit("queue_cancelled", {
		mode = entry.mode,
		waitSeconds = math.clamp(now() - entry.joinedAt, 0, 3_600),
	})
	removeEntry(entry)
	publishState(player)
	publishQueue()
	task.defer(processQueue)
end

local function returnToLobby(player: Player)
	local returned, reason = MatchService.returnPlayerToLobby(player)
	if not returned and MatchService.isPlayerInCurrentMatch(player) then
		reject(player, reason or "return_rejected")
		return
	end
	inMatch[player] = nil
	matchIdByPlayer[player] = nil
	publishState(player)
	task.defer(processQueue)
end

local function handleRequest(player: Player, value: unknown)
	local requestTime = os.clock()
	local previous = lastRequestAt[player]
	if previous and requestTime - previous < LobbyConfig.requestRateLimitSeconds then
		return
	end
	lastRequestAt[player] = requestTime

	local request = LobbyRules.parseRequest(value)
	if not request then
		local previousFeedback = lastMalformedFeedbackAt[player]
		if not previousFeedback or requestTime - previousFeedback >= 1 then
			lastMalformedFeedbackAt[player] = requestTime
			reject(player, "malformed_request")
		end
		return
	end

	if request.action == "Practice" or request.action == "Casual" then
		enqueue(player, request.action :: Mode)
	elseif request.action == "Cancel" then
		cancel(player, request.queueToken)
	else
		returnToLobby(player)
	end
end

local function onLifecycle(snapshot: MatchService.LifecycleSnapshot)
	if snapshot.kind == "MatchStarted" then
		for _, player in snapshot.humanPlayers do
			local entry = queuedByPlayer[player]
			if entry then
				removeEntry(entry)
			end
			inMatch[player] = true
			matchIdByPlayer[player] = snapshot.matchId
			publishState(player)
		end
	else
		for _, player in snapshot.humanPlayers do
			inMatch[player] = nil
			matchIdByPlayer[player] = nil
			publishState(player)
		end
	end
	publishQueue()
	task.defer(processQueue)
end

local function observePlayer(player: Player)
	if MatchService.isPlayerInCurrentMatch(player) then
		inMatch[player] = true
	end
	publishState(player)
end

function LobbyService.start(networkRemotes: Remotes)
	assert(not started, "LobbyService may only be started once")
	started = true
	remotes = networkRemotes

	networkRemotes.requestLobbyAction.OnServerEvent:Connect(function(player, value)
		handleRequest(player, value)
	end)
	MatchService.setLifecycleHandler(onLifecycle)

	for _, player in Players:GetPlayers() do
		observePlayer(player)
	end
	Players.PlayerAdded:Connect(observePlayer)
	Players.PlayerRemoving:Connect(function(player)
		local entry = queuedByPlayer[player]
		if entry then
			removeEntry(entry)
		end
		inMatch[player] = nil
		matchIdByPlayer[player] = nil
		lastRequestAt[player] = nil
		lastMalformedFeedbackAt[player] = nil
		publishQueue()
		task.defer(processQueue)
	end)

	setDiagnostics()
	task.spawn(function()
		while true do
			task.wait(LobbyConfig.queuePollSeconds)
			if #queue > 0 then
				processQueue()
			end
		end
	end)
end

return LobbyService
