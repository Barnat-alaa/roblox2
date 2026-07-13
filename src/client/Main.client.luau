--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)

local CameraController = require(script.Parent.Controllers.CameraController)
local EffectsController = require(script.Parent.Controllers.EffectsController)
local HUDController = require(script.Parent.Controllers.HUDController)
local InputController = require(script.Parent.Controllers.InputController)
local TrajectoryController = require(script.Parent.Controllers.TrajectoryController)

type NetworkTable = { [string]: any }

type Intent = {
	angle: number,
	power: number,
	weaponId: string,
}

type MatchState = {
	phase: string,
	activeUserId: number,
	deadline: number,
	roundNumber: number,
	wind: number,
	serverTime: number,
}

type ShotLaunch = {
	shotId: string,
	weaponId: string,
	origin: Vector3,
	velocity: Vector3,
	acceleration: Vector3,
	serverTime: number,
	seed: number,
}

type ShotImpact = {
	shotId: string,
	position: Vector3,
	normal: Vector3,
	weaponId: string,
}

local REJECTION_MESSAGES: { [string]: string } = {
	rate_limited = "Easy there—wait a moment before firing again.",
	invalid_request = "That shot setup was invalid.",
	invalid_request_fields = "That shot setup was incomplete.",
	non_finite_shot = "That shot used an invalid number.",
	invalid_weapon = "That weapon is not available.",
	unknown_weapon = "That weapon is not available.",
	invalid_angle = "Aim is outside the allowed range.",
	angle_out_of_range = "Aim is outside the allowed range.",
	invalid_power = "Power is outside the allowed range.",
	power_out_of_range = "Power is outside the allowed range.",
	match_not_aiming = "Wait for the aiming phase.",
	not_your_turn = "It is another critter's turn.",
	turn_expired = "Time ran out before the shot reached the server.",
	player_not_alive = "Your critter cannot fire right now.",
	missing_character_root = "Your critter is still spawning.",
	invalid_character_position = "Return to the arena before firing.",
	shot_rejected = "The server rejected that shot.",
}

local function waitForRemote(folder: Instance, remoteName: string): RemoteEvent
	local remote = folder:WaitForChild(remoteName)
	assert(remote:IsA("RemoteEvent"), `{remoteName} must be a RemoteEvent`)
	return remote
end

local function asNetworkTable(value: any): NetworkTable?
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

local function finiteVector(value: any): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	local vector = value :: Vector3
	if
		finiteNumber(vector.X) == nil
		or finiteNumber(vector.Y) == nil
		or finiteNumber(vector.Z) == nil
	then
		return nil
	end
	return vector
end

local function parseMatchState(value: any): MatchState?
	local payload = asNetworkTable(value)
	if not payload then
		return nil
	end

	local phase = payload.phase
	local activeUserId = finiteNumber(payload.activeUserId)
	local deadline = finiteNumber(payload.deadline)
	local roundNumber = finiteNumber(payload.roundNumber)
	local wind = finiteNumber(payload.wind)
	local serverTime = finiteNumber(payload.serverTime)
	if
		type(phase) ~= "string"
		or not activeUserId
		or not deadline
		or not roundNumber
		or not wind
		or not serverTime
	then
		return nil
	end

	return {
		phase = phase,
		activeUserId = activeUserId,
		deadline = deadline,
		roundNumber = roundNumber,
		wind = wind,
		serverTime = serverTime,
	}
end

local function parseShotLaunch(value: any): ShotLaunch?
	local payload = asNetworkTable(value)
	if not payload then
		return nil
	end

	local shotId = payload.shotId
	local weaponId = payload.weaponId
	local origin = finiteVector(payload.origin)
	local velocity = finiteVector(payload.velocity)
	local acceleration = finiteVector(payload.acceleration)
	local serverTime = finiteNumber(payload.serverTime)
	local seed = finiteNumber(payload.seed)
	if
		type(shotId) ~= "string"
		or shotId == ""
		or type(weaponId) ~= "string"
		or not origin
		or not velocity
		or not acceleration
		or not serverTime
		or not seed
	then
		return nil
	end

	return {
		shotId = shotId,
		weaponId = weaponId,
		origin = origin,
		velocity = velocity,
		acceleration = acceleration,
		serverTime = serverTime,
		seed = seed,
	}
end

