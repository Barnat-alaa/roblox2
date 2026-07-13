--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Ballistics = require(ReplicatedStorage.Shared.Simulation.Ballistics)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)

local WARM_CORAL = Color3.fromRGB(242, 107, 94)
local GOLDEN = Color3.fromRGB(246, 196, 71)
local MINT = Color3.fromRGB(118, 217, 177)
local IMPACT_WHITE = Color3.fromRGB(255, 253, 246)
local MAX_ACTIVE_SHOTS = 24
local MAX_CATCHUP_STEPS = 480
local FALLBACK_LIFETIME = 8

export type ShotLaunch = {
	shotId: string,
	weaponId: string,
	origin: Vector3,
	velocity: Vector3,
	acceleration: Vector3,
	serverTime: number,
	seed: number,
}

export type ShotImpact = {
	shotId: string,
	position: Vector3,
	normal: Vector3,
	weaponId: string,
}

type ActiveShot = {
	part: BasePart,
	state: Ballistics.State,
	acceleration: Vector3,
	serverTime: number,
	maxLifetime: number,
	definition: Weapons.ProjectileDefinition?,
	bouncesRemaining: number,
	raycastParams: RaycastParams,
	settled: boolean,
	sequence: number,
}

export type Controller = {
	launch: (launch: ShotLaunch) -> BasePart,
	impact: (impact: ShotImpact) -> (),
	destroy: () -> (),
}

local EffectsController = {}

local function configureVisualPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

local function reflectVelocity(velocity: Vector3, normal: Vector3, restitution: number): Vector3
	return (velocity - 2 * velocity:Dot(normal) * normal) * restitution
end

