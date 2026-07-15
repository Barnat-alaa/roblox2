--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchRules = require(ReplicatedStorage.Shared.Simulation.MatchRules)
local ClientSettings = require(script.Parent.ClientSettings)

local MAX_PARTICIPANTS = 8
local MAX_DISPLAY_NAME_BYTES = 96
local MAX_REASON_BYTES = 96
local MAX_SAFE_INTEGER = 9_007_199_254_740_991
local CLOSED_MATCH_HISTORY = 16
local REQUEST_COOLDOWN_SECONDS = 0.2
local WARNING_INTERVAL_SECONDS = 2

local REWARD_STATUS: { [string]: boolean } = {
	Pending = true,
	Granted = true,
	Duplicate = true,
	Ineligible = true,
	ReadOnly = true,
	Unavailable = true,
}

local REWARD_ENTRY_KEYS: { [string]: boolean } = {
	userId = true,
	status = true,
	coins = true,
	experience = true,
}

local REWARD_RESOLVED_KEYS: { [string]: boolean } = {
	matchId = true,
	userId = true,
	status = true,
	coins = true,
	experience = true,
	serverTime = true,
}

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

type RewardEntry = {
	userId: number,
	status: string,
	coins: number,
	experience: number,
}

type ResultPayload = {
	matchId: string,
	winnerUserId: number,
	isDraw: boolean,
	reason: string,
	participants: { Participant },
	rewards: { RewardEntry },
	serverTime: number,
}

