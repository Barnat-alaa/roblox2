--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Ballistics = require(ReplicatedStorage.Shared.Simulation.Ballistics)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local Wind = require(ReplicatedStorage.Shared.Simulation.Wind)
local ClientSettings = require(script.Parent.ClientSettings)

local DOT_COUNT = 24
local SAMPLE_INTERVAL = 4 / 15
local COLLISION_SUBSTEPS_PER_DOT = 2
local COLLISION_INTERVAL = SAMPLE_INTERVAL / COLLISION_SUBSTEPS_PER_DOT
local ORIGIN_HEIGHT = 2.4
local REFRESH_INTERVAL = 0.1
local MINT = Color3.fromRGB(118, 217, 177)

export type Intent = {
	angle: number,
	power: number,
	weaponId: string,
}

export type Controller = {
	setIntent: (intent: Intent) -> (),
	setWind: (wind: number) -> (),
	setVisible: (visible: boolean) -> (),
	destroy: () -> (),
}

local TrajectoryController = {}

local function getLaunchOrigin(): Vector3?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end

	return Vector3.new(root.Position.X, root.Position.Y + ORIGIN_HEIGHT, GameConfig.combatPlaneZ)
end

local function cloneIntent(intent: Intent): Intent
	return {
		angle = intent.angle,
		power = intent.power,
		weaponId = intent.weaponId,
	}
end

function TrajectoryController.create(initialIntent: Intent): Controller
	local folder = Instance.new("Folder")
	folder.Name = "CritterClashLocalTrajectory"
	folder.Parent = Workspace

	local dots: { BasePart } = {}
	for index = 1, DOT_COUNT do
		local dot = Instance.new("Part")
		dot.Name = string.format("PreviewDot%02d", index)
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.CanTouch = false
		dot.CastShadow = false
		dot.Color = MINT
		dot.Material = Enum.Material.Neon
		dot.Shape = Enum.PartType.Ball
		dot.Size = Vector3.one * math.max(0.22, 0.48 - index * 0.009)
		dot.Transparency = 1
		dot.Parent = folder
		dots[index] = dot
	end

	local intent = cloneIntent(initialIntent)
	local windStrength = 0
	local visible = false
	local dirty = true
	local destroyed = false
	local elapsedSinceMovementCheck = REFRESH_INTERVAL
	local lastOrigin: Vector3? = nil
	local reducedEffects = ClientSettings.readLocal(Players.LocalPlayer).reducedEffects

	local function hideAll()
		for _, dot in dots do
			dot.Transparency = 1
		end
	end

	local function rebuild()
		dirty = false
		if not visible then
			hideAll()
			return
		end

		local origin = getLaunchOrigin()
		local definition = Weapons.get(intent.weaponId)
		if not origin or not definition then
			hideAll()
			return
		end
		lastOrigin = origin

		local speed = Weapons.resolveSpeed(definition, intent.power)
		local velocity = Ballistics.worldLaunchVelocity(intent.angle, speed)
		local acceleration = Ballistics.acceleration({
			gravity = Vector3.new(0, -GameConfig.projectileWorldGravity, 0),
			wind = Wind.asAcceleration(windStrength),
			gravityScale = definition.gravityScale,
			windScale = definition.windScale,
		})
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		local filter: { Instance } = { folder }
		local character = Players.LocalPlayer.Character
		if character then
			table.insert(filter, character)
		end
		raycastParams.FilterDescendantsInstances = filter
		raycastParams.IgnoreWater = true

		local visibleDotCount = 0
		local previousPoint = origin
		local stopped = false
		local maximumDots = if reducedEffects then math.ceil(DOT_COUNT / 2) else DOT_COUNT
		for dotIndex = 1, maximumDots do
			local dot = dots[dotIndex]
			for substepIndex = 1, COLLISION_SUBSTEPS_PER_DOT do
				local elapsed = (dotIndex - 1) * SAMPLE_INTERVAL + substepIndex * COLLISION_INTERVAL
				local point = Ballistics.positionAt(origin, velocity, acceleration, elapsed)
				local hit = Workspace:Raycast(previousPoint, point - previousPoint, raycastParams)
				if hit then
					dot.Position = hit.Position
					dot.Transparency = 0.15
					visibleDotCount = dotIndex
					stopped = true
					break
				end
				previousPoint = point
			end
			if stopped then
				break
			end

			dot.Position = previousPoint
			dot.Transparency = math.min(0.58, 0.08 + dotIndex * 0.018)
			visibleDotCount = dotIndex
		end

		for index = visibleDotCount + 1, DOT_COUNT do
			dots[index].Transparency = 1
		end
	end

	local heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		if destroyed or not visible then
			return
		end
		elapsedSinceMovementCheck += deltaTime
		if elapsedSinceMovementCheck >= REFRESH_INTERVAL then
			elapsedSinceMovementCheck = 0
			local origin = getLaunchOrigin()
			if origin and (not lastOrigin or (origin - lastOrigin).Magnitude > 0.05) then
				dirty = true
			elseif not origin and lastOrigin then
				lastOrigin = nil
				dirty = true
			end
		end

		if dirty then
			rebuild()
		end
	end)
	local settingsConnection = Players.LocalPlayer
		:GetAttributeChangedSignal("ClientReducedEffects")
		:Connect(function()
			reducedEffects = ClientSettings.readLocal(Players.LocalPlayer).reducedEffects
			dirty = true
		end)

	local controller: Controller = {
		setIntent = function(nextIntent: Intent)
			intent = cloneIntent(nextIntent)
			dirty = true
		end,
		setWind = function(nextWind: number)
			if windStrength ~= nextWind then
				windStrength = nextWind
				dirty = true
			end
		end,
		setVisible = function(nextVisible: boolean)
			if visible == nextVisible then
				return
			end
			visible = nextVisible
			dirty = true
			if not visible then
				hideAll()
			end
		end,
		destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			heartbeatConnection:Disconnect()
			settingsConnection:Disconnect()
			folder:Destroy()
		end,
	}

	return controller
end

return TrajectoryController
