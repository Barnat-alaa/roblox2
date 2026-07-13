--!strict

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)

local ARENA_NAME = "CritterClashArena"

local ArenaService = {}

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = canCollide
	part.CanQuery = canCollide
	part.CanTouch = canCollide
	part.CastShadow = canCollide
	part.Material = material
	part.Color = color
	part.Size = size
	part.Position = position
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function createSpawn(parent: Instance, name: string, x: number): SpawnLocation
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = name
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.Size = Vector3.new(6, 1, 8)
	spawn.Position = Vector3.new(x, 0.5, GameConfig.combatPlaneZ)
	spawn.Parent = parent
	return spawn
end

local function createTrainingTarget(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "TrainingTarget"

	local root = makePart(
		model,
		"HumanoidRootPart",
		Vector3.new(4, 5, 3),
		Vector3.new(48, 10.5, GameConfig.combatPlaneZ),
		Color3.fromRGB(238, 112, 93),
		Enum.Material.SmoothPlastic,
		true
	)
	root.Shape = Enum.PartType.Ball

	local face = Instance.new("Decal")
	face.Name = "TargetFace"
	face.Face = Enum.NormalId.Front
	face.Texture = ""
	face.Parent = root

	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayName = "Training Critter"
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model

	model.PrimaryPart = root
	model.Parent = parent
	CollectionService:AddTag(model, "Combatant")
	return model
end

function ArenaService.createGreybox(): Model
	local existing = Workspace:FindFirstChild(ARENA_NAME)
	if existing then
		assert(existing:IsA("Model"), ARENA_NAME .. " must be a Model")
		return existing
	end

	Workspace.Gravity = GameConfig.projectileWorldGravity
	local arena = Instance.new("Model")
	arena.Name = ARENA_NAME

	-- TerrainService owns the visible terrain projection and authoritative
	-- collision grid. ArenaService keeps only non-destructible scene dressing,
	-- spawns, and the development target.
	makePart(
		arena,
		"Backdrop",
		Vector3.new(220, 100, 1),
		Vector3.new(0, 30, -14),
		Color3.fromRGB(39, 73, 89),
		Enum.Material.SmoothPlastic,
		false
	)

	createSpawn(arena, "LeftSpawn", -64)
	createSpawn(arena, "RightSpawn", 64)
	createTrainingTarget(arena)

	arena.Parent = Workspace

	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(55, 74, 91)
	Lighting.OutdoorAmbient = Color3.fromRGB(90, 105, 120)

	return arena
end

return ArenaService
