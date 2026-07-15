--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientSettings = require(script.Parent.ClientSettings)

local MAX_SAFE_INTEGER = 9_007_199_254_740_991
local WARNING_INTERVAL_SECONDS = 2

local PROFILE_ATTRIBUTES = {
	"ProfileStatus",
	"ProfileStorage",
	"ProfileCoins",
	"ProfileExperience",
	"ProfileLevel",
	"ProfileXPIntoLevel",
	"ProfileXPForNextLevel",
}

local VALID_STATUS: { [string]: boolean } = {
	Loading = true,
	Ready = true,
	ReadOnly = true,
	Unavailable = true,
	Released = true,
}

local VALID_STORAGE: { [string]: boolean } = {
	Persistent = true,
	SessionMemory = true,
	ReadOnly = true,
	Unavailable = true,
}

local STORAGE_LABELS: { [string]: string } = {
	Persistent = "CLOUD",
	SessionMemory = "SESSION",
	ReadOnly = "READ ONLY",
	Unavailable = "OFFLINE",
}

local DEEP_TEAL = Color3.fromRGB(15, 107, 109)
local WARM_CORAL = Color3.fromRGB(242, 107, 94)
local CREAM = Color3.fromRGB(255, 241, 213)
local GOLDEN = Color3.fromRGB(246, 196, 71)
local DARK_NAVY = Color3.fromRGB(20, 40, 61)
local MINT = Color3.fromRGB(118, 217, 177)

type ProfileView = {
	status: string,
	storage: string?,
	coins: number?,
	experience: number?,
	level: number?,
	xpIntoLevel: number?,
	xpForNextLevel: number?,
}

export type Controller = {
	destroy: () -> (),
}

local ProfileController = {}

local function safeNonNegativeInteger(value: any): number?
	if
		type(value) ~= "number"
		or value ~= value
		or value == math.huge
		or value == -math.huge
		or value < 0
		or value ~= math.floor(value)
		or value > MAX_SAFE_INTEGER
	then
		return nil
	end
	return value
end

local function readStorage(player: Player): (string?, boolean)
	local value = player:GetAttribute("ProfileStorage")
	if value == nil then
		return nil, true
	end
	if type(value) ~= "string" or not VALID_STORAGE[value] then
		return nil, false
	end
	return value, true
end

local function readProfile(player: Player): ProfileView?
	local rawStatus = player:GetAttribute("ProfileStatus")
	if rawStatus == nil then
		return {
			status = "Loading",
			storage = nil,
			coins = nil,
			experience = nil,
			level = nil,
			xpIntoLevel = nil,
			xpForNextLevel = nil,
		} :: ProfileView
	end
	if type(rawStatus) ~= "string" or not VALID_STATUS[rawStatus] then
		return nil
	end

	local storage, storageValid = readStorage(player)
	if not storageValid then
		return nil
	end

	if rawStatus == "Loading" or rawStatus == "Unavailable" or rawStatus == "Released" then
		return {
			status = rawStatus,
			storage = storage,
			coins = nil,
			experience = nil,
			level = nil,
			xpIntoLevel = nil,
			xpForNextLevel = nil,
		} :: ProfileView
	end

	if storage == nil then
		return nil
	end
	local coins = safeNonNegativeInteger(player:GetAttribute("ProfileCoins"))
	local experience = safeNonNegativeInteger(player:GetAttribute("ProfileExperience"))
	local level = safeNonNegativeInteger(player:GetAttribute("ProfileLevel"))
	local xpIntoLevel = safeNonNegativeInteger(player:GetAttribute("ProfileXPIntoLevel"))
	local xpForNextLevel = safeNonNegativeInteger(player:GetAttribute("ProfileXPForNextLevel"))
	if
		coins == nil
		or experience == nil
		or level == nil
		or level < 1
		or xpIntoLevel == nil
		or xpForNextLevel == nil
		or experience < xpIntoLevel
		or (xpForNextLevel == 0 and xpIntoLevel ~= 0)
		or (xpForNextLevel > 0 and xpIntoLevel >= xpForNextLevel)
	then
		return nil
	end

	return {
		status = rawStatus,
		storage = storage,
		coins = coins,
		experience = experience,
		level = level,
		xpIntoLevel = xpIntoLevel,
		xpForNextLevel = xpForNextLevel,
	}
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
	alignment: Enum.TextXAlignment
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
	label.TextXAlignment = alignment
	label.Parent = parent
	return label
end