type RewardResolvedPayload = RewardEntry & {
	matchId: string,
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

local function hasExactKeys(
	source: NetworkTable,
	allowedKeys: { [string]: boolean },
	expectedCount: number
): boolean
	local count = 0
	for rawKey in source do
		if type(rawKey) ~= "string" or not allowedKeys[rawKey] then
			return false
		end
		count += 1
		if count > expectedCount then
			return false
		end
	end
	return count == expectedCount
end

local function parseRewardEntry(value: any): RewardEntry?
	local source = asTable(value)
	if not source or not hasExactKeys(source, REWARD_ENTRY_KEYS, 4) then
		return nil
	end

	local userId = safeInteger(source.userId)
	local status = source.status
	local coins = safeInteger(source.coins)
	local experience = safeInteger(source.experience)
	if
		userId == nil
		or type(status) ~= "string"
		or not REWARD_STATUS[status]
		or coins == nil
		or coins < 0
		or experience == nil
		or experience < 0
	then
		return nil
	end

	return {
		userId = userId,
		status = status,
		coins = coins,
		experience = experience,
	}
end

local function parseRewards(value: any): { RewardEntry }?
	local source = asTable(value)
	if not source then
		return nil
	end

	local rewards: { RewardEntry } = {}
	local seenUserIds: { [number]: boolean } = {}
	local entryCount = 0
	for rawArrayIndex, rawReward in source do
		local arrayIndex = safeInteger(rawArrayIndex)
		local reward = parseRewardEntry(rawReward)
		if
			arrayIndex == nil
			or arrayIndex < 1
			or arrayIndex > MAX_PARTICIPANTS
			or reward == nil
			or seenUserIds[reward.userId]
		then
			return nil
		end
		seenUserIds[reward.userId] = true
		entryCount += 1
		rewards[arrayIndex] = reward
	end
	if entryCount ~= #rewards then
		return nil
	end
	return rewards
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
	local rewards = parseRewards(payload.rewards)
	local serverTime = finiteNumber(payload.serverTime)
	if
		not matchId
		or not winnerUserId
		or type(isDraw) ~= "boolean"
		or not reason
		or not participants
		or not rewards
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

	local participantByUserId: { [number]: Participant } = {}
	local rewardedUserIds: { [number]: boolean } = {}
	for _, participant in participants do
		participantByUserId[participant.userId] = participant
	end
	for _, reward in rewards do
		local participant = participantByUserId[reward.userId]
		if not participant or participant.isNpc then
			return nil
		end
		rewardedUserIds[reward.userId] = true
	end
	for _, participant in participants do
		if not participant.isNpc and not rewardedUserIds[participant.userId] then
			return nil
		end
	end

	return {
		matchId = matchId,
		winnerUserId = winnerUserId,
		isDraw = isDraw,
		reason = reason,
		participants = participants,
		rewards = rewards,
		serverTime = serverTime,
	}
end

local function parseRewardResolved(value: any): RewardResolvedPayload?
	local payload = asTable(value)
	if not payload or not hasExactKeys(payload, REWARD_RESOLVED_KEYS, 6) then
		return nil
	end

	local matchId = boundedString(payload.matchId, MatchRules.MAX_MATCH_ID_LENGTH, false)
	local reward = parseRewardEntry({
		userId = payload.userId,
		status = payload.status,
		coins = payload.coins,
		experience = payload.experience,
	})
	local serverTime = finiteNumber(payload.serverTime)
	if not matchId or not reward or not serverTime or serverTime < 0 then
		return nil
	end

	return {
		matchId = matchId,
		userId = reward.userId,
		status = reward.status,
		coins = reward.coins,
		experience = reward.experience,
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

local function formatInteger(value: number): string
	local digits = string.format("%.0f", value)
	local reversed = string.reverse(digits)
	local grouped = reversed:gsub("(%d%d%d)", "%1,")
	grouped = string.reverse(grouped)
	if grouped:sub(1, 1) == "," then
		grouped = grouped:sub(2)
	end
	return grouped
end

local function rewardPresentation(reward: RewardEntry): (string, Color3)
	local coins = formatInteger(reward.coins)
	local experience = formatInteger(reward.experience)
	if reward.status == "Pending" then
		return `REWARD PENDING | {coins} COINS | {experience} XP`, GOLDEN
	elseif reward.status == "Granted" then
		return `YOUR REWARD | +{coins} COINS | +{experience} XP`, MINT
	elseif reward.status == "Duplicate" then
		return `REWARD SECURED | {coins} COINS | {experience} XP`, MINT
	elseif reward.status == "Ineligible" then
		return "NO REWARD | MATCH ELIGIBILITY NOT MET", CREAM
	elseif reward.status == "ReadOnly" then
		return "REWARDS PAUSED | PROFILE IS READ ONLY", GOLDEN
	end
	return "REWARDS OFFLINE | PROGRESS WAS NOT CHANGED", WARM_CORAL
end

function ResultsController.create(
	matchEventRemote: RemoteEvent,
	requestRematchRemote: RemoteEvent,
	requestLobbyActionRemote: RemoteEvent?,
	lobbyEventRemote: RemoteEvent?
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
	sizeConstraint.MinSize = Vector2.new(280, 340)
	sizeConstraint.Parent = panel

	local accessibilityScale = Instance.new("UIScale")
	accessibilityScale.Name = "AccessibilityScale"
	accessibilityScale.Scale = ClientSettings.readLocal(localPlayer).uiScale
	accessibilityScale.Parent = panel

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
	participantList.Size = UDim2.new(1, -48, 1, -316)
	participantList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	participantList.CanvasSize = UDim2.fromOffset(0, 0)
	participantList.ScrollBarImageColor3 = MINT
	participantList.ScrollBarThickness = 5
	participantList.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 7)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = participantList

	local rewardFrame = Instance.new("Frame")
	rewardFrame.Name = "LocalReward"
	rewardFrame.BackgroundColor3 = DEEP_TEAL
	rewardFrame.BackgroundTransparency = 0.08
	rewardFrame.Position = UDim2.new(0, 24, 1, -176)
	rewardFrame.Size = UDim2.new(1, -48, 0, 36)
	rewardFrame.Parent = panel
	addCorner(rewardFrame, 10)
	addStroke(rewardFrame, GOLDEN, 1)

	local rewardLabel = createLabel(
		rewardFrame,
		"Status",
		"REWARD STATUS PENDING",
		UDim2.fromOffset(10, 3),
		UDim2.new(1, -20, 1, -6),
		13,
		GOLDEN,
		Enum.TextXAlignment.Center
	)
	rewardLabel.TextScaled = true
	local rewardTextConstraint = Instance.new("UITextSizeConstraint")
	rewardTextConstraint.MinTextSize = 10
	rewardTextConstraint.MaxTextSize = 14
	rewardTextConstraint.Parent = rewardLabel

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
	rematchButton.AnchorPoint = Vector2.zero
	rematchButton.AutoButtonColor = false
	rematchButton.BackgroundColor3 = DEEP_TEAL
	rematchButton.Position = UDim2.new(0, 24, 1, -96)
	rematchButton.Size = UDim2.new(0.5, -30, 0, 52)
	rematchButton.Font = Enum.Font.GothamBold
	rematchButton.Text = "REMATCH"
	rematchButton.TextColor3 = IMPACT_WHITE
	rematchButton.TextSize = 20
	rematchButton.Selectable = true
	rematchButton.Parent = panel
	addCorner(rematchButton, 13)
	addStroke(rematchButton, CREAM, 2)

	local returnButton = Instance.new("TextButton")
	returnButton.Name = "ReturnToLobbyButton"
	returnButton.AutoButtonColor = false
	returnButton.BackgroundColor3 = WARM_CORAL
	returnButton.Position = UDim2.new(0.5, 6, 1, -96)
	returnButton.Size = UDim2.new(0.5, -30, 0, 52)
	returnButton.Font = Enum.Font.GothamBold
	returnButton.Text = "RETURN TO CAMP"
	returnButton.TextColor3 = IMPACT_WHITE
	returnButton.TextScaled = true
	returnButton.Selectable = true
	returnButton.Visible = requestLobbyActionRemote ~= nil
	returnButton.Parent = panel
	addCorner(returnButton, 13)
	addStroke(returnButton, CREAM, 2)
	local returnTextConstraint = Instance.new("UITextSizeConstraint")
	returnTextConstraint.MinTextSize = 11
	returnTextConstraint.MaxTextSize = 17
	returnTextConstraint.Parent = returnButton

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
	local latestRewardTime = -math.huge
	local currentLocalReward: RewardEntry? = nil
	local participantsById: { [number]: Participant } = {}
	local participantRows: { [number]: ParticipantRow } = {}
	local readyUserIds: { [number]: boolean } = {}
	local requiredUserIds: { [number]: boolean } = {}
	local localReady = false
	local canRequestRematch = false
	local returnPending = false
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

	local function renderLocalReward(reward: RewardEntry?)
		currentLocalReward = reward
		if not reward then
			rewardLabel.Text = "SPECTATING | NO PERSONAL REWARD"
			rewardLabel.TextColor3 = CREAM
			return
		end
		local text, color = rewardPresentation(reward)
		rewardLabel.Text = text
		rewardLabel.TextColor3 = color
	end

	local function updateRematchButton()
		rematchButton.Active = canRequestRematch and not returnPending
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

	local function updateReturnButton()
		returnButton.Active = requestLobbyActionRemote ~= nil and not returnPending
		returnButton.Text = if returnPending then "RETURNING..." else "RETURN TO CAMP"
		returnButton.BackgroundColor3 = if returnPending then GOLDEN else WARM_CORAL
		returnButton.TextColor3 = if returnPending then DARK_NAVY else IMPACT_WHITE
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
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(overlay) then
			GuiService.SelectedObject = nil
		end
		overlay.Visible = false
		currentMatchId = nil
		currentResultTime = -math.huge
		latestStatusTime = -math.huge
		latestRewardTime = -math.huge
		localReady = false
		canRequestRematch = false
		returnPending = false
		renderLocalReward(nil)
		clearParticipantRows()
		updateRematchButton()
		updateReturnButton()
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
		local lobbyMatchId = localPlayer:GetAttribute("LobbyMatchId")
		if
			localPlayer:GetAttribute("LobbyState") ~= "InMatch"
			or (
				type(lobbyMatchId) == "string"
				and lobbyMatchId ~= ""
				and lobbyMatchId ~= result.matchId
			)
		then
			return
		end
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
		latestRewardTime = result.serverTime
		localReady = false
		returnPending = false
		for order, participant in result.participants do
			createParticipantRow(participant, result, order)
		end
		local localParticipant = participantsById[localPlayer.UserId]
		canRequestRematch = localParticipant ~= nil and not localParticipant.isNpc
		local localReward: RewardEntry? = nil
		for _, reward in result.rewards do
			if reward.userId == localPlayer.UserId then
				localReward = reward
				break
			end
		end
		renderLocalReward(localReward)

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
		updateReturnButton()
		overlay.Visible = true
		GuiService.SelectedObject = if canRequestRematch then rematchButton else returnButton
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

	local function applyRewardResolved(resolved: RewardResolvedPayload)
		if resolved.userId ~= localPlayer.UserId then
			return
		end
		local matchId = currentMatchId
		local currentReward = currentLocalReward
		if
			not matchId
			or resolved.matchId ~= matchId
			or closedMatchIds[resolved.matchId]
			or resolved.serverTime < currentResultTime
			or resolved.serverTime <= latestRewardTime
			or not participantsById[localPlayer.UserId]
			or not currentReward
			or currentReward.userId ~= resolved.userId
			or currentReward.status ~= "Pending"
		then
			return
		end

		latestRewardTime = resolved.serverTime
		renderLocalReward({
			userId = resolved.userId,
			status = resolved.status,
			coins = resolved.coins,
			experience = resolved.experience,
		})
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
	local returnConnection = returnButton.Activated:Connect(function()
		if not requestLobbyActionRemote or not currentMatchId or not overlay.Visible then
			return
		end
		local now = os.clock()
		if now - lastRequestAt < REQUEST_COOLDOWN_SECONDS then
			return
		end
		lastRequestAt = now
		returnPending = true
		updateRematchButton()
		updateReturnButton()
		requestLobbyActionRemote:FireServer({ action = "ReturnToLobby" })
	end)
	local lobbyStateConnection = localPlayer
		:GetAttributeChangedSignal("LobbyState")
		:Connect(function()
			if overlay.Visible and localPlayer:GetAttribute("LobbyState") ~= "InMatch" then
				hideCurrentResult(true)
			end
		end)
	local lobbyEventConnection = if lobbyEventRemote
		then lobbyEventRemote.OnClientEvent:Connect(function(kind: any, payload: any)
			if not returnPending then
				return
			end
			if kind == "Rejected" then
				returnPending = false
				rematchStatusLabel.Text = "RETURN UNAVAILABLE // TRY AGAIN"
				rematchStatusLabel.TextColor3 = WARM_CORAL
				updateRematchButton()
				updateReturnButton()
			elseif kind == "State" and type(payload) == "table" and payload.state == "InMatch" then
				returnPending = false
				updateRematchButton()
				updateReturnButton()
			end
		end)
		else nil
	local scaleConnection = localPlayer
		:GetAttributeChangedSignal("ClientUIScale")
		:Connect(function()
			accessibilityScale.Scale = ClientSettings.readLocal(localPlayer).uiScale
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
			elseif kind == "RewardResolved" then
				local resolved = parseRewardResolved(payload)
				if resolved then
					applyRewardResolved(resolved)
				else
					reportProblem("RewardResolved")
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
			returnConnection:Disconnect()
			lobbyStateConnection:Disconnect()
			if lobbyEventConnection then
				lobbyEventConnection:Disconnect()
			end
			scaleConnection:Disconnect()
			matchEventConnection:Disconnect()
			clearParticipantRows()
			screenGui:Destroy()
		end,
	}

	return controller
end

return ResultsController
