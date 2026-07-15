--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local ClientSettings = require(script.Parent.ClientSettings)

local ACTION_AIM_UP = "CritterClashAimUp"
local ACTION_AIM_DOWN = "CritterClashAimDown"
local ACTION_POWER_UP = "CritterClashPowerUp"
local ACTION_POWER_DOWN = "CritterClashPowerDown"
local ACTION_WEAPON = "CritterClashWeapon"
local ACTION_FIRE = "CritterClashFire"
local ACTION_GAMEPAD_AIM_POWER = "CritterClashGamepadAimPower"
local ACTION_PRIORITY = 3_000

local AIM_STEP = 2
local POWER_STEP = 0.025
local GAMEPAD_SAMPLE_SECONDS = 0.05
local GAMEPAD_DEADZONE = 0.2
local GAMEPAD_AIM_DEGREES_PER_SECOND = 45
local GAMEPAD_POWER_PER_SECOND = 0.55

local WEAPON_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
}

local DEEP_TEAL = Color3.fromRGB(15, 107, 109)
local WARM_CORAL = Color3.fromRGB(242, 107, 94)
local CREAM = Color3.fromRGB(255, 241, 213)
local DARK_NAVY = Color3.fromRGB(20, 40, 61)

export type Intent = {
	angle: number,
	power: number,
	weaponId: string,
}

export type ChangeKind = "Aim" | "Power" | "Weapon"

export type Controller = {
	changed: RBXScriptSignal,
	fireRequested: RBXScriptSignal,
	getIntent: () -> Intent,
	setEnabled: (enabled: boolean) -> (),
	setFireLocked: (locked: boolean) -> (),
	isEnabled: () -> boolean,
	destroy: () -> (),
}

local InputController = {}