function ProfileController.create(): Controller
	local localPlayer = Players.LocalPlayer
	local playerGuiInstance = localPlayer:WaitForChild("PlayerGui")
	assert(playerGuiInstance:IsA("PlayerGui"), "PlayerGui must be available")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CritterClashProfile"
	screenGui.DisplayOrder = 11
	screenGui.IgnoreGuiInset = false
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGuiInstance

	local currentCamera = Workspace.CurrentCamera
	local viewportWidth = if currentCamera then currentCamera.ViewportSize.X else 1_280
	if viewportWidth < 320 then
		viewportWidth = 800
	end
	local touchLayout = UserInputService.TouchEnabled
	local panelScale = if touchLayout then math.clamp((viewportWidth - 60) / 830, 0.62, 1) else 1
	local panelTop = if touchLayout then 26 + math.floor(62 * panelScale) else 88

	local panel = Instance.new("Frame")
	panel.Name = "ProfilePanel"
	panel.BackgroundColor3 = DARK_NAVY
	panel.BackgroundTransparency = 0.06
	panel.Position = UDim2.fromOffset(18, panelTop)
	panel.Size = UDim2.fromOffset(250, 76)
	panel.Parent = screenGui
	addCorner(panel, 13)
	addStroke(panel, DEEP_TEAL, 2)

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "AccessibilityScale"
	uiScale.Scale = panelScale * ClientSettings.readLocal(localPlayer).uiScale
	uiScale.Parent = panel

	local headerLabel = createLabel(
		panel,
		"Header",
		"PROFILE // SYNCING",
		UDim2.fromOffset(12, 5),
		UDim2.new(0.68, -12, 0, 17),
		11,
		GOLDEN,
		Enum.TextXAlignment.Left
	)
	local storageLabel = createLabel(
		panel,
		"Storage",
		"CONNECTING",
		UDim2.new(0.68, 0, 0, 5),
		UDim2.new(0.32, -12, 0, 17),
		10,
		CREAM,
		Enum.TextXAlignment.Right
	)
	local coinsLabel = createLabel(
		panel,
		"Coins",
		"COINS --",
		UDim2.fromOffset(12, 23),
		UDim2.new(0.62, -12, 0, 23),
		18,
		GOLDEN,
		Enum.TextXAlignment.Left
	)
	local levelLabel = createLabel(
		panel,
		"Level",
		"LV --",
		UDim2.new(0.62, 0, 0, 23),
		UDim2.new(0.38, -12, 0, 23),
		17,
		MINT,
		Enum.TextXAlignment.Right
	)

	local xpBack = Instance.new("Frame")
	xpBack.Name = "XPBack"
	xpBack.BackgroundColor3 = DEEP_TEAL
	xpBack.Position = UDim2.fromOffset(12, 49)
	xpBack.Size = UDim2.new(1, -24, 0, 9)
	xpBack.Parent = panel
	addCorner(xpBack, 5)

	local xpFill = Instance.new("Frame")
	xpFill.Name = "XPFill"
	xpFill.BackgroundColor3 = MINT
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.Parent = xpBack
	addCorner(xpFill, 5)

	local xpLabel = createLabel(
		panel,
		"XP",
		"XP SYNCING",
		UDim2.fromOffset(12, 59),
		UDim2.new(1, -24, 0, 13),
		10,
		CREAM,
		Enum.TextXAlignment.Center
	)

	local connections: { RBXScriptConnection } = {}
	local refreshScheduled = false
	local destroyed = false
	local lastWarningAt = -math.huge

	local function setUnavailable(header: string, detail: string, color: Color3)
		headerLabel.Text = header
		headerLabel.TextColor3 = color
		storageLabel.Text = detail
		storageLabel.TextColor3 = color
		coinsLabel.Text = "COINS --"
		levelLabel.Text = "LV --"
		xpFill.Size = UDim2.fromScale(0, 1)
		xpLabel.Text = "PROGRESS NOT AVAILABLE"
	end

	local function render(view: ProfileView)
		local status = view.status
		if status == "Loading" then
			setUnavailable("PROFILE // SYNCING", "CONNECTING", GOLDEN)
			return
		elseif status == "Unavailable" or status == "Released" then
			setUnavailable("PROFILE // OFFLINE", "UNAVAILABLE", WARM_CORAL)
			return
		end

		local storage = view.storage :: string
		local coins = view.coins :: number
		local level = view.level :: number
		local xpIntoLevel = view.xpIntoLevel :: number
		local xpForNextLevel = view.xpForNextLevel :: number
		local readOnly = status == "ReadOnly"
		headerLabel.Text = if readOnly then "PROFILE // READ ONLY" else "FIELD PROFILE"
		headerLabel.TextColor3 = if readOnly then WARM_CORAL else MINT
		storageLabel.Text = STORAGE_LABELS[storage] or "OFFLINE"
		storageLabel.TextColor3 = if readOnly then WARM_CORAL else CREAM
		coinsLabel.Text = `COINS {formatInteger(coins)}`
		levelLabel.Text = `LV {formatInteger(level)}`

		local progress = if xpForNextLevel > 0 then xpIntoLevel / xpForNextLevel else 1
		xpFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
		xpFill.BackgroundColor3 = if readOnly then GOLDEN else MINT
		xpLabel.Text = if xpForNextLevel > 0
			then `{formatInteger(xpIntoLevel)} / {formatInteger(xpForNextLevel)} XP`
			else "MAX LEVEL"
	end

	local function refresh()
		refreshScheduled = false
		if destroyed then
			return
		end
		local view = readProfile(localPlayer)
		if not view then
			setUnavailable("PROFILE // SYNC ERROR", "INVALID DATA", WARM_CORAL)
			local now = os.clock()
			if now - lastWarningAt >= WARNING_INTERVAL_SECONDS then
				lastWarningAt = now
				warn("[CritterClash Profile] ignored invalid replicated profile attributes")
			end
			return
		end
		render(view)
	end

	local function scheduleRefresh()
		if destroyed or refreshScheduled then
			return
		end
		refreshScheduled = true
		task.defer(refresh)
	end

	for _, attributeName in PROFILE_ATTRIBUTES do
		table.insert(
			connections,
			localPlayer:GetAttributeChangedSignal(attributeName):Connect(scheduleRefresh)
		)
	end
	table.insert(
		connections,
		localPlayer:GetAttributeChangedSignal("ClientUIScale"):Connect(function()
			uiScale.Scale = panelScale * ClientSettings.readLocal(localPlayer).uiScale
		end)
	)
	refresh()

	local controller: Controller = {
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

	return controller
end

return ProfileController
