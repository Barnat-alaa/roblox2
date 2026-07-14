--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchRules = require(ReplicatedStorage.Shared.Simulation.MatchRules)

local MAX_PARTICIPANTS = 8
local MAX_DISPLAY_NAME_BYTES = 96
local MAX_REASON_BYTES = 96
local MAX_SAFE_INTEGER = 9_007_199_254_740_991
local CLOSED_MATCH_HISTORY = 16
local REQUEST_COOLDOWN_SECONDS = 0.2
local WARNING_INTERVAL_SECONDS = 2

local DEEP_TEAL = Color3.fromRGB(15, 107, 109)
local WARM_CORAL = Color3.fromRGB(242, 107, 94)
local CREAM = Color3.fromRGB(255, 241, 213)
local GOLDEN = Color3.fromRGB(246, 196, 71)
local DARK_NAVY = Color3.fromRGB(20, 40, 61)
local MINT = Color3.fromRGB(118, 217, 177)
local IMPACT_WHITE = Color3.fromRGB(255, 253, 246)

type NetworkTable = { [any]: any }

type Participant = {
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
	participants: { Participant },
	serverTime: number,
}

type RematchStatusPayload = {
	matchId: string,
	readyUserIds: { number },
	requiredUserIds: { number },
	serverTime: number,
}

type MatchRestartingPayload = {
	matchId: string,
	nextMatchId: string,
	serverTime: number,
}

type ParticipantRow = {
	frame: Frame,
	statusLabel: TextLabel,
	baseStatus: string,
}

export type Controller = {
	setMatchState: (phase: string, serverTime: number) -> (),
	destroy: () -> (),
}

local ResultsController = {}

local ACTIVE_MATCH_PHASES: { [string]: boolean } = {
	Countdown = true,
	TurnStart = true,
	Movement = true,
	Aiming = true,
}

local REASON_LABELS: { [string]: string } = {
	last_participant_standing = "Last critter standing",
	all_participants_eliminated = "Every critter was eliminated",
	elimination = "The final hit decided the match",
	disconnect = "The other critter left the match",
	timeout = "The match timer expired",
	draw = "Nobody takes the crown this round",
}

local function asTable(value: any): NetworkTable?
	if type(value) ~= "table" then
		return nil
	end
	return value :: NetworkTable
end

