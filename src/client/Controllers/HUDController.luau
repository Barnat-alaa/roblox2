--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)

local DEEP_TEAL = Color3.fromRGB(15, 107, 109)
local WARM_CORAL = Color3.fromRGB(242, 107, 94)
local CREAM = Color3.fromRGB(255, 241, 213)
local GOLDEN = Color3.fromRGB(246, 196, 71)
local DARK_NAVY = Color3.fromRGB(20, 40, 61)
local MINT = Color3.fromRGB(118, 217, 177)
local IMPACT_WHITE = Color3.fromRGB(255, 253, 246)

export type Intent = {
	angle: number,
	power: number,
	weaponId: string,
}

export type MatchState = {
	phase: string,
	activeUserId: number,
	deadline: number,
	roundNumber: number,
	wind: number,
	serverTime: number,
}

export type Controller = {
	setMatchState: (state: MatchState) -> (),
	setIntent: (intent: Intent) -> (),
	setCanAct: (canAct: boolean) -> (),
	showMessage: (message: string, duration: number?) -> (),
	destroy: () -> (),
}

local HUDController = {}

local PHASE_NAMES: { [string]: string } = {
	WaitingForPlayers = "WAITING FOR PLAYERS",
	Countdown = "GET READY",
	TurnStart = "TURN START",
	Movement = "MOVE & AIM",
	Aiming = "AIMING",
	ProjectileFired = "SHOT AWAY",
	ProjectileResolving = "SHOT IN FLIGHT",
	EnvironmentalResolution = "SETTLING",
	TurnEnd = "TURN END",
	RoundEnd = "ROUND END",
	MatchEnd = "MATCH OVER",
	Results = "RESULTS",
}

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

local function addScale(guiObject: GuiObject, scaleValue: number)
	local scale = Instance.new("UIScale")
	scale.Scale = scaleValue
	scale.Parent = guiObject
end

local function createPanel(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	anchorPoint: Vector2?
): Frame
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.AnchorPoint = anchorPoint or Vector2.zero
	panel.BackgroundColor3 = DARK_NAVY
	panel.BackgroundTransparency = 0.08
	panel.Position = position
	panel.Size = size
	panel.Parent = parent
	addCorner(panel, 12)
	addStroke(panel, CREAM, 2)
	return panel
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

local function createHealthPanel(
	parent: Instance,
	name: string,
	position: UDim2,
	anchorPoint: Vector2
): (Frame, TextLabel, TextLabel, Frame)
	local panel = createPanel(parent, name, position, UDim2.fromOffset(250, 62), anchorPoint)
	local nameLabel = createLabel(
		panel,
		"Name",
		"CRITTER",
		UDim2.fromOffset(12, 5),
		UDim2.new(1, -24, 0, 22),
		16,
		CREAM,
		Enum.TextXAlignment.Left
	)
	local valueLabel = createLabel(
		panel,
		"Value",
		"100 / 100",
		UDim2.new(1, -104, 0, 5),
		UDim2.fromOffset(92, 22),
		14,
		IMPACT_WHITE,
		Enum.TextXAlignment.Right
	)

	local barBack = Instance.new("Frame")
	barBack.Name = "HealthBarBack"
	barBack.BackgroundColor3 = DEEP_TEAL
	barBack.Position = UDim2.fromOffset(12, 34)
	barBack.Size = UDim2.new(1, -24, 0, 16)
	barBack.Parent = panel
	addCorner(barBack, 8)

	local barFill = Instance.new("Frame")
	barFill.Name = "HealthBarFill"
	barFill.BackgroundColor3 = MINT
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.Parent = barBack
	addCorner(barFill, 8)

	return panel, nameLabel, valueLabel, barFill
end

local function findHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function phaseDisplayName(phase: string): string
	return PHASE_NAMES[phase] or string.upper(phase)
end