local function addCorner(guiObject: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = guiObject
end

local function addStroke(guiObject: GuiObject, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = 0.1
	stroke.Parent = guiObject
end

local function createButton(
	parent: Instance,
	name: string,
	text: string,
	position: UDim2,
	size: UDim2,
	backgroundColor: Color3
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Active = true
	button.AutoButtonColor = false
	button.BackgroundColor3 = backgroundColor
	button.Position = position
	button.Size = size
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = CREAM
	button.TextScaled = true
	button.TextStrokeColor3 = DARK_NAVY
	button.TextStrokeTransparency = 0.55
	button.Parent = parent
	addCorner(button, 12)
	addStroke(button, DARK_NAVY, 2)

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 20
	textConstraint.MinTextSize = 11
	textConstraint.Parent = button

	return button
end

local function cloneIntent(intent: Intent): Intent
	return {
		angle = intent.angle,
		power = intent.power,
		weaponId = intent.weaponId,
	}
end

local function facingFromSpawn(player: Player): number?
	local spawnX = player:GetAttribute("MatchSpawnX")
	if type(spawnX) ~= "number" or spawnX ~= spawnX or spawnX == 0 then
		return nil
	end
	return if spawnX < 0 then 1 else -1
end

function InputController.create(): Controller
	local localPlayer = Players.LocalPlayer
	local playerGuiInstance = localPlayer:WaitForChild("PlayerGui")
	assert(playerGuiInstance:IsA("PlayerGui"), "PlayerGui must be available")

	local changedEvent = Instance.new("BindableEvent")
	local fireEvent = Instance.new("BindableEvent")
	local connections: { RBXScriptConnection } = {}
	local enabled = false
	local fireLocked = false
	local selectedWeaponIndex = 1
	local gamepadAimAxis = 0
	local gamepadPowerAxis = 0
	local gamepadAccumulator = 0
	local destroyed = false

	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local facing: number = facingFromSpawn(localPlayer)
		or if root and root:IsA("BasePart") and root.Position.X > 0 then -1 else 1
	local initialAngle = if facing == -1 then 135 else 45
	local intent: Intent = {
		angle = initialAngle,
		power = 0.65,
		weaponId = Weapons.All[selectedWeaponIndex].id,
	}

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CritterClashTouchControls"
	screenGui.DisplayOrder = 20
	screenGui.IgnoreGuiInset = false
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false
	screenGui.Parent = playerGuiInstance

	local controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.AnchorPoint = Vector2.new(1, 1)
	controls.BackgroundTransparency = 1
	controls.Position = UDim2.new(1, -14, 1, -18)
	controls.Size = UDim2.fromOffset(230, 112)
	controls.Parent = screenGui

	local accessibilityScale = Instance.new("UIScale")
	accessibilityScale.Name = "AccessibilityScale"
	accessibilityScale.Scale = ClientSettings.readLocal(localPlayer).uiScale
	accessibilityScale.Parent = controls

	local aimUpButton = createButton(
		controls,
		"AimUp",
		"AIM +",
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(70, 50),
		DEEP_TEAL
	)
	local aimDownButton = createButton(
		controls,
		"AimDown",
		"AIM -",
		UDim2.fromOffset(0, 58),
		UDim2.fromOffset(70, 50),
		DEEP_TEAL
	)
	local powerUpButton = createButton(
		controls,
		"PowerUp",
		"PWR +",
		UDim2.fromOffset(78, 0),
		UDim2.fromOffset(70, 50),
		DEEP_TEAL
	)
	local powerDownButton = createButton(
		controls,
		"PowerDown",
		"PWR -",
		UDim2.fromOffset(78, 58),
		UDim2.fromOffset(70, 50),
		DEEP_TEAL
	)
	local weaponButton = createButton(
		controls,
		"Weapon",
		"WPN 1",
		UDim2.fromOffset(156, 0),
		UDim2.fromOffset(70, 50),
		DEEP_TEAL
	)
	local fireButton = createButton(
		controls,
		"Fire",
		"FIRE",
		UDim2.fromOffset(156, 58),
		UDim2.fromOffset(70, 50),
		WARM_CORAL
	)

	local function updateResponsiveLayout()
		local camera = Workspace.CurrentCamera
		local viewportWidth = if camera then camera.ViewportSize.X else 1_280
		accessibilityScale.Scale = ClientSettings.readLocal(localPlayer).uiScale
		if viewportWidth < 520 then
			controls.Size = UDim2.fromOffset(150, 124)
			for index, button in
				{
					aimUpButton,
					aimDownButton,
					powerUpButton,
					powerDownButton,
					weaponButton,
					fireButton,
				}
			do
				local column = (index - 1) % 2
				local row = math.floor((index - 1) / 2)
				button.Position = UDim2.fromOffset(column * 78, row * 43)
				button.Size = UDim2.fromOffset(70, 36)
			end
		else
			controls.Size = UDim2.fromOffset(230, 112)
			for index, button in
				{
					aimUpButton,
					aimDownButton,
					powerUpButton,
					powerDownButton,
					weaponButton,
					fireButton,
				}
			do
				local column = math.floor((index - 1) / 2)
				local row = (index - 1) % 2
				button.Position = UDim2.fromOffset(column * 78, row * 58)
				button.Size = UDim2.fromOffset(70, 50)
			end
		end
	end

	local function emitChanged(kind: ChangeKind)
		changedEvent:Fire(cloneIntent(intent), kind)
	end

	local function syncFacing()
		local nextFacing = facingFromSpawn(localPlayer)
		if not nextFacing or nextFacing == facing then
			return
		end
		local elevation = if facing == 1 then intent.angle else 180 - intent.angle
		facing = nextFacing
		intent.angle = if facing == 1 then elevation else 180 - elevation
		emitChanged("Aim")
	end

	local function adjustAim(delta: number)
		local elevation = if facing == 1 then intent.angle else 180 - intent.angle
		elevation = math.clamp(elevation + delta, GameConfig.minimumAimDegrees, 90)
		intent.angle = if facing == 1 then elevation else 180 - elevation
		emitChanged("Aim")
	end

	local function adjustPower(delta: number)
		intent.power =
			math.clamp(intent.power + delta, GameConfig.minimumPower, GameConfig.maximumPower)
		emitChanged("Power")
	end

	local function selectWeapon(index: number)
		local definition = Weapons.All[index]
		if not definition then
			return
		end

		selectedWeaponIndex = index
		intent.weaponId = definition.id
		weaponButton.Text = string.format("WPN %d", selectedWeaponIndex)
		emitChanged("Weapon")
	end

	local function cycleWeapon()
		local nextIndex = (selectedWeaponIndex % #Weapons.All) + 1
		selectWeapon(nextIndex)
	end

	local function cycleWeaponBackward()
		local nextIndex = ((selectedWeaponIndex - 2) % #Weapons.All) + 1
		selectWeapon(nextIndex)
	end

	local function updateFireButton()
		local ready = enabled and not fireLocked
		fireButton.Active = ready
		fireButton.BackgroundColor3 = if ready then WARM_CORAL else DARK_NAVY
		fireButton.Text = if ready then "FIRE" else "WAIT"
	end

	local function requestFire()
		if not enabled or fireLocked then
			return
		end

		fireLocked = true
		updateFireButton()
		fireEvent:Fire(cloneIntent(intent))
	end

	local function actionOnBegin(callback: () -> ())
		return function(
			_actionName: string,
			inputState: Enum.UserInputState,
			_inputObject: InputObject
		): Enum.ContextActionResult
			if not enabled then
				return Enum.ContextActionResult.Pass
			end
			if inputState == Enum.UserInputState.Begin then
				callback()
			end
			return Enum.ContextActionResult.Sink
		end
	end

	ContextActionService:BindActionAtPriority(
		ACTION_AIM_UP,
		actionOnBegin(function()
			adjustAim(AIM_STEP)
		end),
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.Up,
		Enum.KeyCode.DPadUp
	)
	ContextActionService:BindActionAtPriority(
		ACTION_AIM_DOWN,
		actionOnBegin(function()
			adjustAim(-AIM_STEP)
		end),
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.Down,
		Enum.KeyCode.DPadDown
	)
	ContextActionService:BindActionAtPriority(
		ACTION_POWER_UP,
		actionOnBegin(function()
			adjustPower(POWER_STEP)
		end),
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.Right
	)
	ContextActionService:BindActionAtPriority(
		ACTION_POWER_DOWN,
		actionOnBegin(function()
			adjustPower(-POWER_STEP)
		end),
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.Left
	)

	ContextActionService:BindActionAtPriority(
		ACTION_WEAPON,
		function(
			_actionName: string,
			inputState: Enum.UserInputState,
			inputObject: InputObject
		): Enum.ContextActionResult
			if not enabled then
				return Enum.ContextActionResult.Pass
			end
			if inputState == Enum.UserInputState.Begin then
				local keyNumber = WEAPON_KEYS[inputObject.KeyCode]
				if keyNumber then
					selectWeapon(keyNumber)
				elseif inputObject.KeyCode == Enum.KeyCode.ButtonL1 then
					cycleWeaponBackward()
				elseif inputObject.KeyCode == Enum.KeyCode.ButtonR1 then
					cycleWeapon()
				end
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.Four,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1
	)
	ContextActionService:BindActionAtPriority(
		ACTION_FIRE,
		actionOnBegin(requestFire),
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.F,
		Enum.KeyCode.ButtonR2
	)
	ContextActionService:BindActionAtPriority(
		ACTION_GAMEPAD_AIM_POWER,
		function(
			_actionName: string,
			inputState: Enum.UserInputState,
			inputObject: InputObject
		): Enum.ContextActionResult
			if not enabled then
				gamepadAimAxis = 0
				gamepadPowerAxis = 0
				return Enum.ContextActionResult.Pass
			end
			if
				inputState == Enum.UserInputState.End
				or inputState == Enum.UserInputState.Cancel
			then
				gamepadAimAxis = 0
				gamepadPowerAxis = 0
			else
				local position = inputObject.Position
				gamepadAimAxis = if math.abs(position.Y) >= GAMEPAD_DEADZONE then position.Y else 0
				gamepadPowerAxis = if math.abs(position.X) >= GAMEPAD_DEADZONE
					then position.X
					else 0
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.Thumbstick2
	)

	table.insert(
		connections,
		aimUpButton.Activated:Connect(function()
			adjustAim(AIM_STEP)
		end)
	)
	table.insert(
		connections,
		aimDownButton.Activated:Connect(function()
			adjustAim(-AIM_STEP)
		end)
	)
	table.insert(
		connections,
		powerUpButton.Activated:Connect(function()
			adjustPower(POWER_STEP)
		end)
	)
	table.insert(
		connections,
		powerDownButton.Activated:Connect(function()
			adjustPower(-POWER_STEP)
		end)
	)
	table.insert(connections, weaponButton.Activated:Connect(cycleWeapon))
	table.insert(connections, fireButton.Activated:Connect(requestFire))
	table.insert(
		connections,
		localPlayer:GetAttributeChangedSignal("ClientUIScale"):Connect(updateResponsiveLayout)
	)
	table.insert(
		connections,
		localPlayer:GetAttributeChangedSignal("MatchSpawnX"):Connect(syncFacing)
	)
	table.insert(
		connections,
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateResponsiveLayout)
	)
	local camera = Workspace.CurrentCamera
	if camera then
		table.insert(
			connections,
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveLayout)
		)
	end

	local heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if destroyed or not enabled then
			return
		end
		if gamepadAimAxis == 0 and gamepadPowerAxis == 0 then
			gamepadAccumulator = 0
			return
		end
		gamepadAccumulator += deltaTime
		if gamepadAccumulator < GAMEPAD_SAMPLE_SECONDS then
			return
		end
		local sample = math.min(gamepadAccumulator, 0.1)
		gamepadAccumulator = 0
		if gamepadAimAxis ~= 0 then
			adjustAim(gamepadAimAxis * GAMEPAD_AIM_DEGREES_PER_SECOND * sample)
		end
		if gamepadPowerAxis ~= 0 then
			adjustPower(gamepadPowerAxis * GAMEPAD_POWER_PER_SECOND * sample)
		end
	end)

	updateResponsiveLayout()
	updateFireButton()

	local controller: Controller = {
		changed = changedEvent.Event,
		fireRequested = fireEvent.Event,
		getIntent = function(): Intent
			return cloneIntent(intent)
		end,
		setEnabled = function(nextEnabled: boolean)
			if nextEnabled then
				syncFacing()
			end
			enabled = nextEnabled
			screenGui.Enabled = UserInputService.TouchEnabled and enabled
			if not nextEnabled then
				fireLocked = false
				gamepadAimAxis = 0
				gamepadPowerAxis = 0
				gamepadAccumulator = 0
			end
			updateFireButton()
		end,
		setFireLocked = function(locked: boolean)
			fireLocked = locked
			updateFireButton()
		end,
		isEnabled = function(): boolean
			return enabled
		end,
		destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			heartbeatConnection:Disconnect()

			ContextActionService:UnbindAction(ACTION_AIM_UP)
			ContextActionService:UnbindAction(ACTION_AIM_DOWN)
			ContextActionService:UnbindAction(ACTION_POWER_UP)
			ContextActionService:UnbindAction(ACTION_POWER_DOWN)
			ContextActionService:UnbindAction(ACTION_WEAPON)
			ContextActionService:UnbindAction(ACTION_FIRE)
			ContextActionService:UnbindAction(ACTION_GAMEPAD_AIM_POWER)
			for _, connection in connections do
				connection:Disconnect()
			end
			screenGui:Destroy()
			changedEvent:Destroy()
			fireEvent:Destroy()
		end,
	}

	return controller
end

return InputController
