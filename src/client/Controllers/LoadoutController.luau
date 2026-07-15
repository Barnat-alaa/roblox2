--!strict

local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local ClientSettings = require(script.Parent.ClientSettings)

local DEEP_TEAL = Color3.fromRGB(15, 107, 109)
local WARM_CORAL = Color3.fromRGB(242, 107, 94)
local CREAM = Color3.fromRGB(255, 241, 213)
local GOLDEN = Color3.fromRGB(246, 196, 71)
local DARK_NAVY = Color3.fromRGB(20, 40, 61)
local MINT = Color3.fromRGB(118, 217, 177)
local IMPACT_WHITE = Color3.fromRGB(255, 253, 246)
local REQUEST_COOLDOWN_SECONDS = 1.05

type CosmeticDefinition = Cosmetics.CosmeticDefinition

export type Controller = {
	setOpen: (open: boolean) -> (),
	isOpen: () -> boolean,
	destroy: () -> (),
}

local LoadoutController = {}

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
	button.TextSize = 16
	button.Selectable = true
	button.Parent = parent
	addCorner(button, 11)
	addStroke(button, CREAM, 1, 0.18)
	return button
end

local function parseOwned(value: any): ({ string }, boolean)
	if value == nil then
		return {}, true
	end
	if type(value) ~= "string" or #value > 4_096 then
		return {}, false
	end

	local source: any = nil
	if value:sub(1, 1) == "[" then
		local decoded, result = pcall(HttpService.JSONDecode, HttpService, value)
		if decoded and type(result) == "table" then
			source = result
		else
			return {}, false
		end
	else
		source = string.split(value, ",")
	end

	local result: { string } = {}
	local seen: { [string]: boolean } = {}
	for index, rawId in source do
		if
			type(index) ~= "number"
			or index ~= math.floor(index)
			or index < 1
			or type(rawId) ~= "string"
			or #result >= Cosmetics.MAX_OWNED_COSMETICS
		then
			return {}, false
		end
		local id = rawId:match("^%s*(.-)%s*$") or ""
		local definition = Cosmetics.get(id)
		if not definition or not definition.enabled or seen[id] then
			return {}, false
		end
		seen[id] = true
		table.insert(result, id)
	end
	return result, true
end

local function addScarfPreview(parent: Instance, definition: CosmeticDefinition)
	local preview = Instance.new("Frame")
	preview.Name = "OriginalScarfPreview"
	preview.AnchorPoint = Vector2.new(0.5, 0.5)
	preview.BackgroundColor3 = Color3.fromRGB(24, 55, 69)
	preview.Position = UDim2.fromScale(0.5, 0.5)
	preview.Size = UDim2.fromOffset(170, 170)
	preview.Parent = parent
	addCorner(preview, 85)
	addStroke(preview, definition.accentColor, 2, 0.08)

	local head = Instance.new("Frame")
	head.Name = "CritterSilhouette"
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.BackgroundColor3 = CREAM
	head.Position = UDim2.fromScale(0.5, 0.44)
	head.Size = UDim2.fromOffset(90, 90)
	head.Parent = preview
	addCorner(head, 45)

	local scarfBand = Instance.new("Frame")
	scarfBand.Name = "ScarfBand"
	scarfBand.AnchorPoint = Vector2.new(0.5, 0.5)
	scarfBand.BackgroundColor3 = definition.primaryColor
	scarfBand.Position = UDim2.fromScale(0.5, 0.61)
	scarfBand.Size = UDim2.fromOffset(106, 25)
	scarfBand.Rotation = -4
	scarfBand.Parent = preview
	addCorner(scarfBand, 10)
	addStroke(scarfBand, definition.accentColor, 2, 0)

	local knot = Instance.new("Frame")
	knot.Name = "Knot"
	knot.AnchorPoint = Vector2.new(0.5, 0.5)
	knot.BackgroundColor3 = definition.accentColor
	knot.Position = UDim2.fromScale(0.71, 0.64)
	knot.Size = UDim2.fromOffset(27, 27)
	knot.Rotation = 45
	knot.Parent = preview
	addCorner(knot, 7)

	for index, rotation in { 10, 24 } do
		local tail = Instance.new("Frame")
		tail.Name = `Tail{index}`
		tail.AnchorPoint = Vector2.new(0.5, 0)
		tail.BackgroundColor3 = if index == 1
			then definition.primaryColor
			else definition.accentColor
		tail.Position = UDim2.fromScale(0.72, 0.67)
		tail.Size = UDim2.fromOffset(22, if index == 1 then 52 else 43)
		tail.Rotation = rotation
		tail.Parent = preview
		addCorner(tail, 6)
	end

	local stitch = createLabel(
		scarfBand,
		"Stitch",
		"*",
		UDim2.fromScale(0, 0),
		UDim2.fromScale(1, 1),
		18,
		definition.accentColor,
		Enum.TextXAlignment.Center
	)
	stitch.TextYAlignment = Enum.TextYAlignment.Center