function HUDController.create(initialIntent: Intent): Controller
	local localPlayer = Players.LocalPlayer
	local playerGuiInstance = localPlayer:WaitForChild("PlayerGui")
	assert(playerGuiInstance:IsA("PlayerGui"), "PlayerGui must be available")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CritterClashHUD"
	screenGui.DisplayOrder = 10
	screenGui.IgnoreGuiInset = false
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGuiInstance
	local currentCamera = Workspace.CurrentCamera
	local viewportWidth = if currentCamera then currentCamera.ViewportSize.X else 1_280
	if viewportWidth < 320 then
		viewportWidth = 800
	end
	local touchLayout = UserInputService.TouchEnabled
	local topScale = if touchLayout then math.clamp((viewportWidth - 60) / 830, 0.62, 1) else 1

	local localHealthPanel, localNameLabel, localHealthLabel, localHealthFill =
		createHealthPanel(screenGui, "LocalHealth", UDim2.fromOffset(18, 18), Vector2.zero)
	local opponentHealthPanel, opponentNameLabel, opponentHealthLabel, opponentHealthFill =
		createHealthPanel(screenGui, "OpponentHealth", UDim2.new(1, -18, 0, 18), Vector2.new(1, 0))

	local turnPanel = createPanel(
		screenGui,
		"TurnPanel",
		UDim2.new(0.5, 0, 0, 18),
		UDim2.fromOffset(330, 88),
		Vector2.new(0.5, 0)
	)
	if touchLayout then
		addScale(localHealthPanel, topScale)
		addScale(opponentHealthPanel, topScale)
		addScale(turnPanel, topScale)
	end
	local phaseLabel = createLabel(
		turnPanel,
		"Phase",
		"CONNECTING",
		UDim2.fromOffset(10, 6),
		UDim2.new(1, -20, 0, 25),
		20,
		GOLDEN,
		Enum.TextXAlignment.Center
	)
	local turnLabel = createLabel(
		turnPanel,
		"Turn",
		"Waiting for match state",
		UDim2.fromOffset(10, 31),
		UDim2.new(1, -20, 0, 20),
		14,
		CREAM,
		Enum.TextXAlignment.Center
	)
	local timerLabel = createLabel(
		turnPanel,
		"Timer",
		"--",
		UDim2.fromOffset(12, 56),
		UDim2.fromOffset(70, 22),
		19,
		IMPACT_WHITE,
		Enum.TextXAlignment.Left
	)
	local roundLabel = createLabel(
		turnPanel,
		"Round",
		"ROUND --",
		UDim2.fromOffset(90, 56),
		UDim2.fromOffset(110, 22),
		14,
		CREAM,
		Enum.TextXAlignment.Center
	)
	local windLabel = createLabel(
		turnPanel,
		"Wind",
		"WIND CALM",
		UDim2.new(1, -126, 0, 56),
		UDim2.fromOffset(114, 22),
		14,
		MINT,
		Enum.TextXAlignment.Right
	)

	local compactWeaponWidth = math.max(260, math.min(500, viewportWidth - 310))
	local weaponPanel = createPanel(
		screenGui,
		"WeaponPanel",
		if touchLayout then UDim2.new(0, 14, 1, -18) else UDim2.new(0.5, 0, 1, -20),
		if touchLayout
			then UDim2.fromOffset(compactWeaponWidth, 126)
			else UDim2.fromOffset(500, 126),
		if touchLayout then Vector2.new(0, 1) else Vector2.new(0.5, 1)
	)
	local weaponLabel = createLabel(
		weaponPanel,
		"Weapon",
		"ACORN CANNON",
		UDim2.fromOffset(15, 8),
		UDim2.new(1, -30, 0, 25),
		20,
		GOLDEN,
		Enum.TextXAlignment.Left
	)
	local descriptionLabel = createLabel(
		weaponPanel,
		"Description",
		"",
		UDim2.fromOffset(15, 34),
		UDim2.new(1, -30, 0, 34),
		12,
		CREAM,
		Enum.TextXAlignment.Left
	)
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top

	local aimLabel = createLabel(
		weaponPanel,
		"Aim",
		"AIM 45°",
		UDim2.fromOffset(15, 73),
		UDim2.fromOffset(100, 21),
		14,
		MINT,
		Enum.TextXAlignment.Left
	)
	local powerLabel = createLabel(
		weaponPanel,
		"Power",
		"POWER 65%",
		UDim2.fromOffset(117, 73),
		UDim2.fromOffset(112, 21),
		14,
		MINT,
		Enum.TextXAlignment.Left
	)
	local powerBack = Instance.new("Frame")
	powerBack.Name = "PowerBack"
	powerBack.BackgroundColor3 = DEEP_TEAL
	powerBack.Position = UDim2.fromOffset(232, 76)
	powerBack.Size = UDim2.new(1, -247, 0, 14)
	powerBack.Parent = weaponPanel
	addCorner(powerBack, 7)
	local powerFill = Instance.new("Frame")
	powerFill.Name = "PowerFill"
	powerFill.BackgroundColor3 = WARM_CORAL
	powerFill.Size = UDim2.fromScale(initialIntent.power, 1)
	powerFill.Parent = powerBack
	addCorner(powerFill, 7)

	local statusLabel = createLabel(
		weaponPanel,
		"Status",
		"Waiting for your turn",
		UDim2.fromOffset(15, 99),
		UDim2.new(1, -30, 0, 20),
		13,
		IMPACT_WHITE,
		Enum.TextXAlignment.Center
	)

	local state: MatchState? = nil
	local intent = initialIntent
	local canAct = false
	local message = ""
	local messageExpiresAt = 0
	local serverClockOffset = 0
	local destroyed = false
	local healthRefreshElapsed = 1

	local function updateIntent()
		local definition = Weapons.get(intent.weaponId)
		weaponLabel.Text = if definition
			then string.upper(definition.displayName)
			else "UNKNOWN WEAPON"
		descriptionLabel.Text = if definition
			then definition.description
			else "Weapon data unavailable."
		local elevation = if intent.angle > 90 then 180 - intent.angle else intent.angle
		aimLabel.Text = string.format("AIM %d°", math.floor(elevation + 0.5))
		powerLabel.Text = string.format("POWER %d%%", math.floor(intent.power * 100 + 0.5))
		powerFill.Size = UDim2.fromScale(math.clamp(intent.power, 0, 1), 1)
	end

	local function updateHealthDisplay(
		nameLabel: TextLabel,
		valueLabel: TextLabel,
		barFill: Frame,
		displayName: string,
		humanoid: Humanoid?
	)
		nameLabel.Text = string.upper(displayName)
		local health = if humanoid then math.max(0, humanoid.Health) else 0
		local maximum = if humanoid then math.max(1, humanoid.MaxHealth) else 100
		local fraction = math.clamp(health / maximum, 0, 1)
		valueLabel.Text = string.format("%d / %d", math.ceil(health), math.ceil(maximum))
		barFill.Size = UDim2.fromScale(fraction, 1)
		barFill.BackgroundColor3 = if fraction > 0.5
			then MINT
			elseif fraction > 0.25 then GOLDEN
			else WARM_CORAL
	end

	local function updateHealth()
		updateHealthDisplay(
			localNameLabel,
			localHealthLabel,
			localHealthFill,
			localPlayer.DisplayName,
			findHumanoid(localPlayer)
		)

		local opponent: Player? = nil
		for _, player in Players:GetPlayers() do
			if player ~= localPlayer then
				opponent = player
				break
			end
		end
		if opponent then
			updateHealthDisplay(
				opponentNameLabel,
				opponentHealthLabel,
				opponentHealthFill,
				opponent.DisplayName,
				findHumanoid(opponent)
			)
			return
		end

		local target = Workspace:FindFirstChild("TrainingTarget", true)
		local targetHumanoid = if target and target:IsA("Model")
			then target:FindFirstChildOfClass("Humanoid")
			else nil
		updateHealthDisplay(
			opponentNameLabel,
			opponentHealthLabel,
			opponentHealthFill,
			"Training Target",
			targetHumanoid
		)
	end

	local function updateMatchDisplay()
		local currentState = state
		if not currentState then
			return
		end

		phaseLabel.Text = phaseDisplayName(currentState.phase)
		roundLabel.Text = string.format("ROUND %d", currentState.roundNumber)
		local activePlayer = Players:GetPlayerByUserId(currentState.activeUserId)
		if currentState.activeUserId == localPlayer.UserId then
			turnLabel.Text = "YOUR TURN"
			turnLabel.TextColor3 = MINT
		elseif activePlayer then
			turnLabel.Text = string.format("%s'S TURN", string.upper(activePlayer.DisplayName))
			turnLabel.TextColor3 = CREAM
		else
			turnLabel.Text = "WAITING FOR A CRITTER"
			turnLabel.TextColor3 = CREAM
		end

		if currentState.deadline > 0 then
			local estimatedServerTime = Workspace:GetServerTimeNow() + serverClockOffset
			local remaining = math.max(0, currentState.deadline - estimatedServerTime)
			timerLabel.Text = string.format("%04.1f", remaining)
			timerLabel.TextColor3 = if remaining <= 5 then WARM_CORAL else IMPACT_WHITE
		else
			timerLabel.Text = "--"
			timerLabel.TextColor3 = IMPACT_WHITE
		end

		if math.abs(currentState.wind) < 0.05 then
			windLabel.Text = "WIND CALM"
		else
			local arrow = if currentState.wind < 0 then "←" else "→"
			windLabel.Text = string.format("WIND %s %.2f", arrow, math.abs(currentState.wind))
		end

		if message ~= "" and Workspace:GetServerTimeNow() < messageExpiresAt then
			statusLabel.Text = message
			statusLabel.TextColor3 = WARM_CORAL
		elseif canAct then
			statusLabel.Text = if UserInputService.TouchEnabled
				then "Aim, set power, choose a weapon, then fire"
				else "↑/↓ aim  •  ←/→ power  •  1–4 weapon  •  F fire"
			statusLabel.TextColor3 = MINT
		else
			statusLabel.Text = phaseDisplayName(currentState.phase)
			statusLabel.TextColor3 = CREAM
		end
	end

	updateIntent()
	updateHealth()

	local heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		if destroyed then
			return
		end
		healthRefreshElapsed += deltaTime
		if healthRefreshElapsed >= 0.15 then
			healthRefreshElapsed = 0
			updateHealth()
		end
		updateMatchDisplay()
	end)

	local controller: Controller = {
		setMatchState = function(nextState: MatchState)
			state = nextState
			serverClockOffset = nextState.serverTime - Workspace:GetServerTimeNow()
			updateMatchDisplay()
		end,
		setIntent = function(nextIntent: Intent)
			intent = nextIntent
			updateIntent()
		end,
		setCanAct = function(nextCanAct: boolean)
			canAct = nextCanAct
			updateMatchDisplay()
		end,
		showMessage = function(nextMessage: string, duration: number?)
			message = nextMessage
			messageExpiresAt = Workspace:GetServerTimeNow() + (duration or 2.5)
			updateMatchDisplay()
		end,
		destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			heartbeatConnection:Disconnect()
			screenGui:Destroy()
		end,
	}

	return controller
end

return HUDController
