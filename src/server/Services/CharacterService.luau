--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

type LifecycleState = "Participant" | "Loading" | "Eliminated" | "Spectator"

local LEFT_SPAWN_X = -64
local RIGHT_SPAWN_X = 64
local CHARACTER_SPAWN_Y = 13
local SPECTATOR_HEIGHT = 512
local SPECTATOR_DEPTH = 128
local RELOAD_RETRY_SECONDS = 1

local CharacterService = {}

local activePlayer: Player? = nil
local lifecycleByPlayer: { [Player]: LifecycleState } = {}
local spawnXByPlayer: { [Player]: number } = {}
local turnStartX: { [Player]: number } = {}
local desiredReloadGeneration: { [Player]: number } = {}
local inFlightReloadGeneration: { [Player]: number } = {}
local rootWatchConnections: { [Player]: RBXScriptConnection } = {}
local heartbeatConnection: RBXScriptConnection? = nil
local started = false
local configurationGeneration = 0

local ensureReload: (player: Player) -> ()

local function setCharacterMovement(character: Model, enabled: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = if enabled then GameConfig.maxHorizontalSpeed else 0
		humanoid.JumpHeight = if enabled then 7.2 else 0
		humanoid.AutoRotate = enabled
	end
end

local function spectatorCFrame(player: Player): CFrame
	-- Spectators stay anchored outside every authoritative combat/query volume. The
	-- small deterministic offset keeps multiple spectator cameras from overlapping.
	local offset = (math.abs(player.UserId) % 17) - 8
	return CFrame.new(offset * 3, SPECTATOR_HEIGHT, GameConfig.combatPlaneZ + SPECTATOR_DEPTH)
end

local function setLifecycleAttributes(player: Player, state: LifecycleState, spawnX: number?)
	player:SetAttribute("MatchCharacterState", state)
	player:SetAttribute("MatchSpawnX", spawnX)
end

local function isParticipantState(player: Player): boolean
	return lifecycleByPlayer[player] == "Participant" and player.Parent == Players
end

local function configureCharacterRoot(player: Player, character: Model, root: BasePart)
	if player.Character ~= character then
		return
	end

	local spawnX = spawnXByPlayer[player]
	if isParticipantState(player) and spawnX then
		root.Anchored = false
		character:PivotTo(CFrame.new(spawnX, CHARACTER_SPAWN_Y, GameConfig.combatPlaneZ))
		setCharacterMovement(character, player == activePlayer)

		local canSetNetworkOwnership = root:CanSetNetworkOwnership()
		if canSetNetworkOwnership then
			root:SetNetworkOwner(nil)
		end
	else
		setCharacterMovement(character, false)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(spectatorCFrame(player))
		root.Anchored = true
	end
end

local function placeCharacter(player: Player, character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		root = character:WaitForChild("HumanoidRootPart", 10)
	end
	if player.Character ~= character or not root or not root:IsA("BasePart") then
		return
	end
	configureCharacterRoot(player, character, root)
end

local function applyCurrentCharacterState(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		-- Existing characters are parked synchronously before terrain collision swaps.
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
			-- A newer match configuration arrived while the old load yielded. Serialize
			-- the replacement so that stale CharacterAdded events cannot full-heal it.
			ensureReload(player)
		elseif loaded and configurationGeneration == desiredGeneration then
			-- LoadCharacterAsync may apply a SpawnLocation after CharacterAdded. Reapply
			-- the authoritative side once the yielding engine call has fully completed.
			applyCurrentCharacterState(player)
		end
	end)
end

local function onCharacterAdded(player: Player, character: Model)
	local existingRootWatch = rootWatchConnections[player]
	if existingRootWatch then
		existingRootWatch:Disconnect()
		rootWatchConnections[player] = nil
	end

	local desiredGeneration = desiredReloadGeneration[player]
	if
		desiredGeneration
		and inFlightReloadGeneration[player] == desiredGeneration
		and lifecycleByPlayer[player] == "Loading"
	then
		promoteReloadedCharacter(player, desiredGeneration, character)
	end

	rootWatchConnections[player] = character.ChildAdded:Connect(function(child)
		if child.Name == "HumanoidRootPart" and child:IsA("BasePart") then
			local connection = rootWatchConnections[player]
			if connection then
				connection:Disconnect()
				rootWatchConnections[player] = nil
			end
			applyCurrentCharacterState(player)
		end
	end)
	if character:FindFirstChild("HumanoidRootPart") then
		local connection = rootWatchConnections[player]
		if connection then
			connection:Disconnect()
			rootWatchConnections[player] = nil
		end
	end
	task.spawn(placeCharacter, player, character)
	task.delay(0.1, function()
		if player.Character == character then
			applyCurrentCharacterState(player)
		end
	end)
end

local function constrainCharacter(player: Player)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end

	if not isParticipantState(player) then
		local target = spectatorCFrame(player)
		if not root.Anchored or (root.Position - target.Position).Magnitude > 0.5 then
			configureCharacterRoot(player, character :: Model, root)
		end
		return
	end

	local position = root.Position
	if position.Y < GameConfig.deathHeight then
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
		return
	end

	local x = position.X
	local startX = turnStartX[player]
	if player == activePlayer and startX then
		x = math.clamp(
			x,
			startX - GameConfig.movementAllowanceStuds,
			startX + GameConfig.movementAllowanceStuds
		)
	end
	x = math.clamp(x, -GameConfig.arenaHalfWidth + 3, GameConfig.arenaHalfWidth - 3)

	if math.abs(position.Z - GameConfig.combatPlaneZ) > 0.01 or math.abs(x - position.X) > 0.01 then
		root.CFrame = CFrame.new(x, position.Y, GameConfig.combatPlaneZ) * root.CFrame.Rotation
	end

	local velocity = root.AssemblyLinearVelocity
	if math.abs(velocity.Z) > 0.01 then
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, velocity.Y, 0)
	end
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
	table.clear(turnStartX)

	local nextLifecycle: { [Player]: LifecycleState } = {}
	local nextSpawnX: { [Player]: number } = {}
	local included: { [Player]: boolean } = {}
	local connectedParticipants = {}

	for _, player in participants do
		if player.Parent == Players and not included[player] then
			included[player] = true
			table.insert(connectedParticipants, player)
			local spawnX = spawnXForSlot(#connectedParticipants)
			local needsReload = reloadCharacters == true or inFlightReloadGeneration[player] ~= nil
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

function CharacterService.markEliminated(player: Player)
	local state = lifecycleByPlayer[player]
	if state ~= "Participant" and state ~= "Loading" then
		return
	end

	desiredReloadGeneration[player] = nil
	lifecycleByPlayer[player] = "Eliminated"
	turnStartX[player] = nil
	if activePlayer == player then
		activePlayer = nil
	end
	setLifecycleAttributes(player, "Eliminated", spawnXByPlayer[player])
	applyCurrentCharacterState(player)
end

function CharacterService.setSpectator(player: Player)
	desiredReloadGeneration[player] = nil
	lifecycleByPlayer[player] = "Spectator"
	spawnXByPlayer[player] = nil
	turnStartX[player] = nil
	if activePlayer == player then
		activePlayer = nil
	end
	setLifecycleAttributes(player, "Spectator", nil)
	applyCurrentCharacterState(player)
end

function CharacterService.isEligible(player: Player): boolean
	if not isParticipantState(player) then
		return false
	end

	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return humanoid ~= nil and humanoid.Health > 0
end

function CharacterService.start()
	assert(not started, "CharacterService may only be started once")
	started = true

	for _, player in Players:GetPlayers() do
		observePlayer(player)
	end
	Players.PlayerAdded:Connect(observePlayer)

	Players.PlayerRemoving:Connect(function(player)
		lifecycleByPlayer[player] = nil
		spawnXByPlayer[player] = nil
		turnStartX[player] = nil
		desiredReloadGeneration[player] = nil
		inFlightReloadGeneration[player] = nil
		local rootWatch = rootWatchConnections[player]
		if rootWatch then
			rootWatch:Disconnect()
			rootWatchConnections[player] = nil
		end
		if activePlayer == player then
			activePlayer = nil
		end
	end)

	if not heartbeatConnection then
		heartbeatConnection = RunService.Heartbeat:Connect(function()
			for _, player in Players:GetPlayers() do
				constrainCharacter(player)
			end
		end)
	end
end

function CharacterService.setActivePlayer(player: Player?)
	activePlayer = if player and CharacterService.isEligible(player) then player else nil
	for _, candidate in Players:GetPlayers() do
		local character = candidate.Character
		if character then
			setCharacterMovement(character, candidate == activePlayer)
		end

		if candidate == activePlayer then
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if root and root:IsA("BasePart") then
				turnStartX[candidate] = root.Position.X
			end
		else
			turnStartX[candidate] = nil
		end
	end
end

return CharacterService
