--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)

local CosmeticService = {}

local COSMETIC_MODEL_NAME = "CritterClashCosmetic"
local started = false
local connectionsByPlayer: { [Player]: { RBXScriptConnection } } = {}
local applyGenerationByPlayer: { [Player]: number } = {}

local function configurePart(part: BasePart, color: Color3)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CollisionGroup = "Default"
end

local function weldPart(
	model: Model,
	anchor: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	shape: Enum.PartType?
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Shape = shape or Enum.PartType.Block
	configurePart(part, color)
	part.CFrame = anchor.CFrame * offset
	part.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Name = "CosmeticWeld"
	weld.Part0 = anchor
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function createSunsetScoutScarf(character: Model, anchor: BasePart)
	local definition = Cosmetics.get(Cosmetics.STARTER_COSMETIC_ID)
	if not definition then
		return
	end

	local existing = character:FindFirstChild(COSMETIC_MODEL_NAME)
	if existing then
		existing:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = COSMETIC_MODEL_NAME
	model:SetAttribute("CosmeticId", definition.id)
	model.Parent = character

	local width = math.clamp(anchor.Size.X * 0.92, 1.35, 2.2)
	local depth = math.clamp(anchor.Size.Z * 0.76, 0.62, 1.1)
	local neckY = math.clamp(anchor.Size.Y * 0.42, 0.7, 1.1)
	weldPart(
		model,
		anchor,
		"ScarfBand",
		Vector3.new(width, 0.28, depth),
		CFrame.new(0, neckY, 0),
		definition.primaryColor
	)
	-- The side camera observes the arena from +Z, so the knot remains readable.
	local frontZ = depth * 0.5 + 0.13
	weldPart(
		model,
		anchor,
		"CompassKnot",
		Vector3.new(0.42, 0.42, 0.42),
		CFrame.new(0, neckY - 0.13, frontZ),
		definition.accentColor,
		Enum.PartType.Ball
	)
	weldPart(
		model,
		anchor,
		"ScarfTailLeft",
		Vector3.new(0.34, 0.9, 0.14),
		CFrame.new(-0.21, neckY - 0.65, frontZ + 0.04) * CFrame.Angles(0, 0, math.rad(-13)),
		definition.primaryColor
	)
	weldPart(
		model,
		anchor,
		"ScarfTailRight",
		Vector3.new(0.3, 0.72, 0.15),
		CFrame.new(0.22, neckY - 0.57, frontZ + 0.02) * CFrame.Angles(0, 0, math.rad(18)),
		definition.accentColor
	)
end

local function clearCosmetic(character: Model)
	local existing = character:FindFirstChild(COSMETIC_MODEL_NAME)
	if existing then
		existing:Destroy()
	end
end

local function applyEquipped(player: Player, character: Model, generation: number)
	if player.Character ~= character or character.Parent == nil then
		return
	end
	local cosmeticId = player:GetAttribute("ProfileEquippedCosmetic")
	if type(cosmeticId) ~= "string" then
		clearCosmetic(character)
		return
	end
	local definition = Cosmetics.get(cosmeticId)
	if not definition or not definition.enabled then
		clearCosmetic(character)
		return
	end

	local anchor = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local anchorDeadline = os.clock() + 4
	while
		not anchor
		and player.Character == character
		and applyGenerationByPlayer[player] == generation
		and os.clock() < anchorDeadline
	do
		task.wait(0.05)
		anchor = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	end
	anchor = anchor or character:FindFirstChild("HumanoidRootPart")
	if
		applyGenerationByPlayer[player] ~= generation
		or player:GetAttribute("ProfileEquippedCosmetic") ~= cosmeticId
		or not anchor
		or not anchor:IsA("BasePart")
		or player.Character ~= character
	then
		return
	end

	if cosmeticId == Cosmetics.STARTER_COSMETIC_ID then
		createSunsetScoutScarf(character, anchor)
	else
		clearCosmetic(character)
	end
end

local function queueApply(player: Player, character: Model)
	local generation = (applyGenerationByPlayer[player] or 0) + 1
	applyGenerationByPlayer[player] = generation
	task.defer(applyEquipped, player, character, generation)
end

local function observePlayer(player: Player)
	local connections: { RBXScriptConnection } = {}
	connectionsByPlayer[player] = connections

	table.insert(
		connections,
		player.CharacterAdded:Connect(function(character)
			queueApply(player, character)
		end)
	)
	table.insert(
		connections,
		player:GetAttributeChangedSignal("ProfileEquippedCosmetic"):Connect(function()
			local character = player.Character
			if character then
				queueApply(player, character)
			end
		end)
	)
	if player.Character then
		queueApply(player, player.Character)
	end
end

function CosmeticService.start()
	assert(not started, "CosmeticService may only be started once")
	started = true
	for _, player in Players:GetPlayers() do
		observePlayer(player)
	end
	Players.PlayerAdded:Connect(observePlayer)
	Players.PlayerRemoving:Connect(function(player)
		applyGenerationByPlayer[player] = nil
		local connections = connectionsByPlayer[player]
		if connections then
			connectionsByPlayer[player] = nil
			for _, connection in connections do
				connection:Disconnect()
			end
		end
	end)
end

return CosmeticService
