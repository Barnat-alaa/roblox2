--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MovementRules = require(ReplicatedStorage.Shared.Simulation.MovementRules)

local TerrainService = require(script.Parent.TerrainService)

type LifecycleState = "Participant" | "Loading" | "Eliminated" | "Spectator"

type MovementLedger = {
	turnToken: number,
	lastSequence: number,
	inputX: number,
	inputLeaseUntil: number,
	horizontal: MovementRules.State,
	correctionActive: boolean,
	lastRemainingPublishedAt: number,
	lastAcceptedJumpAt: number?,
	jumpsUsed: number,
}

export type SettlementResult = {
	completed: boolean,
	timedOut: boolean,
	eliminatedCount: number,
}

local LEFT_SPAWN_X = -64
local RIGHT_SPAWN_X = 64
local CHARACTER_SPAWN_Y = 13
local SPECTATOR_HEIGHT = 512
local SPECTATOR_DEPTH = 128
local RELOAD_RETRY_SECONDS = 1
local ARENA_MARGIN = 3
local GROUNDED_RECENCY_SECONDS = 0.15
local JUMP_AUTHORIZATION_SECONDS = 0.25
local MAX_RECOVERY_DROP = 160
local GROUNDED_VERTICAL_SPEED_LIMIT = 2
local MOVEMENT_BUDGET_EPSILON = 1e-3
local MOVEMENT_ATTRIBUTE_INTERVAL_SECONDS = 0.1
local DIAGNOSTICS_INTERVAL_SECONDS = 1

local MOVEMENT_CONFIG: MovementRules.Config = table.freeze({
	minimumX = -GameConfig.arenaHalfWidth + ARENA_MARGIN,
	maximumX = GameConfig.arenaHalfWidth - ARENA_MARGIN,
	movementAllowance = GameConfig.movementAllowanceStuds,
	maxHorizontalSpeed = GameConfig.maxHorizontalSpeed,
	stepTolerance = GameConfig.movementStepToleranceStuds,
	maxSampleInterval = GameConfig.movementMaxSampleIntervalSeconds,
})

local CharacterService = {}

local activePlayer: Player? = nil
local lifecycleByPlayer: { [Player]: LifecycleState } = {}
local spawnXByPlayer: { [Player]: number } = {}
local desiredReloadGeneration: { [Player]: number } = {}
local inFlightReloadGeneration: { [Player]: number } = {}
local characterReadyConnections: { [Player]: RBXScriptConnection } = {}
local humanoidStateConnections: { [Player]: RBXScriptConnection } = {}
local movementByPlayer: { [Player]: MovementLedger } = {}
local lastGroundedAtByPlayer: { [Player]: number } = {}
local authorizedJumpUntilByPlayer: { [Player]: number } = {}
local combatantModels: { [Model]: boolean } = {}
local authoritativeXByModel: { [Model]: number } = {}
local externalMotionUntilByModel: { [Model]: number } = {}
local npcCombatant: Model? = nil
local heartbeatConnection: RBXScriptConnection? = nil
local started = false
local configurationGeneration = 0
local movementCorrectionCount = 0
local rejectedJumpCount = 0
local settlementTimeoutCount = 0
local diagnosticsDirty = true
local lastDiagnosticsAt = -math.huge

local ensureReload: (player: Player) -> ()

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isFiniteVector(value: Vector3): boolean
	return isFinite(value.X) and isFinite(value.Y) and isFinite(value.Z)
end

local function markDiagnosticsDirty()
	diagnosticsDirty = true
end

local function publishDiagnostics(now: number, force: boolean?)
	if
		not force
		and (not diagnosticsDirty or now - lastDiagnosticsAt < DIAGNOSTICS_INTERVAL_SECONDS)
	then
		return
	end
	Workspace:SetAttribute("CritterClashMovementCorrectionCount", movementCorrectionCount)
	Workspace:SetAttribute("CritterClashRejectedJumpCount", rejectedJumpCount)
	Workspace:SetAttribute("CritterClashSettlementTimeoutCount", settlementTimeoutCount)
	diagnosticsDirty = false
	lastDiagnosticsAt = now
end

