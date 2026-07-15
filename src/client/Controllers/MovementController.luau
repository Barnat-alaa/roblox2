--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ClientSettings = require(script.Parent.ClientSettings)

local ACTION_LEFT = "CritterClashMoveLeft"
local ACTION_RIGHT = "CritterClashMoveRight"
local ACTION_JUMP = "CritterClashJump"
local ACTION_GAMEPAD_MOVE = "CritterClashGamepadMove"
local ACTION_PRIORITY = 3_100
local SEND_INTERVAL_SECONDS = 0.1
local GAMEPAD_DEADZONE = 0.14

export type Controller = {
	setTurn: (matchId: string, turnToken: number, enabled: boolean) -> (),
	destroy: () -> (),
}

local MovementController = {}

local function disableDefaultControls(): any
	local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
	local playerModuleScript = playerScripts:WaitForChild("PlayerModule")
	local loaded, playerModule = pcall(require, playerModuleScript)
	if not loaded then
		warn("CritterClash could not disable default character controls")
		return nil
	end
	local controls = (playerModule :: any):GetControls()
	controls:Disable()
	return controls
end

function MovementController.create(requestMovement: RemoteEvent): Controller
	local defaultControls = disableDefaultControls()
	local leftHeld = false
	local rightHeld = false
	local gamepadAxis = 0
	local enabled = false
	local currentMatchId = ""
	local currentTurnToken = 0
	local sequence = 0
	local sendAccumulator = 0
	local destroyed = false

	local function movementAxis(): number
		if math.abs(gamepadAxis) >= GAMEPAD_DEADZONE then
			return gamepadAxis
		end
		if leftHeld == rightHeld then
			return 0
		end
		return if leftHeld then -1 else 1
	end

	local function send(jumpRequested: boolean)
		if not enabled or currentMatchId == "" or currentTurnToken < 1 then
			return
		end
		sequence += 1
		requestMovement:FireServer({
			matchId = currentMatchId,
			turnToken = currentTurnToken,
			sequence = sequence,
			moveX = movementAxis(),
			jumpRequested = jumpRequested,
		})
	end

	local function bindHeldAction(actionName: string, isLeft: boolean, keyCode: Enum.KeyCode)
		ContextActionService:BindActionAtPriority(actionName, function(_, inputState)
			if not enabled then
				return Enum.ContextActionResult.Pass
			end
			if inputState == Enum.UserInputState.Begin then
				if isLeft then
					leftHeld = true
				else
					rightHeld = true
				end
				send(false)
			elseif
				inputState == Enum.UserInputState.End
				or inputState == Enum.UserInputState.Cancel
			then
				if isLeft then
					leftHeld = false
				else
					rightHeld = false
				end
				send(false)
			end
			return Enum.ContextActionResult.Sink
		end, true, ACTION_PRIORITY, keyCode)
	end

	bindHeldAction(ACTION_LEFT, true, Enum.KeyCode.A)
	bindHeldAction(ACTION_RIGHT, false, Enum.KeyCode.D)
	ContextActionService:BindActionAtPriority(ACTION_JUMP, function(_, inputState)
		if not enabled then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			send(true)
		end
		return Enum.ContextActionResult.Sink
	end, true, ACTION_PRIORITY, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	ContextActionService:BindActionAtPriority(
		ACTION_GAMEPAD_MOVE,
		function(_, inputState, inputObject)
			if not enabled then
				gamepadAxis = 0
				return Enum.ContextActionResult.Pass
			end
			if
				inputState == Enum.UserInputState.End
				or inputState == Enum.UserInputState.Cancel
			then
				gamepadAxis = 0
			else
				local axis = inputObject.Position.X
				gamepadAxis = if math.abs(axis) >= GAMEPAD_DEADZONE then axis else 0
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.Thumbstick1
	)

	ContextActionService:SetTitle(ACTION_LEFT, "LEFT")
	ContextActionService:SetTitle(ACTION_RIGHT, "RIGHT")
	ContextActionService:SetTitle(ACTION_JUMP, "JUMP")
	ContextActionService:SetPosition(ACTION_LEFT, UDim2.new(0, 54, 1, -74))
	ContextActionService:SetPosition(ACTION_RIGHT, UDim2.new(0, 128, 1, -74))
	ContextActionService:SetPosition(ACTION_JUMP, UDim2.new(0, 91, 1, -142))

	local function updateTouchButtons()
		local scale = ClientSettings.readLocal(Players.LocalPlayer).uiScale
		for _, actionName in { ACTION_LEFT, ACTION_RIGHT, ACTION_JUMP } do
			local button = ContextActionService:GetButton(actionName)
			if button then
				button.Visible = enabled
				button.Size = UDim2.fromOffset(60 * scale, 60 * scale)
			end
		end
	end
	task.defer(updateTouchButtons)
	local settingConnection =
		Players.LocalPlayer:GetAttributeChangedSignal("ClientUIScale"):Connect(updateTouchButtons)

	local heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not enabled then
			return
		end
		sendAccumulator += deltaTime
		if sendAccumulator >= SEND_INTERVAL_SECONDS then
			sendAccumulator %= SEND_INTERVAL_SECONDS
			send(false)
		end
	end)

	return {
		setTurn = function(matchId: string, turnToken: number, nextEnabled: boolean)
			local sameTurn = currentMatchId == matchId and currentTurnToken == turnToken
			if not sameTurn then
				sequence = 0
				sendAccumulator = 0
			end
			currentMatchId = matchId
			currentTurnToken = turnToken
			enabled = nextEnabled
			if not enabled then
				leftHeld = false
				rightHeld = false
				gamepadAxis = 0
				sendAccumulator = 0
			end
			updateTouchButtons()
		end,
		destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			heartbeatConnection:Disconnect()
			settingConnection:Disconnect()
			ContextActionService:UnbindAction(ACTION_LEFT)
			ContextActionService:UnbindAction(ACTION_RIGHT)
			ContextActionService:UnbindAction(ACTION_JUMP)
			ContextActionService:UnbindAction(ACTION_GAMEPAD_MOVE)
			if defaultControls then
				defaultControls:Enable()
			end
		end,
	}
end

return MovementController