local function parseShotImpact(value: any): ShotImpact?
	local payload = asNetworkTable(value)
	if not payload then
		return nil
	end

	local shotId = payload.shotId
	local weaponId = payload.weaponId
	local position = finiteVector(payload.position)
	local normal = finiteVector(payload.normal)
	if
		type(shotId) ~= "string"
		or shotId == ""
		or type(weaponId) ~= "string"
		or not position
		or not normal
	then
		return nil
	end

	return {
		shotId = shotId,
		weaponId = weaponId,
		position = position,
		normal = normal,
	}
end

local remotesFolder = ReplicatedStorage:WaitForChild(RemoteNames.folder)
local requestFireRemote = waitForRemote(remotesFolder, RemoteNames.requestFire)
local selectWeaponRemote = waitForRemote(remotesFolder, RemoteNames.selectWeapon)
local combatEventRemote = waitForRemote(remotesFolder, RemoteNames.combatEvent)
local matchStateRemote = waitForRemote(remotesFolder, RemoteNames.matchState)

local inputController = InputController.create()
local initialIntent: Intent = inputController.getIntent()
local cameraController = CameraController.create()
local effectsController = EffectsController.create()
local hudController = HUDController.create(initialIntent)
local trajectoryController = TrajectoryController.create(initialIntent)
local connections: { RBXScriptConnection } = {}
local destroyed = false

local function isLocalTurn(state: MatchState): boolean
	if state.activeUserId ~= Players.LocalPlayer.UserId then
		return false
	end
	return state.phase == "TurnStart" or state.phase == "Movement" or state.phase == "Aiming"
end

table.insert(
	connections,
	inputController.changed:Connect(function(nextIntent: Intent, kind: string)
		hudController.setIntent(nextIntent)
		trajectoryController.setIntent(nextIntent)
		if kind == "Weapon" then
			-- Selection is cosmetic in the current server slice, but this keeps the
			-- dedicated remote ready for inventory validation without sending definitions.
			selectWeaponRemote:FireServer(nextIntent.weaponId)
		end
	end)
)

table.insert(
	connections,
	inputController.fireRequested:Connect(function(intent: Intent)
		requestFireRemote:FireServer({
			weaponId = intent.weaponId,
			angle = intent.angle,
			power = intent.power,
		})
	end)
)

table.insert(
	connections,
	matchStateRemote.OnClientEvent:Connect(function(payload: any)
		local state = parseMatchState(payload)
		if not state then
			warn("CritterClash ignored a malformed MatchState payload")
			return
		end

		local localTurn = isLocalTurn(state)
		local canFire = state.activeUserId == Players.LocalPlayer.UserId and state.phase == "Aiming"
		cameraController.setActiveUserId(state.activeUserId)
		inputController.setEnabled(canFire)
		hudController.setMatchState(state)
		hudController.setCanAct(canFire)
		trajectoryController.setWind(state.wind)
		trajectoryController.setVisible(localTurn)
	end)
)

table.insert(
	connections,
	combatEventRemote.OnClientEvent:Connect(function(kind: any, payload: any)
		if kind == "ProjectileLaunched" then
			local launchData = parseShotLaunch(payload)
			if not launchData then
				warn("CritterClash ignored a malformed ProjectileLaunched payload")
				return
			end

			trajectoryController.setVisible(false)
			local projectile = effectsController.launch(launchData)
			local definition = Weapons.get(launchData.weaponId)
			cameraController.followProjectile(
				launchData.shotId,
				projectile,
				definition ~= nil and definition.cameraMode == "Wide"
			)
		elseif kind == "ProjectileImpacted" then
			local impactData = parseShotImpact(payload)
			if not impactData then
				warn("CritterClash ignored a malformed ProjectileImpacted payload")
				return
			end

			effectsController.impact(impactData)
			cameraController.showImpact(impactData.shotId, impactData.position)
		elseif kind == "FireRejected" then
			inputController.setFireLocked(false)
			local rejection = asNetworkTable(payload)
			local reasonValue = if rejection then rejection.reason else nil
			local reason = if type(reasonValue) == "string" then reasonValue else "shot_rejected"
			hudController.showMessage(
				REJECTION_MESSAGES[reason] or "The server rejected that shot."
			)
		end
	end)
)

local function destroy()
	if destroyed then
		return
	end
	destroyed = true
	for _, connection in connections do
		connection:Disconnect()
	end
	trajectoryController.destroy()
	effectsController.destroy()
	cameraController.destroy()
	hudController.destroy()
	inputController.destroy()
end

table.insert(connections, script.Destroying:Connect(destroy))
