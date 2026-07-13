--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Ballistics = require(ReplicatedStorage.Shared.Simulation.Ballistics)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local Wind = require(ReplicatedStorage.Shared.Simulation.Wind)

local DamageService = require(script.Parent.DamageService)
local MatchService = require(script.Parent.MatchService)
local NetworkService = require(script.Parent.NetworkService)
local TerrainService = require(script.Parent.TerrainService)

type Remotes = NetworkService.Remotes
type ProjectileDefinition = Weapons.ProjectileDefinition
type BallisticState = Ballistics.State

local ProjectileService = {}

local shotSequence = 0
local lastRequestAt: { [Player]: number } = {}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function reject(remotes: Remotes, player: Player, reason: string)
	remotes.combatEvent:FireClient(player, "FireRejected", {
		reason = reason,
	})
end

local function validateRequest(request: unknown): (ProjectileDefinition?, number?, number?, string?)
	if typeof(request) ~= "table" then
		return nil, nil, nil, "invalid_request"
	end

	local requestTable = request :: { [string]: any }
	local weaponId = requestTable.weaponId
	local angle = requestTable.angle
	local power = requestTable.power
	if typeof(weaponId) ~= "string" or typeof(angle) ~= "number" or typeof(power) ~= "number" then
		return nil, nil, nil, "invalid_request_fields"
	end
	if not isFinite(angle) or not isFinite(power) then
		return nil, nil, nil, "non_finite_shot"
	end
	if angle < GameConfig.minimumAimDegrees or angle > GameConfig.maximumAimDegrees then
		return nil, nil, nil, "angle_out_of_range"
	end
	if power < GameConfig.minimumPower or power > GameConfig.maximumPower then
		return nil, nil, nil, "power_out_of_range"
	end

	local definition = Weapons.get(weaponId)
	if not definition then
		return nil, nil, nil, "unknown_weapon"
	end
	return definition, angle, power, nil
end

local function reflectVelocity(velocity: Vector3, normal: Vector3, restitution: number): Vector3
	local reflected = velocity - 2 * velocity:Dot(normal) * normal
	return reflected * restitution
end

local function simulateShot(
	remotes: Remotes,
	player: Player,
	definition: ProjectileDefinition,
	origin: Vector3,
	velocity: Vector3,
	acceleration: Vector3,
	shotId: string,
	seed: number
)
	local state: BallisticState = Ballistics.createState(origin, velocity)
	local accumulator = 0
	local bouncesRemaining = definition.bounceCount
	local finished = false
	local connection: RBXScriptConnection? = nil

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true
	raycastParams.FilterDescendantsInstances = if player.Character then { player.Character } else {}

	local function finish(
		position: Vector3,
		normal: Vector3,
		terrainPathStart: Vector3?,
		suppressTerrain: boolean?
	)
		if finished then
			return
		end
		finished = true
		if connection then
			connection:Disconnect()
			connection = nil
		end

		local damageSucceeded, damageError =
			pcall(DamageService.applyExplosion, position, definition, player)
		if not damageSucceeded then
			warn(string.format("[CritterClash] Explosion damage failed: %s", tostring(damageError)))
		end

		local terrainCellsChanged = 0
		local terrainSucceeded, terrainResult = pcall(function(): number
			if suppressTerrain then
				return 0
			end
			if terrainPathStart then
				return TerrainService.applyDrillPath(
					terrainPathStart,
					position,
					definition.terrainRadius
				)
			end
			return TerrainService.applyImpact(position, definition.terrainRadius)
		end)
		if terrainSucceeded then
			terrainCellsChanged = terrainResult :: number
		else
			warn(string.format("[CritterClash] Terrain impact failed: %s", tostring(terrainResult)))
		end
		remotes.combatEvent:FireAllClients("ProjectileImpacted", {
			shotId = shotId,
			position = position,
			normal = normal,
			weaponId = definition.id,
			terrainCellsChanged = terrainCellsChanged,
			terrainRevision = TerrainService.getRevision(),
		})
		MatchService.finishProjectile()
	end

	remotes.combatEvent:FireAllClients("ProjectileLaunched", {
		shotId = shotId,
		weaponId = definition.id,
		origin = origin,
		velocity = velocity,
		acceleration = acceleration,
		serverTime = Workspace:GetServerTimeNow(),
		seed = seed,
	})

	connection = RunService.Heartbeat:Connect(function(deltaTime)
		accumulator += math.min(deltaTime, 0.25)
		local steps = 0

		while
			accumulator >= GameConfig.projectileStepSeconds
			and steps < GameConfig.projectileMaxStepsPerHeartbeat
			and not finished
		do
			accumulator -= GameConfig.projectileStepSeconds
			steps += 1

			local nextState = Ballistics.step(state, acceleration, GameConfig.projectileStepSeconds)
			local displacement = nextState.position - state.position
			local hit = Workspace:Raycast(state.position, displacement, raycastParams)

			if hit then
				if bouncesRemaining > 0 then
					bouncesRemaining -= 1
					state = {
						position = hit.Position + hit.Normal * 0.08,
						velocity = reflectVelocity(
							nextState.velocity,
							hit.Normal,
							definition.restitution
						),
						elapsed = nextState.elapsed,
					}
					if definition.detonationMode == "BounceLimit" and bouncesRemaining == 0 then
						finish(hit.Position, hit.Normal)
					end
				elseif
					definition.detonationMode == "Drill"
					and TerrainService.isTerrainInstance(hit.Instance)
				then
					if TerrainService.isIndestructibleInstance(hit.Instance) then
						finish(hit.Position, hit.Normal, nil, true)
					else
						local direction = if displacement.Magnitude > 0
							then displacement.Unit
							else Vector3.xAxis
						local requestedEnd = hit.Position + direction * definition.penetrationDepth
						local clippedEnd =
							TerrainService.clipDrillEndpoint(hit.Position, requestedEnd)
						finish(clippedEnd, hit.Normal, hit.Position)
					end
				else
					finish(hit.Position, hit.Normal)
				end
			else
				state = nextState
			end

			local fuseExpired = definition.fuseTime ~= nil and state.elapsed >= definition.fuseTime
			local lifetimeExpired = state.elapsed >= definition.maxLifetime
			local outsideSimulationBounds = math.abs(state.position.X)
					> GameConfig.arenaHalfWidth + 80
				or state.position.Y < GameConfig.deathHeight - 40
				or state.position.Y > 180
			if not finished and (fuseExpired or lifetimeExpired or outsideSimulationBounds) then
				finish(state.position, Vector3.yAxis)
			end
		end
	end)

	-- A wall-clock watchdog guarantees that a future simulation error cannot leave
	-- the authoritative match permanently stuck in ProjectileResolving.
	task.delay(definition.maxLifetime + 2, function()
		if not finished then
			warn(string.format("[CritterClash] Projectile watchdog resolved shot %s", shotId))
			finish(state.position, Vector3.yAxis)
		end
	end)
