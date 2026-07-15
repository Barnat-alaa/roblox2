--!strict

local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)
local EnvironmentConfig = require(script.Parent.Parent.Config.EnvironmentConfig)
local MatchRules = require(script.Parent.Parent.Simulation.MatchRules)
local ProfileRules = require(script.Parent.ProfileRules)

local RewardRules = {}

export type MatchOutcome = "win" | "loss" | "draw"
export type Completion = "completed" | "abandonment" | "disconnect"

export type MatchRewardContext = {
	matchId: string,
	userId: number,
	outcome: MatchOutcome,
	completion: Completion,
	opponentIsBot: boolean,
	eliminated: boolean,
	legalTurnsCompleted: number,
}

export type RewardAmount = {
	coins: number,
	xp: number,
}

export type ApplyStatus = "Granted" | "Duplicate"
export type ApplyResult = {
	status: ApplyStatus,
	profile: ProfileRules.Profile,
	grant: ProfileRules.ProcessedReward,
}

local MAX_SAFE_INTEGER = 9_007_199_254_740_991
local MAX_LEGAL_TURNS = 10_000

RewardRules.MAX_LEGAL_TURNS = MAX_LEGAL_TURNS

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isIntegerInRange(value: unknown, minimum: number, maximum: number): boolean
	if typeof(value) ~= "number" then
		return false
	end
	local numberValue = value :: number
	return isFinite(numberValue)
		and numberValue == math.floor(numberValue)
		and numberValue >= minimum
		and numberValue <= maximum
end

local function isValidUserId(value: unknown): boolean
	return isIntegerInRange(value, -MAX_SAFE_INTEGER, MAX_SAFE_INTEGER) and value ~= 0
end

local function cloneGrant(grant: ProfileRules.ProcessedReward): ProfileRules.ProcessedReward
	return {
		key = grant.key,
		coins = grant.coins,
		xp = grant.xp,
		time = grant.time,
		outcome = grant.outcome,
		mode = grant.mode,
	}
end

local function validateContext(context: MatchRewardContext): (boolean, string?)
	if not MatchRules.isValidMatchId(context.matchId) then
		return false, "invalid_match_id"
	end
	if not isValidUserId(context.userId) then
		return false, "invalid_user_id"
	end
	if context.outcome ~= "win" and context.outcome ~= "loss" and context.outcome ~= "draw" then
		return false, "invalid_outcome"
	end
	if
		context.completion ~= "completed"
		and context.completion ~= "abandonment"
		and context.completion ~= "disconnect"
	then
		return false, "invalid_completion"
	end
	if typeof(context.opponentIsBot) ~= "boolean" then
		return false, "invalid_opponent_type"
	end
	if typeof(context.eliminated) ~= "boolean" then
		return false, "invalid_eliminated"
	end
	if not isIntegerInRange(context.legalTurnsCompleted, 0, MAX_LEGAL_TURNS) then
		return false, "invalid_legal_turns"
	end
	return true, nil
end

function RewardRules.isEligible(context: MatchRewardContext): (boolean, string?)
	local valid, reason = validateContext(context)
	if not valid then
		return false, reason
	end
	if context.completion == "abandonment" then
		return false, "abandonment"
	end
	if context.completion == "disconnect" then
		return false, "disconnect"
	end
	if
		context.outcome == "win"
		or context.legalTurnsCompleted >= 2
		or (context.eliminated and context.legalTurnsCompleted >= 1)
	then
		return true, nil
	end
	return false, "insufficient_participation"
end

function RewardRules.calculateMatchReward(context: MatchRewardContext): (RewardAmount?, string?)
	local eligible, reason = RewardRules.isEligible(context)
	if not eligible then
		return nil, reason
	end

	local rewards = EconomyConfig.matchRewards
	local coins = rewards.completionCoins
	local xp = rewards.completionXp
	if context.outcome == "win" then
		coins += rewards.winBonusCoins
		xp += rewards.winBonusXp
	elseif context.outcome == "draw" then
		coins += rewards.drawBonusCoins
		xp += rewards.drawBonusXp
	end
	if context.opponentIsBot then
		coins =
			math.floor(coins * rewards.botMultiplierNumerator / rewards.botMultiplierDenominator)
		xp = math.floor(xp * rewards.botMultiplierNumerator / rewards.botMultiplierDenominator)
	end
	return {
		coins = coins,
		xp = xp,
	}, nil
