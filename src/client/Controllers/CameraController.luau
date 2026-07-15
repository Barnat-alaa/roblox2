--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BotConfig = require(ReplicatedStorage.Shared.Config.BotConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ClientSettings = require(script.Parent.ClientSettings)

local OVERVIEW_TARGET = Vector3.new(0, 15, GameConfig.combatPlaneZ)
local OVERVIEW_DISTANCE = 155
local ACTOR_DISTANCE = 92
local PROJECTILE_DISTANCE = 100
local WIDE_PROJECTILE_DISTANCE = 145
local IMPACT_DISTANCE = 82
local CAMERA_HEIGHT = 8
local CAMERA_SMOOTHNESS = 8
local IMPACT_HOLD_SECONDS = 1.1
local SHAKE_DURATION_SECONDS = 0.5
local MAX_SHAKE_STUDS = 1.75

type CameraMode = "Overview" | "Actor" | "Projectile" | "Impact"

export type Controller = {
	setActiveUserId: (userId: number) -> (),
	followProjectile: (shotId: string, projectile: BasePart, wide: boolean) -> (),
	showImpact: (shotId: string, position: Vector3) -> (),
	stopFollowing: (shotId: string) -> (),
	destroy: () -> (),
}

local CameraController = {}
local cachedBotModel: Model? = nil

local function getBotModel(): Model?
	local cached = cachedBotModel
	if cached and cached.Parent ~= nil then
		return cached
	end
	cachedBotModel = nil

	local arena = Workspace:FindFirstChild("CritterClashArena")
	local candidate = if arena then arena:FindFirstChild(BotConfig.modelName) else nil
	if candidate and candidate:IsA("Model") then
		cachedBotModel = candidate
		return candidate
	end
	return nil
end

local function getActorPosition(userId: number): Vector3?
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		if userId ~= BotConfig.userId then
			return nil
		end
		local bot = getBotModel()
		if not bot then
			return nil
		end
		local root = bot:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root.Position
		end
		return bot:GetPivot().Position
	end

	local character = player.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end

	return character:GetPivot().Position
end

function CameraController.create(): Controller
	local activeUserId = 0
	local mode: CameraMode = "Overview"
	local followedShotId: string? = nil
	local followedProjectile: BasePart? = nil
	local projectileWide = false
	local impactPosition: Vector3? = nil
	local impactExpiresAt = 0
	local impactStartedAt = 0
	local shakePhase = 0
	local cameraShake = ClientSettings.readLocal(Players.LocalPlayer).cameraShake
	local destroyed = false

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 45
	end

	local function returnToActor()
		followedShotId = nil
		followedProjectile = nil
		impactPosition = nil
		mode = if getActorPosition(activeUserId) then "Actor" else "Overview"
	end

	local renderConnection = RunService.RenderStepped:Connect(function(deltaTime: number)
		if destroyed then
			return
		end

		local currentCamera = Workspace.CurrentCamera
		if not currentCamera then
			return
		end
		if currentCamera.CameraType ~= Enum.CameraType.Scriptable then
			currentCamera.CameraType = Enum.CameraType.Scriptable
		end

		if mode == "Impact" and Workspace:GetServerTimeNow() >= impactExpiresAt then
			returnToActor()
		elseif mode == "Projectile" then
			local projectile = followedProjectile
			if not projectile or not projectile.Parent then
				returnToActor()
			end
		end

		local target = OVERVIEW_TARGET
		local distance = OVERVIEW_DISTANCE
		if mode == "Actor" then
			target = getActorPosition(activeUserId) or OVERVIEW_TARGET
			distance = ACTOR_DISTANCE
		elseif mode == "Projectile" then
			local projectile = followedProjectile
			if projectile then
				target = projectile.Position
			end
			distance = if projectileWide then WIDE_PROJECTILE_DISTANCE else PROJECTILE_DISTANCE
		elseif mode == "Impact" then
			target = impactPosition or OVERVIEW_TARGET
			distance = IMPACT_DISTANCE
		end

		target = Vector3.new(target.X, target.Y + CAMERA_HEIGHT, GameConfig.combatPlaneZ)
		if mode == "Impact" and cameraShake > 0 then
			local elapsed = math.max(0, Workspace:GetServerTimeNow() - impactStartedAt)
			local decay = math.max(0, 1 - elapsed / SHAKE_DURATION_SECONDS)
			local amplitude = MAX_SHAKE_STUDS * cameraShake * decay * decay
			target += Vector3.new(
				math.sin(elapsed * 43 + shakePhase) * amplitude,
				math.cos(elapsed * 51 + shakePhase * 0.7) * amplitude * 0.65,
				0
			)
		end
		local desired = CFrame.lookAt(target + Vector3.new(0, 0, distance), target)
		local alpha = 1 - math.exp(-CAMERA_SMOOTHNESS * deltaTime)
		currentCamera.CFrame = currentCamera.CFrame:Lerp(desired, alpha)
		currentCamera.Focus = CFrame.new(target)
	end)

	local settingsConnection = Players.LocalPlayer
		:GetAttributeChangedSignal("ClientCameraShake")
		:Connect(function()
			cameraShake = ClientSettings.readLocal(Players.LocalPlayer).cameraShake
		end)

	local controller: Controller = {
		setActiveUserId = function(userId: number)
			activeUserId = userId
			if mode ~= "Projectile" and mode ~= "Impact" then
				mode = if getActorPosition(activeUserId) then "Actor" else "Overview"
			end
		end,
		followProjectile = function(shotId: string, projectile: BasePart, wide: boolean)
			followedShotId = shotId
			followedProjectile = projectile
			projectileWide = wide
			impactPosition = nil
			mode = "Projectile"
		end,
		showImpact = function(shotId: string, position: Vector3)
			if followedShotId ~= nil and followedShotId ~= shotId then
				return
			end
			followedShotId = shotId
			followedProjectile = nil
			impactPosition = position
			impactStartedAt = Workspace:GetServerTimeNow()
			impactExpiresAt = impactStartedAt + IMPACT_HOLD_SECONDS
			local phaseAccumulator = 0
			for index = 1, #shotId do
				phaseAccumulator = (phaseAccumulator + string.byte(shotId, index) * index) % 6_283
			end
			shakePhase = phaseAccumulator / 1_000
			mode = "Impact"
		end,
		stopFollowing = function(shotId: string)
			if followedShotId == shotId then
				returnToActor()
			end
		end,
		destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			renderConnection:Disconnect()
			settingsConnection:Disconnect()
			local currentCamera = Workspace.CurrentCamera
			if currentCamera then
				currentCamera.CameraType = Enum.CameraType.Custom
			end
		end,
	}

	return controller
end

return CameraController