end

function LoadoutController.create(
	requestEquipCosmeticRemote: RemoteEvent,
	lobbyEventRemote: RemoteEvent?
): Controller
	local localPlayer = Players.LocalPlayer
	local playerGuiInstance = localPlayer:WaitForChild("PlayerGui")
	assert(playerGuiInstance:IsA("PlayerGui"), "PlayerGui must be available")

	local connections: { RBXScriptConnection } = {}
	local itemButtons: { [string]: TextButton } = {}
	local open = false
	local destroyed = false
	local selectedId: string? = nil
	local equippedId: string? = nil
	local ownedIds: { string } = {}
	local lastRequestAt = -math.huge
	local previousSelection: GuiObject? = nil

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CritterClashLoadout"
	screenGui.DisplayOrder = 51
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
	panel.Name = "LoadoutPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = DARK_NAVY
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.9, 0.86)
	panel.Parent = overlay
	addCorner(panel, 18)
	addStroke(panel, CREAM, 2)

	local panelConstraint = Instance.new("UISizeConstraint")
	panelConstraint.MinSize = Vector2.new(300, 430)
	panelConstraint.MaxSize = Vector2.new(720, 560)
	panelConstraint.Parent = panel

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "AccessibilityScale"
	uiScale.Scale = ClientSettings.readLocal(localPlayer).uiScale
	uiScale.Parent = panel

	createLabel(
		panel,
		"Eyebrow",
		"FIELD KIT // COSMETICS",
		UDim2.fromOffset(24, 17),
		UDim2.new(1, -110, 0, 18),
		11,
		GOLDEN
	)
	createLabel(
		panel,
		"Title",
		"LOADOUT",
		UDim2.fromOffset(24, 34),
		UDim2.new(1, -110, 0, 42),
		34,
		IMPACT_WHITE
	)
	local closeButton = createButton(
		panel,
		"Close",
		"CLOSE",
		UDim2.new(1, -92, 0, 22),
		UDim2.fromOffset(68, 40),
		DEEP_TEAL
	)
	closeButton.TextSize = 12

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(24, 90)
	content.Size = UDim2.new(1, -48, 1, -114)
	content.Parent = panel

	local catalog = Instance.new("ScrollingFrame")
	catalog.Name = "OwnedCosmetics"
	catalog.BackgroundColor3 = Color3.fromRGB(10, 31, 46)
	catalog.BackgroundTransparency = 0.12
	catalog.BorderSizePixel = 0
	catalog.Size = UDim2.new(0.42, -7, 1, -58)
	catalog.AutomaticCanvasSize = Enum.AutomaticSize.Y
	catalog.CanvasSize = UDim2.fromOffset(0, 0)
	catalog.ScrollBarImageColor3 = MINT
	catalog.ScrollBarThickness = 5
	catalog.Parent = content
	addCorner(catalog, 13)
	addStroke(catalog, DEEP_TEAL, 1, 0.2)

	local catalogPadding = Instance.new("UIPadding")
	catalogPadding.PaddingTop = UDim.new(0, 12)
	catalogPadding.PaddingBottom = UDim.new(0, 12)
	catalogPadding.PaddingLeft = UDim.new(0, 12)
	catalogPadding.PaddingRight = UDim.new(0, 12)
	catalogPadding.Parent = catalog
	local catalogList = Instance.new("UIListLayout")
	catalogList.Padding = UDim.new(0, 9)
	catalogList.SortOrder = Enum.SortOrder.LayoutOrder
	catalogList.Parent = catalog

	local previewPanel = Instance.new("Frame")
	previewPanel.Name = "PreviewPanel"
	previewPanel.BackgroundColor3 = Color3.fromRGB(10, 31, 46)
	previewPanel.BackgroundTransparency = 0.12
	previewPanel.Position = UDim2.new(0.42, 7, 0, 0)
	previewPanel.Size = UDim2.new(0.58, -7, 1, -58)
	previewPanel.Parent = content
	addCorner(previewPanel, 13)
	addStroke(previewPanel, DEEP_TEAL, 1, 0.2)

	local artHolder = Instance.new("Frame")
	artHolder.Name = "Art"
	artHolder.BackgroundTransparency = 1
	artHolder.Size = UDim2.fromScale(1, 0.55)
	artHolder.Parent = previewPanel

	local itemName = createLabel(
		previewPanel,
		"ItemName",
		"SYNCING FIELD KIT",
		UDim2.new(0, 16, 0.56, 0),
		UDim2.new(1, -32, 0, 29),
		20,
		IMPACT_WHITE,
		Enum.TextXAlignment.Center
	)
	itemName.TextScaled = true
	local nameConstraint = Instance.new("UITextSizeConstraint")
	nameConstraint.MinTextSize = 14
	nameConstraint.MaxTextSize = 21
	nameConstraint.Parent = itemName
	local itemDescription = createLabel(
		previewPanel,
		"Description",
		"Your owned cosmetic kit is loading.",
		UDim2.new(0, 18, 0.67, 0),
		UDim2.new(1, -36, 0.22, 0),
		12,
		CREAM,
		Enum.TextXAlignment.Center
	)
	itemDescription.Font = Enum.Font.GothamMedium
	itemDescription.TextWrapped = true
	itemDescription.TextYAlignment = Enum.TextYAlignment.Top
	local equippedBadge = createLabel(
		previewPanel,
		"EquippedBadge",
		"",
		UDim2.new(0, 16, 1, -36),
		UDim2.new(1, -32, 0, 22),
		11,
		MINT,
		Enum.TextXAlignment.Center
	)

	local equipButton = createButton(
		content,
		"Equip",
		"SELECT AN ITEM",
		UDim2.new(0.42, 7, 1, -47),
		UDim2.new(0.58, -7, 0, 47),
		DEEP_TEAL
	)
	local collectionLabel = createLabel(
		content,
		"Collection",
		"ORIGINAL COSMETICS // OWNED 0",
		UDim2.new(0, 0, 1, -47),
		UDim2.new(0.42, -7, 0, 47),
		11,
		GOLDEN,
		Enum.TextXAlignment.Center
	)
	collectionLabel.TextWrapped = true

	local function clearArt()
		for _, child in artHolder:GetChildren() do
			child:Destroy()
		end
	end

	local function renderSelection()
		clearArt()
		local id = selectedId
		local definition = if id then Cosmetics.get(id) else nil
		if not definition then
			itemName.Text = "NO COSMETIC SELECTED"
			itemDescription.Text = "Choose an owned field cosmetic from the collection."
			equippedBadge.Text = ""
			equipButton.Active = false
			equipButton.Text = "SELECT AN ITEM"
			equipButton.BackgroundColor3 = DARK_NAVY
			return
		end

		addScarfPreview(artHolder, definition)
		itemName.Text = string.upper(definition.displayName)
		itemDescription.Text = definition.description
		local equipped = equippedId == id
		equippedBadge.Text = if equipped
			then "EQUIPPED // APPEARANCE ONLY"
			else "OWNED // READY TO EQUIP"
		equippedBadge.TextColor3 = if equipped then MINT else GOLDEN
		equipButton.Active = not equipped
		equipButton.Text = if equipped then "EQUIPPED" else "EQUIP COSMETIC"
		equipButton.BackgroundColor3 = if equipped then MINT else WARM_CORAL
		equipButton.TextColor3 = if equipped then DARK_NAVY else IMPACT_WHITE

		for cosmeticId, button in itemButtons do
			button.BackgroundColor3 = if cosmeticId == id then DEEP_TEAL else DARK_NAVY
			button.TextColor3 = if cosmeticId == id then MINT else CREAM
		end
	end

	local function rebuildCatalog()
		for _, button in itemButtons do
			button:Destroy()
		end
		table.clear(itemButtons)
		for order, id in ownedIds do
			local definition = Cosmetics.get(id)
			if not definition then
				continue
			end
			local suffix = if equippedId == id then "  //  EQUIPPED" else ""
			local button = createButton(
				catalog,
				`Item_{id}`,
				string.upper(definition.displayName) .. suffix,
				UDim2.fromOffset(0, 0),
				UDim2.new(1, 0, 0, 54),
				DARK_NAVY
			)
			button.LayoutOrder = order
			button.TextSize = 12
			button.TextWrapped = true
			itemButtons[id] = button
			table.insert(
				connections,
				button.Activated:Connect(function()
					selectedId = id
					renderSelection()
				end)
			)
		end
		collectionLabel.Text = string.format("ORIGINAL COSMETICS // OWNED %d", #ownedIds)
		if selectedId == nil or not table.find(ownedIds, selectedId) then
			selectedId = if equippedId and table.find(ownedIds, equippedId)
				then equippedId
				else ownedIds[1]
		end
		renderSelection()
	end

	local function refreshProfile()
		local nextOwned, valid = parseOwned(localPlayer:GetAttribute("ProfileOwnedCosmetics"))
		local nextEquipped = localPlayer:GetAttribute("ProfileEquippedCosmetic")
		if type(nextEquipped) ~= "string" or not Cosmetics.get(nextEquipped) then
			nextEquipped = nil
		end
		ownedIds = nextOwned
		equippedId = nextEquipped
		if not valid then
			collectionLabel.Text = "FIELD KIT DATA UNAVAILABLE"
			collectionLabel.TextColor3 = WARM_CORAL
		else
			collectionLabel.TextColor3 = GOLDEN
		end
		rebuildCatalog()
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
			refreshProfile()
			previousSelection = GuiService.SelectedObject
			GuiService.SelectedObject = itemButtons[selectedId or ""] or closeButton
		else
			if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(overlay) then
				GuiService.SelectedObject = previousSelection
			end
			previousSelection = nil
		end
	end

	table.insert(
		connections,
		equipButton.Activated:Connect(function()
			local id = selectedId
			if not id or equippedId == id or not table.find(ownedIds, id) then
				return
			end
			local now = os.clock()
			if now - lastRequestAt < REQUEST_COOLDOWN_SECONDS then
				return
			end
			lastRequestAt = now
			equipButton.Active = false
			equipButton.Text = "EQUIPPING..."
			equipButton.BackgroundColor3 = GOLDEN
			equipButton.TextColor3 = DARK_NAVY
			requestEquipCosmeticRemote:FireServer({ cosmeticId = id })
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
	for _, attributeName in { "ProfileOwnedCosmetics", "ProfileEquippedCosmetic" } do
		table.insert(
			connections,
			localPlayer:GetAttributeChangedSignal(attributeName):Connect(refreshProfile)
		)
	end
	if lobbyEventRemote then
		table.insert(
			connections,
			lobbyEventRemote.OnClientEvent:Connect(function(kind: any, payload: any)
				if
					kind ~= "ProfileActionResult"
					or type(payload) ~= "table"
					or payload.action ~= "EquipCosmetic"
				then
					return
				end
				refreshProfile()
				if payload.status == "Applied" then
					equippedBadge.Text = "EQUIPPED // SAVED TO FIELD PROFILE"
					equippedBadge.TextColor3 = MINT
				elseif payload.status == "ReadOnly" then
					equippedBadge.Text = "PROFILE IS READ ONLY // NOT EQUIPPED"
					equippedBadge.TextColor3 = WARM_CORAL
				elseif payload.status == "Unavailable" then
					equippedBadge.Text = "PROFILE UNAVAILABLE // TRY LATER"
					equippedBadge.TextColor3 = WARM_CORAL
				else
					equippedBadge.Text = "EQUIP FAILED // WAIT A MOMENT"
					equippedBadge.TextColor3 = WARM_CORAL
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
	table.insert(
		connections,
		localPlayer:GetAttributeChangedSignal("ClientUIScale"):Connect(function()
			uiScale.Scale = ClientSettings.readLocal(localPlayer).uiScale
		end)
	)
	local camera = Workspace.CurrentCamera
	if camera then
		table.insert(
			connections,
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				local viewport = camera.ViewportSize
				local scale = ClientSettings.readLocal(localPlayer).uiScale
				uiScale.Scale = scale
				panel.Size = UDim2.fromOffset(
					math.clamp(viewport.X * 0.9, 300, 720) / scale,
					math.clamp(viewport.Y * 0.86, 430, 560) / scale
				)
			end)
		)
	end

	refreshProfile()

	return {
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
			screenGui:Destroy()
		end,
	}
end

return LoadoutController
