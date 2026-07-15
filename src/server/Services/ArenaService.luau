--!strict

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local BotConfig = require(game:GetService("ReplicatedStorage").Shared.Config.BotConfig)
local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)

local ARENA_NAME = "CritterClashArena"
local DEEP_TEAL = Color3.fromRGB(15, 107, 109)
local NIGHT_TEAL = Color3.fromRGB(25, 66, 79)
local DISTANT_TEAL = Color3.fromRGB(49, 103, 105)
local WARM_CORAL = Color3.fromRGB(238, 112, 93)
local CREAM = Color3.fromRGB(255, 232, 190)
local GOLDEN = Color3.fromRGB(246, 196, 71)
local INK = Color3.fromRGB(27, 43, 54)

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

local function makeDecorativePart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = makePart(parent, name, size, cframe.Position, color, material, false)
	part.CFrame = cframe
	part.Shape = shape or Enum.PartType.Block
	return part
end

local function makeBotDecorativePart(
	parent: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local root = parent:FindFirstChild("HumanoidRootPart")
	assert(root and root:IsA("BasePart"), "BotCritter root must exist before its visuals")
	local part = makeDecorativePart(parent, name, size, cframe, color, material, shape)
	part.Anchored = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Name = name .. "Weld"
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function createBackdropLayers(parent: Instance)
	local sun = makeDecorativePart(
		parent,
		"SunDisc",
		Vector3.new(25, 25, 1),
		CFrame.new(58, 51, -13.35),
		GOLDEN,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	sun.Transparency = 0.12

	makeDecorativePart(
		parent,
		"FarHillLeft",
		Vector3.new(118, 48, 1),
		CFrame.new(-58, -2, -13.05),
		NIGHT_TEAL,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	makeDecorativePart(
		parent,
		"FarHillRight",
		Vector3.new(112, 40, 1),
		CFrame.new(63, -1, -12.95),
		DISTANT_TEAL,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)

	for index, cloud in
		{
			{ position = Vector3.new(-51, 49, -12.65), size = Vector3.new(22, 7, 0.7) },
			{ position = Vector3.new(-38, 51, -12.6), size = Vector3.new(15, 9, 0.7) },
			{ position = Vector3.new(20, 59, -12.7), size = Vector3.new(20, 6, 0.7) },
		}
	do
		local cloudPart = makeDecorativePart(
			parent,
			`Cloud_{index}`,
			cloud.size,
			CFrame.new(cloud.position),
			CREAM,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball
		)
		cloudPart.Transparency = 0.18
	end
end

local function createBotDetails(model: Model, rootPosition: Vector3)
	-- A compact original red-squirrel silhouette made only from low-cost primitives.
	-- Decorative pieces never participate in queries or physics; the root remains the
	-- single authoritative hit body.
	makeBotDecorativePart(
		model,
		"TailLower",
		Vector3.new(2.4, 5.4, 2.1),
		CFrame.new(rootPosition + Vector3.new(2.8, 0.6, -0.7)) * CFrame.Angles(0, 0, math.rad(-24)),
		WARM_CORAL,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	makeBotDecorativePart(
		model,
		"TailTip",
		Vector3.new(2.7, 3.8, 2.2),
		CFrame.new(rootPosition + Vector3.new(3.5, 2.8, -0.75)) * CFrame.Angles(0, 0, math.rad(28)),
		GOLDEN,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)

	makeBotDecorativePart(
		model,
		"Head",
		Vector3.new(4.2, 3.8, 3.4),
		CFrame.new(rootPosition + Vector3.new(-0.1, 2.65, 0)),
		WARM_CORAL,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	for _, side in { -1, 1 } do
		makeBotDecorativePart(
			model,
			if side < 0 then "LeftEar" else "RightEar",
			Vector3.new(1.35, 1.8, 1.2),
			CFrame.new(rootPosition + Vector3.new(side * 1.25, 4.55, -0.15))
				* CFrame.Angles(0, 0, math.rad(side * -14)),
			GOLDEN,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball
		)
		makeBotDecorativePart(
			model,
			if side < 0 then "LeftEye" else "RightEye",
			Vector3.new(0.52, 0.7, 0.38),
			CFrame.new(rootPosition + Vector3.new(side * 0.76, 3.05, 1.62)),
			INK,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball
		)
	end

	makeBotDecorativePart(
		model,
		"Muzzle",
		Vector3.new(1.7, 1.25, 0.55),
		CFrame.new(rootPosition + Vector3.new(-0.05, 2.25, 1.62)),
		CREAM,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	makeBotDecorativePart(
		model,
		"Nose",
		Vector3.new(0.55, 0.45, 0.35),
		CFrame.new(rootPosition + Vector3.new(-0.05, 2.4, 1.98)),
		INK,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	makeBotDecorativePart(
		model,
		"BellyPatch",
		Vector3.new(2.7, 3.25, 0.42),
		CFrame.new(rootPosition + Vector3.new(-0.15, -0.15, 1.52)),
		CREAM,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	makeBotDecorativePart(
		model,
		"Scarf",
		Vector3.new(4.15, 0.5, 3.25),
		CFrame.new(rootPosition + Vector3.new(0, 1.45, 0)),
		DEEP_TEAL,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Block
	)

	makeBotDecorativePart(
		model,
		"LauncherBarrel",
		Vector3.new(3.8, 1.05, 1.05),
		CFrame.new(rootPosition + Vector3.new(-2.2, 1.1, 1.05)),
		DEEP_TEAL,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	makeBotDecorativePart(
		model,
		"LauncherMuzzle",
		Vector3.new(0.42, 1.38, 1.38),
		CFrame.new(rootPosition + Vector3.new(-4.05, 1.1, 1.05)),
		GOLDEN,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
end

local function replaceLightingInstance(instance: Instance)
	local existing = Lighting:FindFirstChild(instance.Name)
	if existing then
		existing:Destroy()
	end
	instance.Parent = Lighting
end

local function configureLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(55, 74, 91)
	Lighting.OutdoorAmbient = Color3.fromRGB(90, 105, 120)

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "CritterClashAtmosphere"
	atmosphere.Color = Color3.fromRGB(186, 224, 217)
	atmosphere.Decay = Color3.fromRGB(76, 112, 121)
	atmosphere.Density = 0.18
	atmosphere.Haze = 0.65
	replaceLightingInstance(atmosphere)

	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "CritterClashColorGrade"
	colorCorrection.Brightness = 0.015
	colorCorrection.Contrast = 0.06
	colorCorrection.Saturation = 0.08
	colorCorrection.TintColor = Color3.fromRGB(255, 244, 224)
	replaceLightingInstance(colorCorrection)

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "CritterClashBloom"
	bloom.Intensity = 0.16
	bloom.Size = 18
	bloom.Threshold = 1.6
	replaceLightingInstance(bloom)
end

local function createBotCritter(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = BotConfig.modelName
	model:SetAttribute("CombatUserId", BotConfig.userId)
	model:SetAttribute("IsServerBot", true)

	local root = makePart(
		model,
		"HumanoidRootPart",
		Vector3.new(4, 5, 3),
		Vector3.new(48, 10.5, GameConfig.combatPlaneZ),
		WARM_CORAL,
		Enum.Material.SmoothPlastic,
		true
	)
	root.Shape = Enum.PartType.Ball
	root.Anchored = false
	root.CanCollide = false
	root.CanTouch = false
	root.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.8, 0, 100, 100)
	model.PrimaryPart = root

	-- Humanoids can rewrite HumanoidRootPart collision during state changes. Keep a
	-- separate welded physics hull so the bot always has stable terrain contact.
	local collisionBody = makePart(
		model,
		"CollisionBody",
		root.Size,
		root.Position,
		WARM_CORAL,
		Enum.Material.SmoothPlastic,
		true
	)
	collisionBody.Transparency = 1
	collisionBody.CastShadow = false
	collisionBody.Anchored = false
	collisionBody.Massless = true
	local collisionWeld = Instance.new("WeldConstraint")
	collisionWeld.Name = "CollisionBodyWeld"
	collisionWeld.Part0 = root
	collisionWeld.Part1 = collisionBody
	collisionWeld.Parent = collisionBody
	createBotDetails(model, root.Position)

	local uprightAttachment = Instance.new("Attachment")
	uprightAttachment.Name = "UprightAttachment"
	uprightAttachment.Parent = root
	local upright = Instance.new("AlignOrientation")
	upright.Name = "UprightConstraint"
	upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
	upright.Attachment0 = uprightAttachment
	upright.CFrame = CFrame.identity
	upright.MaxTorque = 1_000_000
	upright.MaxAngularVelocity = 20
	upright.Responsiveness = 40
	upright.Parent = root

	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayName = BotConfig.displayName
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.EvaluateStateMachine = false
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.JumpHeight = 0
	humanoid.Parent = model

	model.Parent = parent
	local canSetNetworkOwnership = root:CanSetNetworkOwnership()
	if canSetNetworkOwnership then
		root:SetNetworkOwner(nil)
	end
	CollectionService:AddTag(model, "Combatant")
	return model
end

function ArenaService.createGreybox(): Model
	local existing = Workspace:FindFirstChild(ARENA_NAME)
	if existing then
		assert(existing:IsA("Model"), ARENA_NAME .. " must be a Model")
		configureLighting()
		return existing
	end

	Workspace.Gravity = GameConfig.projectileWorldGravity
	local arena = Instance.new("Model")
	arena.Name = ARENA_NAME

	-- TerrainService owns the visible terrain projection and authoritative
	-- collision grid. ArenaService keeps only non-destructible scene dressing,
	-- spawns, and the server-owned bot body.
	makePart(
		arena,
		"Backdrop",
		Vector3.new(220, 100, 1),
		Vector3.new(0, 30, -14),
		Color3.fromRGB(39, 73, 89),
		Enum.Material.SmoothPlastic,
		false
	)
	createBackdropLayers(arena)

	createSpawn(arena, "LeftSpawn", -64)
	createSpawn(arena, "RightSpawn", 64)
	createBotCritter(arena)

	arena.Parent = Workspace

	configureLighting()

	return arena
end

function ArenaService.resetBotCritter(arena: Model, enabled: boolean): Model?
	for _, child in arena:GetChildren() do
		if child.Name == BotConfig.modelName or child.Name == "TrainingTarget" then
			child:Destroy()
		end
	end

	if not enabled then
		return nil
	end
	return createBotCritter(arena)
end

return ArenaService
