--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientSettings = require(script.Parent.ClientSettings)

local DEEP_TEAL = Color3.fromRGB(15, 107, 109)
local WARM_CORAL = Color3.fromRGB(242, 107, 94)
local CREAM = Color3.fromRGB(255, 241, 213)
local GOLDEN = Color3.fromRGB(246, 196, 71)
local DARK_NAVY = Color3.fromRGB(20, 40, 61)
local MINT = Color3.fromRGB(118, 217, 177)
local IMPACT_WHITE = Color3.fromRGB(255, 253, 246)
local REQUEST_COOLDOWN_SECONDS = 0.2

type LobbyState = "Lobby" | "Queued" | "InMatch"
type QueueMode = "Practice" | "Casual"

export type Controller = {
	openLoadoutRequested: RBXScriptSignal,
	openSettingsRequested: RBXScriptSignal,
	setMatchActive: (active: boolean) -> (),
	destroy: () -> (),
}

local LobbyController = {}

local function addCorner(guiObject: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = guiObject
end

local function addStroke(
	guiObject: GuiObject,
	color: Color3,
	thickness: number,
	transparency: number?
)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0.08
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
	label.TextXAlignment = alignment or Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function createButton(
	parent: Instance,
	name: string,
	text: string,
	position: UDim2,
	size: UDim2,
	background: Color3
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Active = true
	button.AutoButtonColor = false
	button.BackgroundColor3 = background
	button.Position = position
	button.Size = size
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = IMPACT_WHITE
	button.TextScaled = true
	button.Selectable = true
	button.Parent = parent
	addCorner(button, 12)
	addStroke(button, CREAM, 1, 0.18)

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MinTextSize = 11
	textConstraint.MaxTextSize = 18
	textConstraint.Parent = button
	return button
end

local function createModeCard(
	parent: Instance,
	order: number,
	name: string,
	eyebrow: string,
	title: string,
	description: string,
	buttonText: string,
	accent: Color3
): (Frame, TextButton)
	local card = Instance.new("Frame")
	card.Name = name
	card.BackgroundColor3 = DARK_NAVY
	card.BackgroundTransparency = 0.03
	card.LayoutOrder = order
	card.Parent = parent
	addCorner(card, 15)
	addStroke(card, accent, 2, 0.06)

	local accentBar = Instance.new("Frame")
	accentBar.Name = "Accent"
	accentBar.BackgroundColor3 = accent
	accentBar.BorderSizePixel = 0
	accentBar.Size = UDim2.new(1, 0, 0, 7)
	accentBar.Parent = card
	addCorner(accentBar, 15)

	local eyebrowLabel = createLabel(
		card,
		"Eyebrow",
		eyebrow,
		UDim2.fromOffset(18, 19),
		UDim2.new(1, -36, 0, 17),
		11,
		accent
	)
	eyebrowLabel.TextScaled = true
	local eyebrowConstraint = Instance.new("UITextSizeConstraint")
	eyebrowConstraint.MinTextSize = 9
	eyebrowConstraint.MaxTextSize = 11
	eyebrowConstraint.Parent = eyebrowLabel

	local titleLabel = createLabel(
		card,
		"Title",
		title,
		UDim2.fromOffset(18, 39),
		UDim2.new(1, -36, 0, 38),
		27,
		IMPACT_WHITE
	)
	titleLabel.TextScaled = true
	local titleConstraint = Instance.new("UITextSizeConstraint")
	titleConstraint.MinTextSize = 18
	titleConstraint.MaxTextSize = 28
	titleConstraint.Parent = titleLabel

	local descriptionLabel = createLabel(
		card,
		"Description",
		description,
		UDim2.fromOffset(18, 82),
		UDim2.new(1, -36, 1, -145),
		13,
		CREAM
	)
	descriptionLabel.Font = Enum.Font.GothamMedium
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
	descriptionLabel.TextTruncate = Enum.TextTruncate.None

	local button = createButton(
		card,
		"Play",
		buttonText,
		UDim2.new(0, 18, 1, -57),
		UDim2.new(1, -36, 0, 42),
		accent
	)
	button.TextColor3 = if accent == MINT then DARK_NAVY else IMPACT_WHITE
	return card, button
end

local function readLobbyState(player: Player): LobbyState
	local value = player:GetAttribute("LobbyState")
	if value == "Queued" or value == "InMatch" or value == "Lobby" then
		return value
	end
	return "Lobby"
end

local function readQueueMode(player: Player): QueueMode?
	local value = player:GetAttribute("LobbyQueueMode")
	if value == "Practice" or value == "Casual" then
		return value
	end
	return nil
end

local function readFiniteNumber(player: Player, name: string): number?
	local value = player:GetAttribute(name)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

function LobbyController.create(
	requestLobbyActionRemote: RemoteEvent,
	lobbyEventRemote: RemoteEvent
): Controller
	local localPlayer = Players.LocalPlayer
	local playerGuiInstance = localPlayer:WaitForChild("PlayerGui")
	assert(playerGuiInstance:IsA("PlayerGui"), "PlayerGui must be available")

	local openLoadoutEvent = Instance.new("BindableEvent")
	local openSettingsEvent = Instance.new("BindableEvent")
	local connections: { RBXScriptConnection } = {}
	local destroyed = false
	local matchOverride = false
	local lastRequestAt = -math.huge
	local pendingAction: string? = nil
	local messageExpiresAt = 0
	local queueRefreshElapsed = 1
	local lastLobbyVisible = false

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CritterClashLobby"
	screenGui.DisplayOrder = 24
	screenGui.IgnoreGuiInset = false
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGuiInstance

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Active = true
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 25, 39)
	backdrop.BackgroundTransparency = 0.06
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = screenGui

	local backdropGradient = Instance.new("UIGradient")
	backdropGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 26, 42)),
		ColorSequenceKeypoint.new(0.55, DARK_NAVY),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 63, 67)),
	})
	backdropGradient.Rotation = 22
	backdropGradient.Parent = backdrop

	local glow = Instance.new("Frame")
	glow.Name = "SunsetGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.BackgroundColor3 = WARM_CORAL
	glow.BackgroundTransparency = 0.86
	glow.Position = UDim2.fromScale(0.12, 0.18)
	glow.Size = UDim2.fromOffset(250, 250)
	glow.Parent = backdrop
	addCorner(glow, 125)

	local panel = Instance.new("Frame")
	panel.Name = "LobbyPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(17, 42, 58)
	panel.BackgroundTransparency = 0.02
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.92, 0.9)
	panel.Parent = backdrop
	addCorner(panel, 20)
	addStroke(panel, CREAM, 2, 0.12)

	local panelConstraint = Instance.new("UISizeConstraint")
	panelConstraint.MinSize = Vector2.new(300, 430)
	panelConstraint.MaxSize = Vector2.new(920, 610)
	panelConstraint.Parent = panel

	local accessibilityScale = Instance.new("UIScale")
	accessibilityScale.Name = "AccessibilityScale"
	accessibilityScale.Scale = ClientSettings.readLocal(localPlayer).uiScale
	accessibilityScale.Parent = panel

	local eyebrow = createLabel(
		panel,
		"Eyebrow",
		"ORIGINAL ANIMAL ARTILLERY",
		UDim2.fromOffset(24, 18),
		UDim2.new(1, -48, 0, 18),
		11,
		GOLDEN
	)
	eyebrow.TextScaled = true
	local eyebrowConstraint = Instance.new("UITextSizeConstraint")
	eyebrowConstraint.MinTextSize = 9
	eyebrowConstraint.MaxTextSize = 11
	eyebrowConstraint.Parent = eyebrow

	local title = createLabel(
		panel,
		"Title",
		"CRITTER CLASH",
		UDim2.fromOffset(24, 36),
		UDim2.new(0.66, -24, 0, 48),
		38,
		IMPACT_WHITE
	)
	title.TextScaled = true
	local titleConstraint = Instance.new("UITextSizeConstraint")
	titleConstraint.MinTextSize = 24
	titleConstraint.MaxTextSize = 40
	titleConstraint.Parent = title

	createLabel(
		panel,
		"Welcome",
		`READY, {string.upper(localPlayer.DisplayName)}?`,
		UDim2.fromOffset(26, 84),
		UDim2.new(0.66, -26, 0, 22),
		13,
		MINT
	)

	local statePill = Instance.new("Frame")
	statePill.Name = "StatePill"
	statePill.AnchorPoint = Vector2.new(1, 0)
	statePill.BackgroundColor3 = DEEP_TEAL
	statePill.Position = UDim2.new(1, -24, 0, 25)
	statePill.Size = UDim2.new(0.29, 0, 0, 54)
	statePill.Parent = panel
	addCorner(statePill, 13)
	addStroke(statePill, MINT, 1, 0.2)
	local stateLabel = createLabel(
		statePill,
		"State",
		"FIELD CAMP",
		UDim2.fromOffset(10, 7),
		UDim2.new(1, -20, 0, 18),
		12,
		MINT,
		Enum.TextXAlignment.Center
	)
	local substateLabel = createLabel(
		statePill,
		"Detail",
		"CHOOSE A MODE",
		UDim2.fromOffset(10, 27),
		UDim2.new(1, -20, 0, 18),
		10,
		CREAM,
		Enum.TextXAlignment.Center
	)

	local modes = Instance.new("Frame")
	modes.Name = "Modes"
	modes.BackgroundTransparency = 1
	modes.Position = UDim2.fromOffset(24, 122)
	modes.Size = UDim2.new(1, -48, 1, -270)
	modes.Parent = panel

	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(14, 12)
	grid.CellSize = UDim2.new(0.5, -7, 1, 0)
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.FillDirectionMaxCells = 2
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = modes

	local _, practiceButton = createModeCard(
		modes,
		1,
		"PracticeCard",
		"INSTANT // BOT DUEL",
		"PRACTICE",
		"Learn the arena, test wind reads, and sharpen every shot against a field bot.",
		"ENTER PRACTICE",
		MINT
	)
	local _, casualButton = createModeCard(
		modes,
		2,
		"CasualCard",
		"SAME SERVER // FAIR PLAY",
		"CASUAL DUEL",
		"Queue for another player. If the field is quiet, a bot fills the opposing side.",
		"FIND A RIVAL",
		WARM_CORAL
	)

	local nav = Instance.new("Frame")
	nav.Name = "Navigation"
	nav.BackgroundTransparency = 1
	nav.Position = UDim2.new(0, 24, 1, -136)
	nav.Size = UDim2.new(1, -48, 0, 46)
	nav.Parent = panel
	local loadoutButton = createButton(
		nav,
		"Loadout",
		"LOADOUT",
		UDim2.fromScale(0, 0),
		UDim2.new(0.5, -7, 1, 0),
		DEEP_TEAL
	)
	local settingsButton = createButton(
		nav,
		"Settings",
		"SETTINGS",
		UDim2.new(0.5, 7, 0, 0),
		UDim2.new(0.5, -7, 1, 0),
		DEEP_TEAL
	)

	local queueBar = Instance.new("Frame")
	queueBar.Name = "QueueBar"
	queueBar.BackgroundColor3 = Color3.fromRGB(10, 31, 46)
	queueBar.Position = UDim2.new(0, 24, 1, -78)
	queueBar.Size = UDim2.new(1, -48, 0, 55)
	queueBar.Parent = panel
	addCorner(queueBar, 13)
	addStroke(queueBar, DEEP_TEAL, 1, 0.2)
	local queueLabel = createLabel(
		queueBar,
		"QueueStatus",
		"CHOOSE A MODE TO DEPLOY",
		UDim2.fromOffset(15, 6),
		UDim2.new(1, -170, 0, 23),
		13,
		CREAM
	)
	local queueHint = createLabel(
		queueBar,
		"QueueHint",
		"Practice is instant. Casual searches this server.",
		UDim2.fromOffset(15, 29),
		UDim2.new(1, -170, 0, 17),
		10,
		MINT
	)
	queueHint.Font = Enum.Font.GothamMedium
	local cancelButton = createButton(
		queueBar,
		"Cancel",
		"CANCEL",
		UDim2.new(1, -142, 0, 7),
		UDim2.fromOffset(128, 41),
		WARM_CORAL
	)
	cancelButton.Visible = false

	local function lobbyVisible(): boolean
		return not matchOverride and readLobbyState(localPlayer) ~= "InMatch"
	end

	local function updateResponsiveLayout()
		if destroyed then
			return
		end
		local camera = Workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1_280, 720)
		local scale = ClientSettings.readLocal(localPlayer).uiScale
		accessibilityScale.Scale = scale
		local visualWidth = math.clamp(viewport.X * 0.92, 300, 920)
		local visualHeight = math.clamp(viewport.Y * 0.9, 430, 610)
		panel.Size = UDim2.fromOffset(visualWidth / scale, visualHeight / scale)

		if visualWidth < 610 then
			grid.FillDirectionMaxCells = 1
			grid.CellSize = UDim2.new(1, 0, 0.5, -6)
			grid.CellPadding = UDim2.fromOffset(0, 12)
		else
			grid.FillDirectionMaxCells = 2
			grid.CellSize = UDim2.new(0.5, -7, 1, 0)
			grid.CellPadding = UDim2.fromOffset(14, 0)
		end
	end

	local function setMessage(text: string, color: Color3, duration: number)
		queueLabel.Text = text
		queueLabel.TextColor3 = color
		messageExpiresAt = Workspace:GetServerTimeNow() + duration
	end

	local function updateState()
		if destroyed then
			return
		end
		local visible = lobbyVisible()
		local becameVisible = visible and not lastLobbyVisible
		backdrop.Visible = visible
		lastLobbyVisible = visible
		if becameVisible then
			task.defer(function()
				if not destroyed and backdrop.Visible then
					GuiService.SelectedObject = practiceButton
				end
			end)
		end
		if not backdrop.Visible then
			return
		end

		local state = readLobbyState(localPlayer)
		local mode = readQueueMode(localPlayer)
		local queued = state == "Queued"
		practiceButton.Active = not queued
		casualButton.Active = not queued
		practiceButton.BackgroundColor3 = if queued then DARK_NAVY else MINT
		practiceButton.TextColor3 = DARK_NAVY
		casualButton.BackgroundColor3 = if queued then DARK_NAVY else WARM_CORAL
		practiceButton.Text = if pendingAction == "Practice"
			then "DEPLOYING..."
			else "ENTER PRACTICE"
		casualButton.Text = if pendingAction == "Casual" then "SEARCHING..." else "FIND A RIVAL"
		cancelButton.Visible = queued
		cancelButton.Active = queued

		if queued then
			pendingAction = nil
			stateLabel.Text = "MATCHMAKING"
			stateLabel.TextColor3 = GOLDEN
			substateLabel.Text = if mode == "Casual" then "CASUAL QUEUE" else "PRACTICE"
			if Workspace:GetServerTimeNow() >= messageExpiresAt then
				queueLabel.Text = if mode == "Casual"
					then "SCOUTING FOR A RIVAL"
					else "PREPARING BOT DUEL"
				queueLabel.TextColor3 = GOLDEN
			end
		else
			pendingAction = nil
			stateLabel.Text = "FIELD CAMP"
			stateLabel.TextColor3 = MINT
			substateLabel.Text = "CHOOSE A MODE"
			if Workspace:GetServerTimeNow() >= messageExpiresAt then
				queueLabel.Text = "CHOOSE A MODE TO DEPLOY"
				queueLabel.TextColor3 = CREAM
				queueHint.Text = "Practice is instant. Casual searches this server."
			end
		end
	end

	local function refreshQueueClock()
		if readLobbyState(localPlayer) ~= "Queued" then
			return
		end
		local mode = readQueueMode(localPlayer)
		local deadline = readFiniteNumber(localPlayer, "LobbyQueueDeadline")
		local position = readFiniteNumber(localPlayer, "LobbyQueuePosition")
		if mode == "Casual" and deadline then
			local remaining = math.max(0, deadline - Workspace:GetServerTimeNow())
			queueHint.Text = if remaining > 0
				then string.format("Player search %.1fs // then a bot fills the field", remaining)
				else "Finalizing the best available matchup..."
		elseif position and position >= 1 then
			queueHint.Text =
				string.format("Queue position %d // keep this field camp open", position)
		else
			queueHint.Text = "Reserving an arena..."
		end
	end

	local function request(action: string)
		if destroyed or not backdrop.Visible then
			return
		end
		local now = os.clock()
		if now - lastRequestAt < REQUEST_COOLDOWN_SECONDS then
			return
		end
		lastRequestAt = now
		pendingAction = action
		if action == "Cancel" then
			local payload: { [string]: any } = { action = action }
			local queueToken = localPlayer:GetAttribute("LobbyQueueToken")
			if type(queueToken) == "string" and queueToken ~= "" then
				payload.queueToken = queueToken
			end
			requestLobbyActionRemote:FireServer(payload)
			setMessage("CANCELING QUEUE...", CREAM, 1.5)
		else
			requestLobbyActionRemote:FireServer({ action = action })
			setMessage(
				if action == "Practice" then "PREPARING PRACTICE..." else "JOINING CASUAL QUEUE...",
				GOLDEN,
				1.5
			)
		end
		updateState()
	end

	table.insert(
		connections,
		practiceButton.Activated:Connect(function()
			if readLobbyState(localPlayer) ~= "Queued" then
				request("Practice")
			end
		end)
	)
	table.insert(
		connections,
		casualButton.Activated:Connect(function()
			if readLobbyState(localPlayer) ~= "Queued" then
				request("Casual")
			end
		end)
	)
	table.insert(
		connections,
		cancelButton.Activated:Connect(function()
			request("Cancel")
		end)
	)
	table.insert(
		connections,
		loadoutButton.Activated:Connect(function()
			openLoadoutEvent:Fire()
		end)
	)
	table.insert(
		connections,
		settingsButton.Activated:Connect(function()
			openSettingsEvent:Fire()
		end)
	)
	table.insert(
		connections,
		lobbyEventRemote.OnClientEvent:Connect(function(kind: any, payload: any)
			if kind == "State" and type(payload) == "table" then
				local rawState = payload.state
				if rawState == "Lobby" then
					setMessage("WELCOME BACK TO FIELD CAMP", MINT, 2)
				elseif rawState == "Queued" then
					setMessage("QUEUE CONFIRMED", GOLDEN, 1.5)
				elseif rawState == "InMatch" then
					matchOverride = true
				end
			elseif kind == "Rejected" then
				pendingAction = nil
				setMessage("ACTION UNAVAILABLE // TRY AGAIN", WARM_CORAL, 2.5)
			end
			updateState()
		end)
	)
	for _, attributeName in
		{
			"LobbyState",
			"LobbyQueueMode",
			"LobbyQueueDeadline",
			"LobbyQueuePosition",
			"LobbyQueueToken",
		}
	do
		table.insert(
			connections,
			localPlayer:GetAttributeChangedSignal(attributeName):Connect(function()
				if attributeName == "LobbyState" and readLobbyState(localPlayer) ~= "InMatch" then
					matchOverride = false
				end
				updateState()
				refreshQueueClock()
			end)
		)
	end
	table.insert(
		connections,
		localPlayer:GetAttributeChangedSignal("ClientUIScale"):Connect(updateResponsiveLayout)
	)
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed or not backdrop.Visible then
				return
			end
			if input.KeyCode == Enum.KeyCode.P then
				request("Practice")
			elseif input.KeyCode == Enum.KeyCode.C then
				request("Casual")
			elseif input.KeyCode == Enum.KeyCode.L then
				openLoadoutEvent:Fire()
			elseif input.KeyCode == Enum.KeyCode.S then
				openSettingsEvent:Fire()
			elseif
				input.KeyCode == Enum.KeyCode.Escape and readLobbyState(localPlayer) == "Queued"
			then
				request("Cancel")
			end
		end)
	)
	local camera = Workspace.CurrentCamera
	if camera then
		table.insert(
			connections,
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveLayout)
		)
	end
	table.insert(
		connections,
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			updateResponsiveLayout()
		end)
	)

	local heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if destroyed or not backdrop.Visible then
			return
		end
		queueRefreshElapsed += deltaTime
		if queueRefreshElapsed >= 0.1 then
			queueRefreshElapsed = 0
			refreshQueueClock()
			if messageExpiresAt > 0 and Workspace:GetServerTimeNow() >= messageExpiresAt then
				messageExpiresAt = 0
				updateState()
			end
		end
	end)

	updateResponsiveLayout()
	updateState()
	if backdrop.Visible then
		GuiService.SelectedObject = practiceButton
	end

	return {
		openLoadoutRequested = openLoadoutEvent.Event,
		openSettingsRequested = openSettingsEvent.Event,
		setMatchActive = function(active: boolean)
			matchOverride = active
			updateState()
		end,
		destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			heartbeatConnection:Disconnect()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			openLoadoutEvent:Destroy()
			openSettingsEvent:Destroy()
			screenGui:Destroy()
		end,
	}
end

return LobbyController