end

function RewardRules.buildGrantId(matchId: string, userId: number): (string?, string?)
	if not MatchRules.isValidMatchId(matchId) then
		return nil, "invalid_match_id"
	end
	if not isValidUserId(userId) then
		return nil, "invalid_user_id"
	end
	local key = string.format("%s|match|%s|user|%d", EnvironmentConfig.name, matchId, userId)
	if #key > ProfileRules.MAX_REWARD_KEY_LENGTH then
		return nil, "grant_id_too_long"
	end
	return key, nil
end

function RewardRules.applyMatchReward(
	profile: ProfileRules.Profile,
	context: MatchRewardContext,
	grantedAt: number
): (ApplyResult?, string?)
	local profileValid, profileReason = ProfileRules.validate(profile)
	if not profileValid then
		return nil, profileReason or "invalid_profile"
	end
	if not isIntegerInRange(grantedAt, 0, MAX_SAFE_INTEGER) then
		return nil, "invalid_grant_time"
	end

	local reward, rewardReason = RewardRules.calculateMatchReward(context)
	if not reward then
		return nil, rewardReason or "ineligible"
	end
	local grantId, grantIdReason = RewardRules.buildGrantId(context.matchId, context.userId)
	if not grantId then
		return nil, grantIdReason or "invalid_grant_id"
	end

	for _, existing in profile.processedRewards do
		if existing.key == grantId then
			return {
				status = "Duplicate",
				profile = ProfileRules.clone(profile),
				grant = cloneGrant(existing),
			},
				nil
		end
	end

	if profile.coins > EconomyConfig.maxCoins - reward.coins then
		return nil, "coins_overflow"
	end
	if profile.xp > EconomyConfig.maxXp - reward.xp then
		return nil, "xp_overflow"
	end
	if profile.stats.matchesPlayed >= EconomyConfig.maxMatchStat then
		return nil, "match_stats_overflow"
	end
	if context.outcome == "win" and profile.stats.wins >= EconomyConfig.maxMatchStat then
		return nil, "match_stats_overflow"
	end
	if context.outcome == "loss" and profile.stats.losses >= EconomyConfig.maxMatchStat then
		return nil, "match_stats_overflow"
	end
	if context.outcome == "draw" and profile.stats.draws >= EconomyConfig.maxMatchStat then
		return nil, "match_stats_overflow"
	end

	local nextProfile = ProfileRules.clone(profile)
	nextProfile.economyVersion = EconomyConfig.version
	nextProfile.coins += reward.coins
	nextProfile.xp += reward.xp
	nextProfile.stats.matchesPlayed += 1
	if context.outcome == "win" then
		nextProfile.stats.wins += 1
	elseif context.outcome == "loss" then
		nextProfile.stats.losses += 1
	else
		nextProfile.stats.draws += 1
	end

	while #nextProfile.processedRewards >= EconomyConfig.maxProcessedRewards do
		table.remove(nextProfile.processedRewards, 1)
	end
	local grant: ProfileRules.ProcessedReward = {
		key = grantId,
		coins = reward.coins,
		xp = reward.xp,
		time = grantedAt,
		outcome = context.outcome,
		mode = if context.opponentIsBot then "bot" else "player",
	}
	table.insert(nextProfile.processedRewards, grant)

	local nextValid, nextReason = ProfileRules.validate(nextProfile)
	if not nextValid then
		return nil, nextReason or "invalid_reward_result"
	end
	return {
		status = "Granted",
		profile = nextProfile,
		grant = cloneGrant(grant),
	}, nil
end

return table.freeze(RewardRules)