end

local function onFireRequested(remotes: Remotes, player: Player, request: unknown)
	local now = os.clock()
	local previous = lastRequestAt[player]
	if previous and now - previous < GameConfig.remoteRateLimitSeconds then
		reject(remotes, player, "rate_limited")
		return
	end
	lastRequestAt[player] = now

	local definition, angle, power, validationReason = validateRequest(request)
	if not definition or not angle or not power then
		reject(remotes, player, validationReason or "invalid_request")
		return
	end

	local canFire, matchReason = MatchService.canFire(player)
	if not canFire then
		reject(remotes, player, matchReason or "shot_rejected")
		return
	end

	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		reject(remotes, player, "missing_character_root")
		return
	end

	local rootPosition = root.Position
	if
		math.abs(rootPosition.X) > GameConfig.arenaHalfWidth
		or math.abs(rootPosition.Z - GameConfig.combatPlaneZ) > 2
	then
		reject(remotes, player, "invalid_character_position")
		return
	end

	local origin = Vector3.new(rootPosition.X, rootPosition.Y + 2.4, GameConfig.combatPlaneZ)
	local speed = Weapons.resolveSpeed(definition, power)
	local velocity = Ballistics.worldLaunchVelocity(angle, speed)
	local acceleration = Ballistics.acceleration({
		gravity = Vector3.new(0, -GameConfig.projectileWorldGravity, 0),
		wind = Wind.asAcceleration(MatchService.getWind()),
		gravityScale = definition.gravityScale,
		windScale = definition.windScale,
	})

	local allowed, beginReason = MatchService.beginProjectile(player)
	if not allowed then
		reject(remotes, player, beginReason or "shot_rejected")
		return
	end

	shotSequence += 1
	local seed = bit32.band(
		bit32.bxor(
			bit32.band(player.UserId, 0xFFFFFFFF),
			bit32.lshift(bit32.band(shotSequence, 0xFFFF), 16),
			0x6D2B79F5
		),
		0x7FFFFFFF
	)
	local shotId = string.format("%d:%d", player.UserId, shotSequence)
	local launched = pcall(
		simulateShot,
		remotes,
		player,
		definition,
		origin,
		velocity,
		acceleration,
		shotId,
		seed
	)
	if not launched then
		warn("[CritterClash] Projectile launch failed before simulation started")
		reject(remotes, player, "server_simulation_error")
		MatchService.finishProjectile()
	end
end

function ProjectileService.start(remotes: Remotes)
	remotes.requestFire.OnServerEvent:Connect(function(player, request)
		onFireRequested(remotes, player, request)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRequestAt[player] = nil
	end)
end

return ProjectileService
