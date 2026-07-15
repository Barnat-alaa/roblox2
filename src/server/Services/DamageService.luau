--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Damage = require(ReplicatedStorage.Shared.Simulation.Damage)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)

type ProjectileDefinition = Weapons.ProjectileDefinition

export type DamageSource = {
	model: Model,
	player: Player?,
}

export type KnockbackHandler = (model: Model, requestedVelocity: Vector3) -> boolean

local DamageService = {}

local function modelFromPart(part: BasePart): Model?
	local candidate: Instance? = part
	while candidate and candidate ~= Workspace do
		if candidate:IsA("Model") and candidate:FindFirstChildOfClass("Humanoid") then
			return candidate
		end
		candidate = candidate.Parent
	end
	return nil
end

local function rootForModel(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return model.PrimaryPart
end

function DamageService.applyExplosion(
	origin: Vector3,
	definition: ProjectileDefinition,
	source: DamageSource,
	validTargets: { Model },
	applyKnockback: KnockbackHandler
): { [Model]: number }
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {}
	-- Zero is unlimited. A fixed cap can be exhausted by accessories or arena debris
	-- before every nearby combatant appears in the result set.
	overlapParams.MaxParts = 0

	local profile = {
		radius = definition.explosionRadius,
		maxDamage = definition.maxDamage,
		minDamage = definition.minDamage,
	}
	local affected: { [Model]: number } = {}
	local validTargetSet: { [Model]: boolean } = {}
	for _, model in validTargets do
		if model.Parent ~= nil then
			validTargetSet[model] = true
		end
	end

	for _, part in
		Workspace:GetPartBoundsInRadius(origin, definition.explosionRadius, overlapParams)
	do
		local model = modelFromPart(part)
		if not model or not validTargetSet[model] or affected[model] ~= nil then
			continue
		end

		local owningPlayer = Players:GetPlayerFromCharacter(model)
		local belongsToSource = model == source.model
			or (source.player ~= nil and owningPlayer == source.player)
		if belongsToSource and not definition.canDamageOwner then
			continue
		end

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = rootForModel(model)
		if not humanoid or humanoid.Health <= 0 or not root then
			continue
		end

		local distance = (root.Position - origin).Magnitude
		local rawDamage = Damage.atDistance(profile, distance)
		local finalDamage = math.max(0, math.floor(rawDamage + 0.5))
		if finalDamage <= 0 then
			continue
		end

		affected[model] = finalDamage
		humanoid:TakeDamage(finalDamage)

		if not root.Anchored then
			local knockback = Damage.knockbackVector(
				origin,
				root.Position,
				definition.explosionRadius,
				definition.knockbackStrength
			)
			if knockback.Magnitude > 0 then
				local planar = Vector3.new(knockback.X, math.max(knockback.Y, 0) + 8, 0)
				local currentVelocity = root.AssemblyLinearVelocity
				local requestedVelocity = currentVelocity + planar
				applyKnockback(model, requestedVelocity)
			end
		end
	end

	return affected
end

return DamageService
