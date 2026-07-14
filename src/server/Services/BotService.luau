--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BotConfig = require(ReplicatedStorage.Shared.Config.BotConfig)
local BotAim = require(ReplicatedStorage.Shared.Simulation.BotAim)

local MatchService = require(script.Parent.MatchService)
local ProjectileService = require(script.Parent.ProjectileService)

local BotService = {}

local started = false
local shotAttemptCount = 0
local acceptedShotCount = 0

local function rootPosition(model: Model): Vector3?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function updateDiagnostics()
	Workspace:SetAttribute("CritterClashBotShotAttemptCount", shotAttemptCount)
	Workspace:SetAttribute("CritterClashBotAcceptedShotCount", acceptedShotCount)
end

local function handleTurn(context: MatchService.BotTurnContext)
	task.delay(BotConfig.thinkDelaySeconds, function()
		if Workspace:GetServerTimeNow() >= context.deadline then
			return
		end

		local originPosition = rootPosition(context.model)
		local targetCharacter = context.targetPlayer.Character
		local targetPosition = if targetCharacter then rootPosition(targetCharacter) else nil
		if not originPosition or not targetPosition then
			return
		end

		local solveStartedAt = os.clock()
		debug.profilebegin("CritterClash.BotAimSolve")
		local solved, solutionOrError = pcall(BotAim.solve, {
			origin = Vector3.new(originPosition.X, originPosition.Y + 2.4, 0),
			target = Vector3.new(targetPosition.X, targetPosition.Y + 1, 0),
			wind = context.wind,
			seed = context.seed,
			turnIndex = context.roundNumber,
			difficulty = BotConfig.difficulty :: BotAim.Difficulty,
			weaponIds = BotConfig.weaponIds,
		})
		debug.profileend()
		Workspace:SetAttribute(
			"CritterClashBotLastSolveMilliseconds",
			(os.clock() - solveStartedAt) * 1_000
		)
		if not solved then
			warn(string.format("[CritterClash] Bot aim failed: %s", tostring(solutionOrError)))
			return
		end
		local solution = solutionOrError :: BotAim.Solution

		shotAttemptCount += 1
		Workspace:SetAttribute("CritterClashBotLastWeaponId", solution.weaponId)
		Workspace:SetAttribute("CritterClashBotLastAngle", solution.angle)
		Workspace:SetAttribute("CritterClashBotLastPower", solution.power)
		Workspace:SetAttribute("CritterClashBotLastPredictedMiss", solution.missDistance)
		Workspace:SetAttribute("CritterClashBotLastPredictedImpactX", solution.predictedImpact.X)
		Workspace:SetAttribute("CritterClashBotLastPredictedImpactY", solution.predictedImpact.Y)
		Workspace:SetAttribute("CritterClashBotLastCandidateCount", solution.evaluatedCandidates)
		updateDiagnostics()

		local accepted, reason = ProjectileService.fireBot(
			context.userId,
			context.matchId,
			context.turnToken,
			context.model,
			{
				weaponId = solution.weaponId,
				angle = solution.angle,
				power = solution.power,
			}
		)
		if accepted then
			acceptedShotCount += 1
			updateDiagnostics()
		else
			warn(string.format("[CritterClash] Bot shot rejected: %s", reason or "unknown"))
		end
	end)
end

function BotService.start()
	assert(not started, "BotService may only be started once")
	started = true
	shotAttemptCount = 0
	acceptedShotCount = 0
	updateDiagnostics()
	MatchService.setBotTurnHandler(handleTurn)
end

return BotService
