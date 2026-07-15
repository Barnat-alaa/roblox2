--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local ClientSettings = require(script.Parent.ClientSettings)

local DEEP_TEAL = Color3.fromRGB(15, 107, 109)
local WARM_CORAL = Color3.fromRGB(242, 107, 94)
local CREAM = Color3.fromRGB(255, 241, 213)
local GOLDEN = Color3.fromRGB(246, 196, 71)
local DARK_NAVY = Color3.fromRGB(20, 40, 61)
local MINT = Color3.fromRGB(118, 217, 177)
local IMPACT_WHITE = Color3.fromRGB(255, 253, 246)
local SEND_DEBOUNCE_SECONDS = 1.05
local ATTRIBUTE_SETTLE_SECONDS = 0.8

export type Values = ClientSettings.Values

export type Controller = {
	changed: RBXScriptSignal,
	getSettings: () -> Values,
	setOpen: (open: boolean) -> (),
	isOpen: () -> boolean,
	destroy: () -> (),
}

local SettingsController = {}

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
	size: UDim2
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Active = true
	button.AutoButtonColor = false
	button.BackgroundColor3 = DEEP_TEAL
	button.Position = position
	button.Size = size
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = IMPACT_WHITE
	button.TextSize = 18
	button.Selectable = true
	button.Parent = parent
	addCorner(button, 11)
	addStroke(button, CREAM, 1, 0.18)
	return button
end

local function addRow(
	parent: Instance,
	order: number,
	title: string,
	description: string
): (Frame, Frame)
	local row = Instance.new("Frame")
	row.Name = title:gsub("%s", "")
	row.BackgroundColor3 = DEEP_TEAL
	row.BackgroundTransparency = 0.78
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 88)
	row.Parent = parent
	addCorner(row, 13)
	addStroke(row, DEEP_TEAL, 1, 0.25)

	createLabel(row, "Title", title, UDim2.fromOffset(16, 11), UDim2.new(1, -190, 0, 25), 18, CREAM)
	local detail = createLabel(
		row,
		"Description",
		description,
		UDim2.fromOffset(16, 38),
		UDim2.new(1, -190, 0, 38),
		12,
		MINT
	)
	detail.Font = Enum.Font.GothamMedium
	detail.TextWrapped = true
	detail.TextYAlignment = Enum.TextYAlignment.Top

	local controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.AnchorPoint = Vector2.new(1, 0.5)
	controls.BackgroundTransparency = 1
	controls.Position = UDim2.new(1, -14, 0.5, 0)
	controls.Size = UDim2.fromOffset(164, 48)
	controls.Parent = row
	return row, controls
end