function EffectsController.create(): Controller
	local folder = Instance.new("Folder")
	folder.Name = "CritterClashLocalEffects"
	folder.Parent = Workspace

	local activeShots: { [string]: ActiveShot } = {}
	local recentImpacts: { [string]: number } = {}
	local nextSequence = 0
	local destroyed = false

	local function removeShot(shotId: string)
		local shot = activeShots[shotId]
		if not shot then
			return
		end
		activeShots[shotId] = nil
		shot.part:Destroy()
	end

	local function trimOldShots()
		local count = 0
		local oldestId: string? = nil
		local oldestSequence = math.huge
		for shotId, shot in activeShots do
			count += 1
			if shot.sequence < oldestSequence then
				oldestSequence = shot.sequence
				oldestId = shotId
			end
		end
		if count >= MAX_ACTIVE_SHOTS and oldestId then
			removeShot(oldestId)
		end
	end

	local function advanceShot(shot: ActiveShot, targetElapsed: number)
		local stepCount = 0
		while
			not shot.settled
			and shot.state.elapsed + GameConfig.projectileStepSeconds <= targetElapsed
			and stepCount < MAX_CATCHUP_STEPS
		do
			stepCount += 1
			local nextState =
				Ballistics.step(shot.state, shot.acceleration, GameConfig.projectileStepSeconds)
			local displacement = nextState.position - shot.state.position
			local hit = Workspace:Raycast(shot.state.position, displacement, shot.raycastParams)
			local definition = shot.definition
			if hit then
				if definition and shot.bouncesRemaining > 0 then
					shot.bouncesRemaining -= 1
					shot.state = {
						position = hit.Position + hit.Normal * 0.08,
						velocity = reflectVelocity(
							nextState.velocity,
							hit.Normal,
							definition.restitution
						),
						elapsed = nextState.elapsed,
					}
					if
						definition.detonationMode == "BounceLimit"
						and shot.bouncesRemaining == 0
					then
						shot.settled = true
					end
				elseif definition and definition.detonationMode == "Drill" then
					local direction = if displacement.Magnitude > 0
						then displacement.Unit
						else Vector3.xAxis
					shot.state = {
						position = hit.Position
							+ direction * math.min(definition.penetrationDepth, 8),
						velocity = Vector3.zero,
						elapsed = nextState.elapsed,
					}
					shot.settled = true
				else
					shot.state = {
						position = hit.Position,
						velocity = Vector3.zero,
						elapsed = nextState.elapsed,
					}
					shot.settled = true
				end
			else
				shot.state = nextState
			end

			local fuseExpired = definition ~= nil
				and definition.fuseTime ~= nil
				and shot.state.elapsed >= definition.fuseTime
			if fuseExpired or shot.state.elapsed >= shot.maxLifetime then
				shot.settled = true
			end
		end

		if shot.settled then
			shot.part.Position = shot.state.position
			return
		end

		local partialElapsed = math.min(
			math.max(0, targetElapsed - shot.state.elapsed),
			GameConfig.projectileStepSeconds
		)
		shot.part.Position = Ballistics.positionAt(
			shot.state.position,
			shot.state.velocity,
			shot.acceleration,
			partialElapsed
		)
	end

	local renderConnection = RunService.RenderStepped:Connect(function()
		if destroyed then
			return
		end

		local now = Workspace:GetServerTimeNow()
		local expired: { string } = {}
		for shotId, shot in activeShots do
			local elapsed = math.max(0, now - shot.serverTime)
			if elapsed > shot.maxLifetime + 0.5 then
				table.insert(expired, shotId)
			else
				advanceShot(shot, elapsed)
			end
		end
		for _, shotId in expired do
			removeShot(shotId)
		end
	end)

	local function launch(launchData: ShotLaunch): BasePart
		removeShot(launchData.shotId)
		trimOldShots()
		nextSequence += 1

		local definition = Weapons.get(launchData.weaponId)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.IgnoreWater = true
		local filter: { Instance } = { folder }
		local shooterUserIdText = string.match(launchData.shotId, "^(%-?%d+):")
		local shooterUserId = if shooterUserIdText then tonumber(shooterUserIdText) else nil
		local shooter = if shooterUserId then Players:GetPlayerByUserId(shooterUserId) else nil
		if shooter and shooter.Character then
			table.insert(filter, shooter.Character)
		end
		raycastParams.FilterDescendantsInstances = filter

		local projectile = Instance.new("Part")
		projectile.Name = `Projectile_{launchData.shotId}`
		projectile.Color = GOLDEN
		projectile.Material = Enum.Material.Neon
		projectile.Shape = Enum.PartType.Ball
		projectile.Size = Vector3.one * 0.9
		projectile.Position = launchData.origin
		configureVisualPart(projectile)
		projectile.Parent = folder

		local frontAttachment = Instance.new("Attachment")
		frontAttachment.Name = "TrailFront"
		frontAttachment.Position = Vector3.new(0, 0.22, 0)
		frontAttachment.Parent = projectile
		local backAttachment = Instance.new("Attachment")
		backAttachment.Name = "TrailBack"
		backAttachment.Position = Vector3.new(0, -0.22, 0)
		backAttachment.Parent = projectile

		local trail = Instance.new("Trail")
		trail.Name = "FlightTrail"
		trail.Attachment0 = frontAttachment
		trail.Attachment1 = backAttachment
		trail.Color = ColorSequence.new(IMPACT_WHITE, MINT)
		trail.FaceCamera = true
		trail.Lifetime = 0.24
		trail.LightEmission = 0.8
		trail.MinLength = 0.05
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Parent = projectile

		activeShots[launchData.shotId] = {
			part = projectile,
			state = Ballistics.createState(launchData.origin, launchData.velocity),
			acceleration = launchData.acceleration,
			serverTime = launchData.serverTime,
			maxLifetime = if definition then definition.maxLifetime else FALLBACK_LIFETIME,
			definition = definition,
			bouncesRemaining = if definition then definition.bounceCount else 0,
			raycastParams = raycastParams,
			settled = false,
			sequence = nextSequence,
		}

		return projectile
	end

	local function createImpactVisual(impactData: ShotImpact)
		local definition = Weapons.get(impactData.weaponId)
		local radius = if definition then definition.explosionRadius else 8

		local flash = Instance.new("Part")
		flash.Name = `ImpactFlash_{impactData.shotId}`
		flash.Color = IMPACT_WHITE
		flash.Material = Enum.Material.Neon
		flash.Shape = Enum.PartType.Ball
		flash.Size = Vector3.one * 0.8
		flash.Position = impactData.position
		flash.Transparency = 0.05
		configureVisualPart(flash)
		flash.Parent = folder

		local core = Instance.new("Part")
		core.Name = `ImpactCore_{impactData.shotId}`
		core.Color = WARM_CORAL
		core.Material = Enum.Material.Neon
		core.Shape = Enum.PartType.Ball
		core.Size = Vector3.one * 0.5
		core.Position = impactData.position
		core.Transparency = 0.12
		configureVisualPart(core)
		core.Parent = folder

		local flashTween = TweenService:Create(
			flash,
			TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Size = Vector3.one * radius * 1.8,
				Transparency = 1,
			}
		)
		local coreTween = TweenService:Create(
			core,
			TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{
				Size = Vector3.one * radius,
				Transparency = 1,
			}
		)
		flashTween:Play()
		coreTween:Play()
		Debris:AddItem(flash, 0.7)
		Debris:AddItem(core, 0.8)
	end

	local function impact(impactData: ShotImpact)
		removeShot(impactData.shotId)
		if recentImpacts[impactData.shotId] then
			return
		end
		recentImpacts[impactData.shotId] = Workspace:GetServerTimeNow()
		createImpactVisual(impactData)
		task.delay(10, function()
			recentImpacts[impactData.shotId] = nil
		end)
	end

	local controller: Controller = {
		launch = launch,
		impact = impact,
		destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			renderConnection:Disconnect()
			for shotId in activeShots do
				removeShot(shotId)
			end
			folder:Destroy()
		end,
	}

	return controller
end

return EffectsController