local function finiteNumber(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function safeInteger(value: any): number?
	local numberValue = finiteNumber(value)
	if
		not numberValue
		or numberValue ~= math.floor(numberValue)
		or math.abs(numberValue) > MAX_SAFE_INTEGER
	then
		return nil
	end
	return numberValue
end

local function boundedString(value: any, maximumBytes: number, allowEmpty: boolean): string?
	if type(value) ~= "string" or #value > maximumBytes or value:find("%c") then
		return nil
	end
	if not allowEmpty and value:match("%S") == nil then
		return nil
	end
	return value
end

local function parseParticipants(value: any): { Participant }?
	local source = asTable(value)
	if not source then
		return nil
	end

	local participants: { Participant } = {}
	local seenUserIds: { [number]: boolean } = {}
	local entryCount = 0
	for rawArrayIndex, rawParticipant in source do
		local arrayIndex = safeInteger(rawArrayIndex)
		local participantTable = asTable(rawParticipant)
		if
			not arrayIndex
			or arrayIndex < 1
			or arrayIndex > MAX_PARTICIPANTS
			or not participantTable
		then
			return nil
		end

		local userId = safeInteger(participantTable.userId)
		local displayName =
			boundedString(participantTable.displayName, MAX_DISPLAY_NAME_BYTES, false)
		local eliminated = participantTable.eliminated
		local isNpc = participantTable.isNpc
		if
			not userId
			or seenUserIds[userId]
			or not displayName
			or type(eliminated) ~= "boolean"
			or type(isNpc) ~= "boolean"
		then
			return nil
		end

		seenUserIds[userId] = true
		entryCount += 1
		participants[arrayIndex] = {
			userId = userId,
			displayName = displayName,
			eliminated = eliminated,
			isNpc = isNpc,
		}
	end
	if entryCount < 1 or entryCount ~= #participants then
		return nil
	end
	return participants
end

local function parseResult(value: any): ResultPayload?
	local payload = asTable(value)
	if not payload then
		return nil
	end

	local matchId = boundedString(payload.matchId, MatchRules.MAX_MATCH_ID_LENGTH, false)
	local winnerUserId = safeInteger(payload.winnerUserId)
	local isDraw = payload.isDraw
	local reason = boundedString(payload.reason, MAX_REASON_BYTES, true)
	local participants = parseParticipants(payload.participants)
	local serverTime = finiteNumber(payload.serverTime)
	if
		not matchId
		or not winnerUserId
		or type(isDraw) ~= "boolean"
		or not reason
		or not participants
		or not serverTime
		or serverTime < 0
	then
		return nil
	end

	if not isDraw then
		local winnerFound = false
		for _, participant in participants do
			if participant.userId == winnerUserId then
				winnerFound = true
				break
			end
		end
		if not winnerFound then
			return nil
		end
	end

	return {
		matchId = matchId,
		winnerUserId = winnerUserId,
		isDraw = isDraw,
		reason = reason,
		participants = participants,
		serverTime = serverTime,
	}
end

local function parseUserIdArray(value: any): { number }?
	local source = asTable(value)
	if not source then
		return nil
	end

	local result: { number } = {}
	local seen: { [number]: boolean } = {}
	local entryCount = 0
	for rawArrayIndex, rawUserId in source do
		local arrayIndex = safeInteger(rawArrayIndex)
		local userId = safeInteger(rawUserId)
		if
			not arrayIndex
			or arrayIndex < 1
			or arrayIndex > MAX_PARTICIPANTS
			or not userId
			or seen[userId]
		then
			return nil
		end
		seen[userId] = true
		entryCount += 1
		result[arrayIndex] = userId
	end
	if entryCount ~= #result then
		return nil
	end
	return result
end

local function parseRematchStatus(value: any): RematchStatusPayload?
	local payload = asTable(value)
	if not payload then
		return nil
	end

	local matchId = boundedString(payload.matchId, MatchRules.MAX_MATCH_ID_LENGTH, false)
	local readyUserIds = parseUserIdArray(payload.readyUserIds)
	local requiredUserIds = parseUserIdArray(payload.requiredUserIds)
	local serverTime = finiteNumber(payload.serverTime)
	if
		not matchId
		or not readyUserIds
		or not requiredUserIds
		or not serverTime
		or serverTime < 0
	then
		return nil
	end

	local requiredSet: { [number]: boolean } = {}
	for _, userId in requiredUserIds do
		requiredSet[userId] = true
	end
	for _, userId in readyUserIds do
		if not requiredSet[userId] then
			return nil
		end
	end

	return {
		matchId = matchId,
		readyUserIds = readyUserIds,
		requiredUserIds = requiredUserIds,
		serverTime = serverTime,
	}
end

local function parseMatchRestarting(value: any): MatchRestartingPayload?
	local payload = asTable(value)
	if not payload then
		return nil
	end

	local matchId = boundedString(payload.matchId, MatchRules.MAX_MATCH_ID_LENGTH, false)
	local nextMatchId = boundedString(payload.nextMatchId, MatchRules.MAX_MATCH_ID_LENGTH, false)
	local serverTime = finiteNumber(payload.serverTime)
	if
		not matchId
		or not nextMatchId
		or matchId == nextMatchId
		or not serverTime
		or serverTime < 0
	then
		return nil
	end
	return {
		matchId = matchId,
		nextMatchId = nextMatchId,
		serverTime = serverTime,
	}
end

local function addCorner(guiObject: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = guiObject
end

local function addStroke(guiObject: GuiObject, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = 0.08
	stroke.Parent = guiObject
end

local function createLabel(
	parent: Instance,
	name: string,
	text: string,
	position: UDim2,
	size: UDim2,
	textSize: number,
	color: Color3,
	alignment: Enum.TextXAlignment?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Position = position
	label.Size = size
	label.Text = text
	label.TextColor3 = color
	label.TextSize = textSize
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextXAlignment = alignment or Enum.TextXAlignment.Center
	label.Parent = parent
	return label
end

local function reasonText(reason: string): string
	if reason == "" then
		return "Match complete"
	end
	return REASON_LABELS[reason] or reason:gsub("_", " ")
end

function ResultsController.create(
	matchEventRemote: RemoteEvent,
	requestRematchRemote: RemoteEvent
): Controller
	local localPlayer = Players.LocalPlayer
	local playerGuiInstance = localPlayer:WaitForChild("PlayerGui")
	assert(playerGuiInstance:IsA("PlayerGui"), "PlayerGui must be available")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CritterClashResults"
	screenGui.DisplayOrder = 30
	screenGui.IgnoreGuiInset = false
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGuiInstance

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundColor3 = DARK_NAVY
	overlay.BackgroundTransparency = 0.3
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Visible = false
	overlay.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "ResultsPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = DARK_NAVY
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.86, 0.82)
	panel.Parent = overlay
	addCorner(panel, 18)
	addStroke(panel, CREAM, 3)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(580, 580)
	sizeConstraint.MinSize = Vector2.new(280, 300)
	sizeConstraint.Parent = panel

	local titleLabel = createLabel(
		panel,
		"Title",
		"MATCH COMPLETE",
		UDim2.fromOffset(20, 16),
		UDim2.new(1, -40, 0, 50),
		38,
		GOLDEN,
		Enum.TextXAlignment.Center
	)
	titleLabel.TextScaled = true
	local titleConstraint = Instance.new("UITextSizeConstraint")
	titleConstraint.MinTextSize = 24
	titleConstraint.MaxTextSize = 42
	titleConstraint.Parent = titleLabel

	local reasonLabel = createLabel(
		panel,
		"Reason",
		"",
		UDim2.fromOffset(24, 70),
		UDim2.new(1, -48, 0, 28),
		15,
		CREAM,
		Enum.TextXAlignment.Center
	)
	reasonLabel.TextWrapped = true

	createLabel(
		panel,
		"ParticipantsTitle",
		"CRITTERS",
		UDim2.fromOffset(24, 104),
		UDim2.new(1, -48, 0, 22),
		14,
		MINT,
		Enum.TextXAlignment.Left
	)

	local participantList = Instance.new("ScrollingFrame")
	participantList.Name = "Participants"
	participantList.BackgroundTransparency = 1
	participantList.BorderSizePixel = 0
	participantList.Position = UDim2.fromOffset(24, 132)
	participantList.Size = UDim2.new(1, -48, 1, -270)
	participantList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	participantList.CanvasSize = UDim2.fromOffset(0, 0)
	participantList.ScrollBarImageColor3 = MINT
	participantList.ScrollBarThickness = 5
	participantList.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 7)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = participantList

	local rematchStatusLabel = createLabel(
		panel,
		"RematchStatus",
		"READY FOR ANOTHER ROUND?",
		UDim2.new(0, 24, 1, -126),
		UDim2.new(1, -48, 0, 24),
		14,
		CREAM,
		Enum.TextXAlignment.Center
	)

	local rematchButton = Instance.new("TextButton")
	rematchButton.Name = "RematchButton"
	rematchButton.AnchorPoint = Vector2.new(0.5, 0)
	rematchButton.AutoButtonColor = false
	rematchButton.BackgroundColor3 = DEEP_TEAL
	rematchButton.Position = UDim2.new(0.5, 0, 1, -96)
	rematchButton.Size = UDim2.new(0.62, 0, 0, 52)
	rematchButton.Font = Enum.Font.GothamBold
	rematchButton.Text = "REMATCH"
	rematchButton.TextColor3 = IMPACT_WHITE
	rematchButton.TextSize = 20
	rematchButton.Parent = panel
	addCorner(rematchButton, 13)
	addStroke(rematchButton, CREAM, 2)

	local rematchHintLabel = createLabel(
		panel,
		"RematchHint",
		"Press again to cancel readiness",
		UDim2.new(0, 24, 1, -36),
		UDim2.new(1, -48, 0, 18),
		11,
		CREAM,
		Enum.TextXAlignment.Center
	)

	local currentMatchId: string? = nil
	local currentResultTime = -math.huge
	local latestResultTime = -math.huge
	local latestStatusTime = -math.huge
	local participantsById: { [number]: Participant } = {}
	local participantRows: { [number]: ParticipantRow } = {}
	local readyUserIds: { [number]: boolean } = {}
	local requiredUserIds: { [number]: boolean } = {}
	local localReady = false
	local canRequestRematch = false
	local lastRequestAt = -math.huge
	local closedMatchIds: { [string]: boolean } = {}
	local closedMatchOrder: { string } = {}
	local lastWarningAt = -math.huge
	local destroyed = false

	local function reportProblem(kind: string)
		local now = os.clock()
		if now - lastWarningAt >= WARNING_INTERVAL_SECONDS then
			lastWarningAt = now
			warn(`[CritterClash Results] ignored malformed or stale {kind}`)
		end
	end

	local function rememberClosed(matchId: string)
		if closedMatchIds[matchId] then
			return
		end
		closedMatchIds[matchId] = true
		table.insert(closedMatchOrder, matchId)
		if #closedMatchOrder > CLOSED_MATCH_HISTORY then
			local expiredId = table.remove(closedMatchOrder, 1)
			if expiredId then
				closedMatchIds[expiredId] = nil
			end
		end
	end

	local function clearParticipantRows()
		for _, row in participantRows do
			row.frame:Destroy()
		end
		table.clear(participantRows)
		table.clear(participantsById)
		table.clear(readyUserIds)
		table.clear(requiredUserIds)
	end

	local function updateRematchButton()
		rematchButton.Active = canRequestRematch
		if not canRequestRematch then
			rematchButton.Text = "SPECTATING"
			rematchButton.BackgroundColor3 = DARK_NAVY
			rematchButton.TextColor3 = CREAM
			rematchHintLabel.Text = "Watching this rematch vote"
		else
			rematchButton.Text = if localReady then "READY - CANCEL" else "REMATCH"
			rematchButton.BackgroundColor3 = if localReady then MINT else DEEP_TEAL
			rematchButton.TextColor3 = if localReady then DARK_NAVY else IMPACT_WHITE
			rematchHintLabel.Text = if localReady
				then "Press again to cancel readiness"
				else "Toggle readiness for another round"
		end
	end

	local function updateParticipantReadyStates()
		for userId, row in participantRows do
			if requiredUserIds[userId] then
				row.statusLabel.Text = if readyUserIds[userId] then "READY" else "WAITING"
				row.statusLabel.TextColor3 = if readyUserIds[userId] then MINT else GOLDEN
			else
				row.statusLabel.Text = row.baseStatus
				row.statusLabel.TextColor3 = CREAM
			end
		end
	end

	local function hideCurrentResult(closeMatch: boolean)
		local matchId = currentMatchId
		if closeMatch and matchId then
			rememberClosed(matchId)
		end
		overlay.Visible = false
		currentMatchId = nil
		currentResultTime = -math.huge
		latestStatusTime = -math.huge
		localReady = false
		canRequestRematch = false
		clearParticipantRows()
		updateRematchButton()
	end

	local function createParticipantRow(
		participant: Participant,
		result: ResultPayload,
		order: number
	)
		local row = Instance.new("Frame")
		row.Name = `Participant_{participant.userId}`
		row.BackgroundColor3 = if participant.userId == localPlayer.UserId
			then DEEP_TEAL
			else DARK_NAVY
		row.BackgroundTransparency = if participant.userId == localPlayer.UserId then 0.05 else 0.3
		row.LayoutOrder = order
		row.Size = UDim2.new(1, -8, 0, 44)
		row.Parent = participantList
		addCorner(row, 10)
		addStroke(row, if participant.userId == localPlayer.UserId then MINT else DEEP_TEAL, 1)

		local suffix = if participant.userId == localPlayer.UserId
			then " (YOU)"
			elseif participant.isNpc then " (BOT)"
			else ""
		createLabel(
			row,
			"Name",
			participant.displayName .. suffix,
			UDim2.fromOffset(12, 0),
			UDim2.new(0.62, -12, 1, 0),
			15,
			CREAM,
			Enum.TextXAlignment.Left
		)

		local baseStatus = if not result.isDraw
				and participant.userId == result.winnerUserId
			then "WINNER"
			elseif participant.eliminated then "ELIMINATED"
			else "SURVIVED"
		local statusLabel = createLabel(
			row,
			"Status",
			baseStatus,
			UDim2.fromScale(0.62, 0),
			UDim2.new(0.38, -12, 1, 0),
			12,
			if baseStatus == "WINNER" then GOLDEN else CREAM,
			Enum.TextXAlignment.Right
		)
		participantsById[participant.userId] = participant
		participantRows[participant.userId] = {
			frame = row,
			statusLabel = statusLabel,
			baseStatus = baseStatus,
		}
	end

	local function showResult(result: ResultPayload)
		if
			closedMatchIds[result.matchId]
			or currentMatchId == result.matchId
			or result.serverTime <= latestResultTime
		then
			return
		end
		if currentMatchId and currentMatchId ~= result.matchId then
			rememberClosed(currentMatchId)
		end

		clearParticipantRows()
		participantList.CanvasPosition = Vector2.zero
		screenGui:SetAttribute("NextMatchId", nil)
		currentMatchId = result.matchId
		currentResultTime = result.serverTime
		latestResultTime = result.serverTime
		latestStatusTime = result.serverTime
		localReady = false
		for order, participant in result.participants do
			createParticipantRow(participant, result, order)
		end
		local localParticipant = participantsById[localPlayer.UserId]
		canRequestRematch = localParticipant ~= nil and not localParticipant.isNpc

		if result.isDraw then
			titleLabel.Text = "DRAW"
			titleLabel.TextColor3 = GOLDEN
		elseif not localParticipant then
			titleLabel.Text = "MATCH COMPLETE"
			titleLabel.TextColor3 = GOLDEN
		elseif result.winnerUserId == localPlayer.UserId then
			titleLabel.Text = "VICTORY"
			titleLabel.TextColor3 = MINT
		else
			titleLabel.Text = "DEFEAT"
			titleLabel.TextColor3 = WARM_CORAL
		end
		reasonLabel.Text = reasonText(result.reason)
		rematchStatusLabel.Text = "READY FOR ANOTHER ROUND?"
		updateRematchButton()
		overlay.Visible = true
	end

	local function applyRematchStatus(status: RematchStatusPayload)
		local matchId = currentMatchId
		if
			not matchId
			or status.matchId ~= matchId
			or status.serverTime < currentResultTime
			or status.serverTime <= latestStatusTime
		then
			return
		end

		local nextRequired: { [number]: boolean } = {}
		for _, userId in status.requiredUserIds do
			local participant = participantsById[userId]
			if not participant or participant.isNpc then
				reportProblem("RematchStatus")
				return
			end
			nextRequired[userId] = true
		end
		local nextReady: { [number]: boolean } = {}
		for _, userId in status.readyUserIds do
			nextReady[userId] = true
		end

		latestStatusTime = status.serverTime
		requiredUserIds = nextRequired
		readyUserIds = nextReady
		canRequestRematch = requiredUserIds[localPlayer.UserId] == true
		localReady = canRequestRematch and readyUserIds[localPlayer.UserId] == true
		rematchStatusLabel.Text = if #status.requiredUserIds == 0
			then "NO CONNECTED PLAYERS"
			else string.format("%d / %d READY", #status.readyUserIds, #status.requiredUserIds)
		updateRematchButton()
		updateParticipantReadyStates()
	end

	local function handleRestarting(restarting: MatchRestartingPayload)
		local matchId = currentMatchId
		if
			not matchId
			or restarting.matchId ~= matchId
			or restarting.serverTime < currentResultTime
		then
			return
		end
		screenGui:SetAttribute("NextMatchId", restarting.nextMatchId)
		hideCurrentResult(true)
	end

	local rematchConnection = rematchButton.Activated:Connect(function()
		local matchId = currentMatchId
		if not matchId or not overlay.Visible or not canRequestRematch then
			return
		end
		local now = os.clock()
		if now - lastRequestAt < REQUEST_COOLDOWN_SECONDS then
			return
		end
		lastRequestAt = now
		localReady = not localReady
		updateRematchButton()
		requestRematchRemote:FireServer({
			matchId = matchId,
			ready = localReady,
		})
	end)

	local matchEventConnection = matchEventRemote.OnClientEvent:Connect(
		function(kind: any, payload: any)
			if kind == "Result" then
				local result = parseResult(payload)
				if result then
					showResult(result)
				else
					reportProblem("Result")
				end
			elseif kind == "RematchStatus" then
				local status = parseRematchStatus(payload)
				if status then
					applyRematchStatus(status)
				else
					reportProblem("RematchStatus")
				end
			elseif kind == "MatchRestarting" then
				local restarting = parseMatchRestarting(payload)
				if restarting then
					handleRestarting(restarting)
				else
					reportProblem("MatchRestarting")
				end
			end
		end
	)

	local controller: Controller = {
		setMatchState = function(phase: string, serverTime: number)
			if
				overlay.Visible
				and ACTIVE_MATCH_PHASES[phase]
				and serverTime > currentResultTime
			then
				hideCurrentResult(true)
			end
		end,
		destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			rematchConnection:Disconnect()
			matchEventConnection:Disconnect()
			clearParticipantRows()
			screenGui:Destroy()
		end,
	}

	return controller
end

return ResultsController