function SettingsController.create(
	requestSettingsRemote: RemoteEvent,
	lobbyEventRemote: RemoteEvent?
): Controller
	local localPlayer = Players.LocalPlayer
	local playerGuiInstance = localPlayer:WaitForChild("PlayerGui")
	assert(playerGuiInstance:IsA("PlayerGui"), "PlayerGui must be available")

	local changedEvent = Instance.new("BindableEvent")
	local connections: { RBXScriptConnection } = {}
	local values = ClientSettings.fromPlayer(localPlayer)
	local open = false
	local destroyed = false
	local sendRevision = 0
	local syncRevision = 0
	local editRevision = 0
	local settledRevision = 0
	local inFlightRevision: number? = nil
	local optimisticUntil = -math.huge
	local previousSelection: GuiObject? = nil

	ClientSettings.publishLocal(localPlayer, values)

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CritterClashSettings"
	screenGui.DisplayOrder = 52
	screenGui.IgnoreGuiInset = false
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGuiInstance

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Active = true
	overlay.BackgroundColor3 = Color3.fromRGB(6, 18, 30)
	overlay.BackgroundTransparency = 0.18
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Visible = false
	overlay.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "SettingsPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = DARK_NAVY
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.9, 0.88)
	panel.Parent = overlay
	addCorner(panel, 18)
	addStroke(panel, CREAM, 2)

	local panelConstraint = Instance.new("UISizeConstraint")
	panelConstraint.MinSize = Vector2.new(300, 430)
	panelConstraint.MaxSize = Vector2.new(650, 570)
	panelConstraint.Parent = panel

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "AccessibilityScale"
	uiScale.Scale = values.uiScale
	uiScale.Parent = panel

	createLabel(
		panel,
		"Eyebrow",
		"FIELD KIT // ACCESSIBILITY",
		UDim2.fromOffset(24, 17),
		UDim2.new(1, -100, 0, 18),
		11,
		GOLDEN
	)
	createLabel(
		panel,
		"Title",
		"SETTINGS",
		UDim2.fromOffset(24, 34),
		UDim2.new(1, -100, 0, 42),
		34,
		IMPACT_WHITE
	)

	local closeButton =
		createButton(panel, "Close", "CLOSE", UDim2.new(1, -92, 0, 22), UDim2.fromOffset(68, 40))
	closeButton.TextSize = 12

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundColor3 = DEEP_TEAL
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromOffset(24, 82)
	divider.Size = UDim2.new(1, -48, 0, 2)
	divider.Parent = panel

	local list = Instance.new("Frame")
	list.Name = "SettingRows"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(24, 98)
	list.Size = UDim2.new(1, -48, 1, -156)
	list.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 10)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	listLayout.Parent = list

	local _, effectsControls = addRow(
		list,
		1,
		"Reduced effects",
		"Softens impact flashes and removes decorative burst layers."
	)
	local effectsButton =
		createButton(effectsControls, "Toggle", "OFF", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))

	local _, shakeControls = addRow(
		list,
		2,
		"Camera shake",
		"Choose the impact punch. Projectile tracking stays smooth."
	)
	local shakeDown = createButton(
		shakeControls,
		"Decrease",
		"-",
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(44, 48)
	)
	local shakeValue = createLabel(
		shakeControls,
		"Value",
		"65%",
		UDim2.fromOffset(47, 0),
		UDim2.fromOffset(70, 48),
		17,
		CREAM,
		Enum.TextXAlignment.Center
	)
	local shakeUp = createButton(
		shakeControls,
		"Increase",
		"+",
		UDim2.fromOffset(120, 0),
		UDim2.fromOffset(44, 48)
	)

	local _, scaleControls = addRow(
		list,
		3,
		"Interface scale",
		"Resize menus and combat readouts for comfortable viewing."
	)
	local scaleDown = createButton(
		scaleControls,
		"Decrease",
		"-",
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(44, 48)
	)
	local scaleValue = createLabel(
		scaleControls,
		"Value",
		"100%",
		UDim2.fromOffset(47, 0),
		UDim2.fromOffset(70, 48),
		17,
		CREAM,
		Enum.TextXAlignment.Center
	)
	local scaleUp = createButton(
		scaleControls,
		"Increase",
		"+",
		UDim2.fromOffset(120, 0),
		UDim2.fromOffset(44, 48)
	)

	local statusLabel = createLabel(
		panel,
		"Status",
		"APPLIED LOCALLY",
		UDim2.new(0, 24, 1, -43),
		UDim2.new(1, -48, 0, 22),
		11,
		MINT,
		Enum.TextXAlignment.Center
	)

	local function render()
		effectsButton.Text = if values.reducedEffects then "ON" else "OFF"
		effectsButton.BackgroundColor3 = if values.reducedEffects then MINT else DEEP_TEAL
		effectsButton.TextColor3 = if values.reducedEffects then DARK_NAVY else IMPACT_WHITE
		shakeValue.Text = string.format("%d%%", math.floor(values.cameraShake * 100 + 0.5))
		scaleValue.Text = string.format("%d%%", math.floor(values.uiScale * 100 + 0.5))
		uiScale.Scale = values.uiScale
	end

	local function fireChanged()
		ClientSettings.publishLocal(localPlayer, values)
		changedEvent:Fire(ClientSettings.copy(values))
		render()
	end

	local function sendEventually()
		sendRevision += 1
		local revision = sendRevision
		statusLabel.Text = "APPLIED INSTANTLY // SAVING"
		statusLabel.TextColor3 = GOLDEN
		task.delay(SEND_DEBOUNCE_SECONDS, function()
			if destroyed or revision ~= sendRevision then
				return
			end
			if inFlightRevision ~= nil or editRevision <= settledRevision then
				return
			end
			inFlightRevision = editRevision
			requestSettingsRemote:FireServer(ClientSettings.copy(values))
			statusLabel.Text = "APPLIED INSTANTLY // SYNCING"
		end)
	end

	local function update(nextValues: Values)
		values = ClientSettings.sanitize(nextValues)
		editRevision += 1
		optimisticUntil = os.clock() + ATTRIBUTE_SETTLE_SECONDS
		fireChanged()
		sendEventually()
	end

	local function syncFromAttributes()
		if destroyed then
			return
		end
		values = ClientSettings.fromPlayer(localPlayer)
		fireChanged()
		statusLabel.Text = "SAVED TO FIELD PROFILE"
		statusLabel.TextColor3 = MINT
	end

	local function scheduleAttributeSync()
		syncRevision += 1
		local revision = syncRevision
		local delaySeconds = math.max(0, optimisticUntil - os.clock())
		task.delay(delaySeconds, function()
			if destroyed or revision ~= syncRevision then
				return
			end
			if editRevision > settledRevision then
				return
			end
			syncFromAttributes()
		end)
	end

	local function setOpen(nextOpen: boolean)
		if destroyed or open == nextOpen then
			return
		end
		if nextOpen and localPlayer:GetAttribute("LobbyState") == "InMatch" then
			return
		end
		open = nextOpen
		overlay.Visible = open
		if open then
			previousSelection = GuiService.SelectedObject
			GuiService.SelectedObject = effectsButton
		else
			if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(overlay) then
				GuiService.SelectedObject = previousSelection
			end
			previousSelection = nil
		end
	end

	table.insert(
		connections,
		effectsButton.Activated:Connect(function()
			local nextValues = ClientSettings.copy(values)
			nextValues.reducedEffects = not nextValues.reducedEffects
			update(nextValues)
		end)
	)
	table.insert(
		connections,
		shakeDown.Activated:Connect(function()
			local nextValues = ClientSettings.copy(values)
			nextValues.cameraShake =
				math.max(0, math.round((nextValues.cameraShake - 0.25) * 4) / 4)
			update(nextValues)
		end)
	)
	table.insert(
		connections,
		shakeUp.Activated:Connect(function()
			local nextValues = ClientSettings.copy(values)
			nextValues.cameraShake =
				math.min(1, math.round((nextValues.cameraShake + 0.25) * 4) / 4)
			update(nextValues)
		end)
	)
	table.insert(
		connections,
		scaleDown.Activated:Connect(function()
			local nextValues = ClientSettings.copy(values)
			nextValues.uiScale = math.max(
				ClientSettings.MIN_UI_SCALE,
				math.round((nextValues.uiScale - 0.1) * 10) / 10
			)
			update(nextValues)
		end)
	)
	table.insert(
		connections,
		scaleUp.Activated:Connect(function()
			local nextValues = ClientSettings.copy(values)
			nextValues.uiScale = math.min(
				ClientSettings.MAX_UI_SCALE,
				math.round((nextValues.uiScale + 0.1) * 10) / 10
			)
			update(nextValues)
		end)
	)
	table.insert(
		connections,
		closeButton.Activated:Connect(function()
			setOpen(false)
		end)
	)
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and open and input.KeyCode == Enum.KeyCode.Escape then
				setOpen(false)
			end
		end)
	)
	for _, attributeName in
		{
			"SettingReducedEffects",
			"SettingCameraShake",
			"SettingUIScale",
		}
	do
		table.insert(
			connections,
			localPlayer:GetAttributeChangedSignal(attributeName):Connect(scheduleAttributeSync)
		)
	end
	if lobbyEventRemote then
		table.insert(
			connections,
			lobbyEventRemote.OnClientEvent:Connect(function(kind: any, payload: any)
				if
					kind ~= "ProfileActionResult"
					or type(payload) ~= "table"
					or payload.action ~= "Settings"
				then
					return
				end
				local acknowledgedRevision = inFlightRevision
				if acknowledgedRevision == nil then
					return
				end
				inFlightRevision = nil
				settledRevision = math.max(settledRevision, acknowledgedRevision)
				sendRevision += 1
				if editRevision > settledRevision then
					statusLabel.Text = "LATEST CHANGE // SAVING"
					statusLabel.TextColor3 = GOLDEN
					sendEventually()
					return
				end
				optimisticUntil = -math.huge
				syncFromAttributes()
				if payload.status == "Applied" then
					statusLabel.Text = "SAVED TO FIELD PROFILE"
					statusLabel.TextColor3 = MINT
				elseif payload.status == "ReadOnly" then
					statusLabel.Text = "PROFILE IS READ ONLY // CHANGE REVERTED"
					statusLabel.TextColor3 = WARM_CORAL
				elseif payload.status == "Unavailable" then
					statusLabel.Text = "PROFILE UNAVAILABLE // CHANGE REVERTED"
					statusLabel.TextColor3 = WARM_CORAL
				else
					statusLabel.Text = "COULD NOT SAVE // CHANGE REVERTED"
					statusLabel.TextColor3 = WARM_CORAL
				end
			end)
		)
	end
	table.insert(
		connections,
		localPlayer:GetAttributeChangedSignal("LobbyState"):Connect(function()
			if localPlayer:GetAttribute("LobbyState") == "InMatch" then
				setOpen(false)
			end
		end)
	)

	render()

	return {
		changed = changedEvent.Event,
		getSettings = function(): Values
			return ClientSettings.copy(values)
		end,
		setOpen = setOpen,
		isOpen = function(): boolean
			return open
		end,
		destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			changedEvent:Destroy()
			screenGui:Destroy()
		end,
	}
end

return SettingsController