local function rootForModel(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function humanoidForModel(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

local function setCharacterMovement(character: Model, enabled: boolean)
	local humanoid = humanoidForModel(character)
	if humanoid then
		humanoid.WalkSpeed = if enabled then GameConfig.maxHorizontalSpeed else 0
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = if enabled then 7.2 else 0
		humanoid.AutoRotate = false
		if not enabled then
			humanoid:Move(Vector3.zero, false)
			humanoid.Jump = false
		end
	end
end

local function spectatorCFrame(player: Player): CFrame
	local offset = (math.abs(player.UserId) % 17) - 8
	return CFrame.new(offset * 3, SPECTATOR_HEIGHT, GameConfig.combatPlaneZ + SPECTATOR_DEPTH)
end

local function setLifecycleAttributes(player: Player, state: LifecycleState, spawnX: number?)
	player:SetAttribute("MatchCharacterState", state)
	player:SetAttribute("MatchSpawnX", spawnX)
	player:SetAttribute("MatchMovementRemaining", nil)
end

local function isParticipantState(player: Player): boolean
	return lifecycleByPlayer[player] == "Participant" and player.Parent == Players
end

local function hasLivingCharacter(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local humanoid = humanoidForModel(character)
	local root = rootForModel(character)
	return humanoid ~= nil and humanoid.Health > 0 and root ~= nil
end

local function configureServerOwnership(root: BasePart)
	local canSetNetworkOwnership = root:CanSetNetworkOwnership()
	if canSetNetworkOwnership then
		root:SetNetworkOwner(nil)
	end
end

local function refreshCombatantModels()
	local nextModels: { [Model]: boolean } = {}
	for player, state in lifecycleByPlayer do
		local character = player.Character
		if state == "Participant" and player.Parent == Players and character then
			nextModels[character] = true
		end
	end
	local npc = npcCombatant
	if npc and npc.Parent ~= nil then
		nextModels[npc] = true
	end

	combatantModels = nextModels
	for model in authoritativeXByModel do
		if not nextModels[model] then
			authoritativeXByModel[model] = nil
			externalMotionUntilByModel[model] = nil
		end
	end
end

local function footOffset(model: Model, root: BasePart, humanoid: Humanoid): number
	if Players:GetPlayerFromCharacter(model) then
		if humanoid.RigType == Enum.HumanoidRigType.R6 then
			-- Standard R6 legs extend two studs below the torso/root assembly.
			return root.Size.Y * 0.5 + 2
		end
		return root.Size.Y * 0.5 + humanoid.HipHeight
	end
	return root.Size.Y * 0.5
end

local function supportForModel(model: Model, maximumDrop: number): TerrainService.SupportResult?
	local root = rootForModel(model)
	local humanoid = humanoidForModel(model)
	if not root or not humanoid then
		return nil
	end
	local halfFootprint = math.clamp(root.Size.X * 0.45, 0.5, 2.25)
	local footY = root.Position.Y - footOffset(model, root, humanoid)
	return TerrainService.findSupportBelow(
		root.Position.X - halfFootprint,
		root.Position.X + halfFootprint,
		footY,
		maximumDrop,
		GameConfig.groundPenetrationToleranceStuds
	)
end

local function isGroundedModel(model: Model): boolean
	local support = supportForModel(model, GameConfig.groundProbeDistanceStuds)
	if not support or support.kind == "Hazard" then
		return false
	end
	local root = rootForModel(model)
	local humanoid = humanoidForModel(model)
	if
		not root
		or not humanoid
		or math.abs(root.AssemblyLinearVelocity.Y) > GROUNDED_VERTICAL_SPEED_LIMIT
	then
		return false
	end
	if not Players:GetPlayerFromCharacter(model) then
		return true
	end
	local state = humanoid:GetState()
	return humanoid.FloorMaterial ~= Enum.Material.Air
		or state == Enum.HumanoidStateType.Landed
		or state == Enum.HumanoidStateType.Running
		or state == Enum.HumanoidStateType.RunningNoPhysics
end

local function killCombatant(model: Model)
	if not combatantModels[model] then
		return
	end
	local humanoid = humanoidForModel(model)
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

local function rejectUnauthorizedJump(player: Player, humanoid: Humanoid)
	rejectedJumpCount += 1
	markDiagnosticsDirty()
	humanoid.Jump = false
	local character = player.Character
	local root = if character then rootForModel(character) else nil
	if root then
		local velocity = root.AssemblyLinearVelocity
		if velocity.Y > 0 then
			root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, 0)
		end
	end
	task.defer(function()
		if humanoid.Parent ~= nil and humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end)
end

local function hookHumanoidState(player: Player, character: Model)
	local existing = humanoidStateConnections[player]
	if existing then
		existing:Disconnect()
		humanoidStateConnections[player] = nil
	end

	local humanoid = humanoidForModel(character)
	if not humanoid then
		return
	end
	humanoidStateConnections[player] = humanoid.StateChanged:Connect(function(_, newState)
		if newState ~= Enum.HumanoidStateType.Jumping then
			return
		end
		local now = Workspace:GetServerTimeNow()
		local authorization = authorizedJumpUntilByPlayer[player]
		authorizedJumpUntilByPlayer[player] = nil
		if
			player ~= activePlayer
			or not authorization
			or authorization < now
			or player.Character ~= character
		then
			rejectUnauthorizedJump(player, humanoid)
		end
	end)
end

local function configureCharacterRoot(player: Player, character: Model, root: BasePart)
	if player.Character ~= character then
		return
	end

	local spawnX = spawnXByPlayer[player]
	if isParticipantState(player) and spawnX then
		root.Anchored = false
		character:PivotTo(CFrame.new(spawnX, CHARACTER_SPAWN_Y, GameConfig.combatPlaneZ))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		setCharacterMovement(character, player == activePlayer)
		configureServerOwnership(root)
		authoritativeXByModel[character] = spawnX
	else
		setCharacterMovement(character, false)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(spectatorCFrame(player))
		root.Anchored = true
		authoritativeXByModel[character] = nil
	end
	refreshCombatantModels()
end

local function placeCharacter(player: Player, character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		root = character:WaitForChild("HumanoidRootPart", 10)
	end
	if player.Character ~= character or not root or not root:IsA("BasePart") then
		return
	end
	hookHumanoidState(player, character)
	configureCharacterRoot(player, character, root)
end

local function applyCurrentCharacterState(player: Player)
	local character = player.Character
	if not character then
		refreshCombatantModels()
		return
	end
	local root = rootForModel(character)
	if root then
		hookHumanoidState(player, character)
		configureCharacterRoot(player, character, root)
	else
		task.spawn(placeCharacter, player, character)
	end
end

local function promoteReloadedCharacter(player: Player, generation: number, character: Model)
	if
		desiredReloadGeneration[player] ~= generation
		or player.Parent ~= Players
		or player.Character ~= character
	then
		return
	end

	desiredReloadGeneration[player] = nil
	lifecycleByPlayer[player] = "Participant"
	setLifecycleAttributes(player, "Participant", spawnXByPlayer[player])
	applyCurrentCharacterState(player)
end

ensureReload = function(player: Player)
	local desiredGeneration = desiredReloadGeneration[player]
	if
		not desiredGeneration
		or inFlightReloadGeneration[player] ~= nil
		or player.Parent ~= Players
	then
		return
	end

	inFlightReloadGeneration[player] = desiredGeneration
	task.spawn(function()
		local loaded, loadError = pcall(function()
			player:LoadCharacterAsync()
		end)

		if inFlightReloadGeneration[player] == desiredGeneration then
			inFlightReloadGeneration[player] = nil
		end
		if player.Parent ~= Players then
			return
		end

		local stillDesired = desiredReloadGeneration[player]
		if stillDesired == desiredGeneration then
			local character = player.Character
			if loaded and character then
				promoteReloadedCharacter(player, desiredGeneration, character)
			else
				warn(
					string.format(
						"[CritterClash] Character reload failed for %d: %s",
						player.UserId,
						tostring(loadError)
					)
				)
				task.delay(RELOAD_RETRY_SECONDS, ensureReload, player)
			end
		elseif stillDesired ~= nil then
			ensureReload(player)
		elseif loaded and configurationGeneration == desiredGeneration then
			applyCurrentCharacterState(player)
		end
	end)
end

local function onCharacterAdded(player: Player, character: Model)
	local existingReadyConnection = characterReadyConnections[player]
	if existingReadyConnection then
		existingReadyConnection:Disconnect()
		characterReadyConnections[player] = nil
	end
	local existingHumanoidConnection = humanoidStateConnections[player]
	if existingHumanoidConnection then
		existingHumanoidConnection:Disconnect()
		humanoidStateConnections[player] = nil
	end

	local desiredGeneration = desiredReloadGeneration[player]
	if
		desiredGeneration
		and inFlightReloadGeneration[player] == desiredGeneration
		and lifecycleByPlayer[player] == "Loading"
	then
		promoteReloadedCharacter(player, desiredGeneration, character)
	end

	characterReadyConnections[player] = character.ChildAdded:Connect(function()
		if rootForModel(character) and humanoidForModel(character) then
			local connection = characterReadyConnections[player]
			if connection then
				connection:Disconnect()
				characterReadyConnections[player] = nil
			end
			hookHumanoidState(player, character)
			applyCurrentCharacterState(player)
		end
	end)
	if rootForModel(character) and humanoidForModel(character) then
		local connection = characterReadyConnections[player]
		if connection then
			connection:Disconnect()
			characterReadyConnections[player] = nil
		end
		hookHumanoidState(player, character)
	end
	task.spawn(placeCharacter, player, character)
	task.delay(0.1, function()
		if player.Character == character then
			applyCurrentCharacterState(player)
		end
	end)
end

local function externalMotionAllowed(model: Model, now: number): boolean
	local expiresAt = externalMotionUntilByModel[model]
	return expiresAt ~= nil and now < expiresAt
end

local function correctRootPosition(root: BasePart, acceptedX: number, correctX: boolean)
	local position = root.Position
	local correctZ = math.abs(position.Z - GameConfig.combatPlaneZ) > 0.01
	if correctX or correctZ then
		root.CFrame = CFrame.new(
			if correctX then acceptedX else position.X,
			position.Y,
			GameConfig.combatPlaneZ
		) * root.CFrame.Rotation
	end

	local velocity = root.AssemblyLinearVelocity
	local nextX = velocity.X
	if
		correctX
		or (position.X <= MOVEMENT_CONFIG.minimumX and velocity.X < 0)
		or (position.X >= MOVEMENT_CONFIG.maximumX and velocity.X > 0)
	then
		nextX = 0
	end
	if nextX ~= velocity.X or math.abs(velocity.Z) > 0.01 then
		root.AssemblyLinearVelocity = Vector3.new(nextX, velocity.Y, 0)
	end
end

local function constrainCombatant(model: Model, player: Player?, now: number)
	if not combatantModels[model] then
		return
	end
	local root = rootForModel(model)
	local humanoid = humanoidForModel(model)
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	if not isFiniteVector(root.Position) or not isFiniteVector(root.AssemblyLinearVelocity) then
		killCombatant(model)
		return
	end
	if root.Position.Y < GameConfig.deathHeight then
		killCombatant(model)
		return
	end

	local requestedX = root.Position.X
	local boundedX = math.clamp(requestedX, MOVEMENT_CONFIG.minimumX, MOVEMENT_CONFIG.maximumX)
	local acceptedX = boundedX
	local correctX = boundedX ~= requestedX
	local external = externalMotionAllowed(model, now)
	local ledger = if player then movementByPlayer[player] else nil

	if player and ledger and player == activePlayer then
		local humanoidInput = if now <= ledger.inputLeaseUntil then ledger.inputX else 0
		humanoid:Move(Vector3.new(humanoidInput, 0, 0), false)
		local decision = MovementRules.applyHorizontalSample(
			ledger.horizontal,
			requestedX,
			now,
			MOVEMENT_CONFIG,
			external
		)
		acceptedX = decision.acceptedX
		correctX = math.abs(acceptedX - requestedX) > 0.01
		authoritativeXByModel[model] = acceptedX
		local movementRemaining =
			MovementRules.remainingDistance(ledger.horizontal, MOVEMENT_CONFIG)
		if
			movementRemaining <= MOVEMENT_BUDGET_EPSILON
			or now - ledger.lastRemainingPublishedAt >= MOVEMENT_ATTRIBUTE_INTERVAL_SECONDS
		then
			local displayedRemaining = player:GetAttribute("MatchMovementRemaining")
			if
				typeof(displayedRemaining) ~= "number"
				or math.abs((displayedRemaining :: number) - movementRemaining) > 0.01
			then
				player:SetAttribute("MatchMovementRemaining", movementRemaining)
			end
			ledger.lastRemainingPublishedAt = now
		end
		if movementRemaining <= MOVEMENT_BUDGET_EPSILON and not external then
			ledger.inputX = 0
			ledger.inputLeaseUntil = 0
			humanoid:Move(Vector3.zero, false)
			if math.abs(root.AssemblyLinearVelocity.X) > 0.01 then
				correctX = true
			end
		end
		if decision.corrected and not ledger.correctionActive then
			movementCorrectionCount += 1
			markDiagnosticsDirty()
		end
		ledger.correctionActive = decision.corrected
	else
		humanoid:Move(Vector3.zero, false)
		if external then
			authoritativeXByModel[model] = boundedX
		else
			acceptedX = authoritativeXByModel[model] or boundedX
			authoritativeXByModel[model] = acceptedX
			correctX = math.abs(acceptedX - requestedX) > 0.01
		end
	end

	correctRootPosition(root, acceptedX, correctX)
	if player and isGroundedModel(model) then
		lastGroundedAtByPlayer[player] = now
	end
end

local function constrainCharacter(player: Player, now: number)
	local character = player.Character
	local root = if character then rootForModel(character) else nil
	if not character or not root then
		return
	end
	if not isParticipantState(player) then
		local target = spectatorCFrame(player)
		if not root.Anchored or (root.Position - target.Position).Magnitude > 0.5 then
			configureCharacterRoot(player, character, root)
		end
		return
	end
	constrainCombatant(character, player, now)
end

local function observePlayer(player: Player)
	if lifecycleByPlayer[player] == nil then
		lifecycleByPlayer[player] = "Spectator"
		setLifecycleAttributes(player, "Spectator", nil)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

local function spawnXForSlot(slot: number): number
	if slot == 1 then
		return LEFT_SPAWN_X
	elseif slot == 2 then
		return RIGHT_SPAWN_X
	end
	local side = if slot % 2 == 1 then -1 else 1
	local inwardSteps = math.floor((slot - 1) / 2)
	return side * (math.abs(RIGHT_SPAWN_X) - inwardSteps * 8)
end

function CharacterService.configureMatch(participants: { Player }, reloadCharacters: boolean?)
	configurationGeneration += 1
	local generation = configurationGeneration
	activePlayer = nil
	table.clear(movementByPlayer)
	table.clear(authorizedJumpUntilByPlayer)

	local nextLifecycle: { [Player]: LifecycleState } = {}
	local nextSpawnX: { [Player]: number } = {}
	local included: { [Player]: boolean } = {}
	local connectedParticipants = {}
	for _, player in participants do
		if player.Parent == Players and not included[player] then
			included[player] = true
			table.insert(connectedParticipants, player)
			local spawnX = spawnXForSlot(#connectedParticipants)
			local needsReload = reloadCharacters == true
				or inFlightReloadGeneration[player] ~= nil
				or not hasLivingCharacter(player)
			nextLifecycle[player] = if needsReload then "Loading" else "Participant"
			nextSpawnX[player] = spawnX
			if needsReload then
				desiredReloadGeneration[player] = generation
			else
				desiredReloadGeneration[player] = nil
			end
		end
	end

	for _, player in Players:GetPlayers() do
		if not included[player] then
			nextLifecycle[player] = "Spectator"
			desiredReloadGeneration[player] = nil
		end
	end
	lifecycleByPlayer = nextLifecycle
	spawnXByPlayer = nextSpawnX
	refreshCombatantModels()

	for _, player in Players:GetPlayers() do
		local state: LifecycleState = lifecycleByPlayer[player] or "Spectator"
		setLifecycleAttributes(player, state, spawnXByPlayer[player])
		applyCurrentCharacterState(player)
	end
	for _, player in connectedParticipants do
		if desiredReloadGeneration[player] == generation then
			ensureReload(player)
		end
	end
end

function CharacterService.setNpcCombatant(model: Model?)
	local previous = npcCombatant
	if previous and previous ~= model then
		externalMotionUntilByModel[previous] = nil
		authoritativeXByModel[previous] = nil
	end
	npcCombatant = model
	if model then
		local root = rootForModel(model)
		if root then
			root.Anchored = false
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			configureServerOwnership(root)
			authoritativeXByModel[model] = root.Position.X
		end
		setCharacterMovement(model, false)
	end
	refreshCombatantModels()
end

function CharacterService.markEliminated(player: Player)
	local state = lifecycleByPlayer[player]
	if state ~= "Participant" and state ~= "Loading" then
		return
	end
	desiredReloadGeneration[player] = nil
	lifecycleByPlayer[player] = "Eliminated"
	movementByPlayer[player] = nil
	authorizedJumpUntilByPlayer[player] = nil
	if activePlayer == player then
		activePlayer = nil
	end
	setLifecycleAttributes(player, "Eliminated", spawnXByPlayer[player])
	refreshCombatantModels()
	applyCurrentCharacterState(player)
end

function CharacterService.setSpectator(player: Player)
	desiredReloadGeneration[player] = nil
	lifecycleByPlayer[player] = "Spectator"
	spawnXByPlayer[player] = nil
	movementByPlayer[player] = nil
	authorizedJumpUntilByPlayer[player] = nil
	if activePlayer == player then
		activePlayer = nil
	end
	setLifecycleAttributes(player, "Spectator", nil)
	refreshCombatantModels()
	applyCurrentCharacterState(player)
end

function CharacterService.isEligible(player: Player): boolean
	if not isParticipantState(player) then
		return false
	end
	local character = player.Character
	local humanoid = if character then humanoidForModel(character) else nil
	local root = if character then rootForModel(character) else nil
	return character ~= nil
		and humanoid ~= nil
		and humanoid.Health > 0
		and root ~= nil
		and isFiniteVector(root.Position)
		and root.Position.Y >= GameConfig.deathHeight
		and math.abs(root.Position.Z - GameConfig.combatPlaneZ) <= 0.25
end

function CharacterService.isCombatantModel(model: Model): boolean
	return combatantModels[model] == true and model.Parent ~= nil
end

function CharacterService.isModelReadyForTurn(model: Model): boolean
	if not CharacterService.isCombatantModel(model) then
		return false
	end
	local humanoid = humanoidForModel(model)
	local root = rootForModel(model)
	return humanoid ~= nil
		and humanoid.Health > 0
		and root ~= nil
		and isFiniteVector(root.Position)
		and isGroundedModel(model)
		and root.AssemblyLinearVelocity.Magnitude <= GameConfig.environmentStableLinearSpeed * 2
end

function CharacterService.isReadyForTurn(player: Player): boolean
	local character = player.Character
	return CharacterService.isEligible(player)
		and character ~= nil
		and CharacterService.isModelReadyForTurn(character)
end

function CharacterService.start()
	assert(not started, "CharacterService may only be started once")
	started = true
	publishDiagnostics(Workspace:GetServerTimeNow(), true)
	TerrainService.setHazardContactHandler(function(model)
		killCombatant(model)
	end)

	for _, player in Players:GetPlayers() do
		observePlayer(player)
	end
	Players.PlayerAdded:Connect(observePlayer)
	Players.PlayerRemoving:Connect(function(player)
		local character = player.Character
		lifecycleByPlayer[player] = nil
		spawnXByPlayer[player] = nil
		desiredReloadGeneration[player] = nil
		inFlightReloadGeneration[player] = nil
		movementByPlayer[player] = nil
		lastGroundedAtByPlayer[player] = nil
		authorizedJumpUntilByPlayer[player] = nil
		if character then
			authoritativeXByModel[character] = nil
			externalMotionUntilByModel[character] = nil
		end
		local readyConnection = characterReadyConnections[player]
		if readyConnection then
			readyConnection:Disconnect()
			characterReadyConnections[player] = nil
		end
		local humanoidConnection = humanoidStateConnections[player]
		if humanoidConnection then
			humanoidConnection:Disconnect()
			humanoidStateConnections[player] = nil
		end
		if activePlayer == player then
			activePlayer = nil
		end
		refreshCombatantModels()
	end)

	if not heartbeatConnection then
		heartbeatConnection = RunService.Heartbeat:Connect(function()
			local now = Workspace:GetServerTimeNow()
			for _, player in Players:GetPlayers() do
				constrainCharacter(player, now)
			end
			local npc = npcCombatant
			if npc and npc.Parent ~= nil then
				constrainCombatant(npc, nil, now)
			end
			publishDiagnostics(now)
		end)
	end
end

function CharacterService.setActivePlayer(player: Player?, turnToken: number?)
	local nextActive = if player and CharacterService.isEligible(player) then player else nil
	if nextActive and (turnToken == nil or turnToken < 1 or turnToken ~= math.floor(turnToken)) then
		nextActive = nil
	end
	activePlayer = nextActive

	for _, candidate in Players:GetPlayers() do
		local character = candidate.Character
		if character then
			setCharacterMovement(character, candidate == activePlayer)
			local root = rootForModel(character)
			if root then
				authoritativeXByModel[character] =
					math.clamp(root.Position.X, MOVEMENT_CONFIG.minimumX, MOVEMENT_CONFIG.maximumX)
			end
		end

		if candidate == activePlayer and character and turnToken then
			local root = rootForModel(character)
			if root then
				local now = Workspace:GetServerTimeNow()
				movementByPlayer[candidate] = {
					turnToken = turnToken,
					lastSequence = 0,
					inputX = 0,
					inputLeaseUntil = 0,
					horizontal = MovementRules.createState(root.Position.X, now),
					correctionActive = false,
					lastRemainingPublishedAt = now,
					lastAcceptedJumpAt = nil,
					jumpsUsed = 0,
				}
				candidate:SetAttribute("MatchMovementRemaining", GameConfig.movementAllowanceStuds)
			end
		else
			movementByPlayer[candidate] = nil
			authorizedJumpUntilByPlayer[candidate] = nil
			candidate:SetAttribute("MatchMovementRemaining", nil)
		end
	end
end

function CharacterService.submitMovement(
	player: Player,
	turnToken: number,
	sequence: number,
	moveX: number,
	jumpRequested: boolean
): (boolean, string?)
	local ledger = movementByPlayer[player]
	if player ~= activePlayer or not ledger or ledger.turnToken ~= turnToken then
		return false, "stale_movement_turn"
	end
	if sequence <= ledger.lastSequence then
		return false, "stale_movement_sequence"
	end
	local now = Workspace:GetServerTimeNow()
	local character = player.Character
	local humanoid = if character then humanoidForModel(character) else nil
	if jumpRequested then
		local groundedAt = lastGroundedAtByPlayer[player]
		local groundedRecently = groundedAt ~= nil and now - groundedAt <= GROUNDED_RECENCY_SECONDS
		local jumpAllowed, jumpReason = MovementRules.canStartJump(
			ledger.lastAcceptedJumpAt,
			now,
			groundedRecently,
			GameConfig.jumpCooldownSeconds
		)
		if ledger.jumpsUsed >= GameConfig.maxJumpsPerTurn then
			jumpAllowed = false
			jumpReason = "jump_budget"
		end
		if not character or not humanoid or not isGroundedModel(character) then
			jumpAllowed = false
			jumpReason = "not_grounded"
		end
		if not jumpAllowed then
			rejectedJumpCount += 1
			markDiagnosticsDirty()
			return false, jumpReason or "jump_rejected"
		end
	end

	-- Commit only after every requested action validates, so a rejected jump cannot
	-- silently alter the authoritative walking lease or sequence ledger.
	ledger.lastSequence = sequence
	ledger.inputX = math.clamp(moveX, -1, 1)
	ledger.inputLeaseUntil = now + GameConfig.movementInputLeaseSeconds
	if jumpRequested then
		assert(humanoid ~= nil, "validated jump must have a Humanoid")
		ledger.lastAcceptedJumpAt = now
		ledger.jumpsUsed += 1
		authorizedJumpUntilByPlayer[player] = now + JUMP_AUTHORIZATION_SECONDS
		humanoid.Jump = true
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
	return true, nil
end

function CharacterService.applyKnockback(model: Model, requestedVelocity: Vector3): boolean
	if not CharacterService.isCombatantModel(model) or not isFiniteVector(requestedVelocity) then
		return false
	end
	local root = rootForModel(model)
	if not root or root.Anchored then
		return false
	end
	local cappedVelocity = Vector3.new(
		math.clamp(requestedVelocity.X, -80, 80),
		math.clamp(requestedVelocity.Y, -15, 70),
		0
	)
	externalMotionUntilByModel[model] = Workspace:GetServerTimeNow()
		+ GameConfig.externalMotionGraceSeconds
	configureServerOwnership(root)
	local currentVelocity = root.AssemblyLinearVelocity
	root:ApplyImpulse((cappedVelocity - currentVelocity) * root.AssemblyMass)
	return true
end

local function isModelSettled(model: Model): boolean
	if model.Parent == nil then
		return true
	end
	local humanoid = humanoidForModel(model)
	if not humanoid or humanoid.Health <= 0 then
		return true
	end
	local root = rootForModel(model)
	if not root or not isFiniteVector(root.Position) then
		return false
	end
	local support = supportForModel(model, GameConfig.groundProbeDistanceStuds)
	if support and support.kind == "Hazard" then
		killCombatant(model)
		return true
	end
	return support ~= nil
		and root.AssemblyLinearVelocity.Magnitude <= GameConfig.environmentStableLinearSpeed
		and root.AssemblyAngularVelocity.Magnitude <= GameConfig.environmentStableAngularSpeed
end

local function recoverUnsettledModel(model: Model): boolean
	local humanoid = humanoidForModel(model)
	local root = rootForModel(model)
	if model.Parent == nil or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if not root then
		humanoid.Health = 0
		return true
	end

	local support = supportForModel(model, MAX_RECOVERY_DROP)
	if not support or support.kind == "Hazard" then
		killCombatant(model)
		return true
	end
	local offset = footOffset(model, root, humanoid)
	local targetX = math.clamp(root.Position.X, MOVEMENT_CONFIG.minimumX, MOVEMENT_CONFIG.maximumX)
	local target = CFrame.new(targetX, support.surfaceY + offset + 0.05, GameConfig.combatPlaneZ)
		* root.CFrame.Rotation
	model:PivotTo(target)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	authoritativeXByModel[model] = targetX
	return false
end

function CharacterService.awaitEnvironmentSettled(
	models: { Model },
	shouldContinue: () -> boolean
): SettlementResult
	local startedAt = Workspace:GetServerTimeNow()
	local stableSamples = 0
	while shouldContinue() do
		local now = Workspace:GetServerTimeNow()
		local allSettled = true
		for _, model in models do
			if not isModelSettled(model) then
				allSettled = false
			end
		end

		if now - startedAt >= GameConfig.environmentMinimumSeconds and allSettled then
			stableSamples += 1
		else
			stableSamples = 0
		end
		if stableSamples >= GameConfig.environmentStableSamples then
			for _, model in models do
				externalMotionUntilByModel[model] = nil
				local root = rootForModel(model)
				if root then
					authoritativeXByModel[model] = root.Position.X
				end
			end
			return {
				completed = true,
				timedOut = false,
				eliminatedCount = 0,
			}
		end
		if now - startedAt >= GameConfig.environmentSettleTimeoutSeconds then
			break
		end
		task.wait(GameConfig.environmentSettleSampleSeconds)
	end

	if not shouldContinue() then
		return {
			completed = false,
			timedOut = false,
			eliminatedCount = 0,
		}
	end

	settlementTimeoutCount += 1
	markDiagnosticsDirty()
	local eliminatedCount = 0
	for _, model in models do
		if recoverUnsettledModel(model) then
			eliminatedCount += 1
		end
		externalMotionUntilByModel[model] = nil
	end
	return {
		completed = true,
		timedOut = true,
		eliminatedCount = eliminatedCount,
	}
end

return CharacterService
