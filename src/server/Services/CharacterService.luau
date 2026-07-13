--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CharacterService = {}

local activePlayer: Player? = nil
local turnStartX: { [Player]: number } = {}
local heartbeatConnection: RBXScriptConnection? = nil

local function setCharacterEnabled(player: Player, enabled: boolean)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = if enabled then GameConfig.maxHorizontalSpeed else 0
		humanoid.JumpHeight = if enabled then 7.2 else 0
		humanoid.AutoRotate = enabled
	end
end

local function placeCharacter(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end

	local players = Players:GetPlayers()
	local index = table.find(players, player) or 1
	local x = if index % 2 == 1 then -64 else 64
	character:PivotTo(CFrame.new(x, 13, GameConfig.combatPlaneZ))
	setCharacterEnabled(player, player == activePlayer)

	local canSetNetworkOwnership = root:CanSetNetworkOwnership()
	if canSetNetworkOwnership then
		-- Setting ownership on the assembly root covers the connected character
		-- assembly without repeating the operation for every accessory part.
		root:SetNetworkOwner(nil)
	end
end

local function constrainCharacter(player: Player)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end

	local position = root.Position
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

function CharacterService.start()
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			placeCharacter(player, character)
		end)
		if player.Character then
			task.defer(placeCharacter, player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			placeCharacter(player, character)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		turnStartX[player] = nil
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
	activePlayer = player
	for _, candidate in Players:GetPlayers() do
		setCharacterEnabled(candidate, candidate == player)
		if candidate == player then
			local character = candidate.Character
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
