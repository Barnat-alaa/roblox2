--!strict

local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)
local CosmeticRules = require(script.Parent.CosmeticRules)
local SettingsRules = require(script.Parent.SettingsRules)

local ProfileRules = {}

export type RewardOutcome = "win" | "loss" | "draw"
export type RewardMode = "player" | "bot"

export type ProcessedReward = {
	key: string,
	coins: number,
	xp: number,
	time: number,
	outcome: RewardOutcome,
	mode: RewardMode,
}

export type MatchStats = {
	matchesPlayed: number,
	wins: number,
	losses: number,
	draws: number,
}

export type Profile = {
	schemaVersion: number,
	economyVersion: number,
	coins: number,
	xp: number,
	stats: MatchStats,
	processedRewards: { ProcessedReward },
	inventory: CosmeticRules.CosmeticInventory,
	settings: SettingsRules.Settings,
}

export type LegacyProfileV0 = {
	schemaVersion: number,
	coins: number,
	xp: number?,
	experience: number?,
}

export type LegacyProfileV1 = {
	schemaVersion: number,
	economyVersion: number,
	coins: number,
	xp: number,
	stats: MatchStats,
	processedRewards: { ProcessedReward },
}

local CURRENT_SCHEMA_VERSION = 2
local MAX_SAFE_INTEGER = 9_007_199_254_740_991
local MAX_REWARD_KEY_LENGTH = 256

local PROFILE_FIELDS = table.freeze({
	schemaVersion = true,
	economyVersion = true,
	coins = true,
	xp = true,
	stats = true,
	processedRewards = true,
	inventory = true,
	settings = true,
})

local LEGACY_V1_FIELDS = table.freeze({
	schemaVersion = true,
	economyVersion = true,
	coins = true,
	xp = true,
	stats = true,
	processedRewards = true,
})

local STATS_FIELDS = table.freeze({
	matchesPlayed = true,
	wins = true,
	losses = true,
	draws = true,
})

local REWARD_FIELDS = table.freeze({
	key = true,
	coins = true,
	xp = true,
	time = true,
	outcome = true,
	mode = true,
})

local LEGACY_V0_FIELDS = table.freeze({
	schemaVersion = true,
	coins = true,
	xp = true,
	experience = true,
})

ProfileRules.CURRENT_SCHEMA_VERSION = CURRENT_SCHEMA_VERSION
ProfileRules.MAX_COINS = EconomyConfig.maxCoins
ProfileRules.MAX_XP = EconomyConfig.maxXp
ProfileRules.MAX_MATCH_STAT = EconomyConfig.maxMatchStat
ProfileRules.MAX_PROCESSED_REWARDS = EconomyConfig.maxProcessedRewards
ProfileRules.MAX_REWARD_KEY_LENGTH = MAX_REWARD_KEY_LENGTH

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

local function onlyHasFields(
	value: { [any]: any },
	allowedFields: { [string]: boolean }
): (boolean, string?)
	for field in value do
		if typeof(field) ~= "string" or not allowedFields[field :: string] then
			return false, "unexpected_field"
		end
	end
	return true, nil
end

local function isRewardOutcome(value: unknown): boolean
	return value == "win" or value == "loss" or value == "draw"
end

local function isRewardMode(value: unknown): boolean
	return value == "player" or value == "bot"
end

local function validateStats(value: unknown): (boolean, string?)
	if typeof(value) ~= "table" then
		return false, "invalid_stats"
	end
	local stats = value :: { [any]: any }
	local fieldsValid = onlyHasFields(stats, STATS_FIELDS)
	if not fieldsValid then
		return false, "invalid_stats_fields"
	end
	if not isIntegerInRange(stats.matchesPlayed, 0, EconomyConfig.maxMatchStat) then
		return false, "invalid_matches_played"
	end
	if not isIntegerInRange(stats.wins, 0, EconomyConfig.maxMatchStat) then
		return false, "invalid_wins"
	end
	if not isIntegerInRange(stats.losses, 0, EconomyConfig.maxMatchStat) then
		return false, "invalid_losses"
	end
	if not isIntegerInRange(stats.draws, 0, EconomyConfig.maxMatchStat) then
		return false, "invalid_draws"
	end
	if stats.wins + stats.losses + stats.draws ~= stats.matchesPlayed then
		return false, "invalid_stats_total"
	end
	return true, nil
end

local function validateRewardEntry(value: unknown): (boolean, string?)
	if typeof(value) ~= "table" then
		return false, "invalid_reward_entry"
	end
	local entry = value :: { [any]: any }
	local fieldsValid = onlyHasFields(entry, REWARD_FIELDS)
	if not fieldsValid then
		return false, "invalid_reward_fields"
	end
	if
		type(entry.key) ~= "string"
		or #entry.key < 1
		or #entry.key > MAX_REWARD_KEY_LENGTH
		or entry.key:find("[%c%s]") ~= nil
	then
		return false, "invalid_reward_key"
	end
	if not isIntegerInRange(entry.coins, 0, EconomyConfig.maxCoins) then
		return false, "invalid_reward_coins"
	end
	if not isIntegerInRange(entry.xp, 0, EconomyConfig.maxXp) then
		return false, "invalid_reward_xp"
	end
	if not isIntegerInRange(entry.time, 0, MAX_SAFE_INTEGER) then
		return false, "invalid_reward_time"
	end
	if not isRewardOutcome(entry.outcome) then
		return false, "invalid_reward_outcome"
	end
	if not isRewardMode(entry.mode) then
		return false, "invalid_reward_mode"
	end
	return true, nil
end

local function validateRewardLedger(value: unknown): (boolean, string?)
	if typeof(value) ~= "table" then
		return false, "invalid_reward_ledger"
	end
	local ledger = value :: { [any]: any }
	local count = 0
	local maximumIndex = 0
	for index in ledger do
		if
			type(index) ~= "number"
			or index ~= math.floor(index)
			or index < 1
			or index > EconomyConfig.maxProcessedRewards
		then
			return false, "invalid_reward_ledger_index"
		end
		count += 1
		maximumIndex = math.max(maximumIndex, index)
	end
	if count ~= maximumIndex then
		return false, "sparse_reward_ledger"
	end

	local seenKeys: { [string]: boolean } = {}
	for index = 1, maximumIndex do
		local entry = ledger[index]
		local valid, reason = validateRewardEntry(entry)
		if not valid then
			return false, reason
		end
		local key = (entry :: { [any]: any }).key :: string
		if seenKeys[key] then
			return false, "duplicate_reward_key"
		end
		seenKeys[key] = true
	end
	return true, nil
end

local function cloneReward(entry: ProcessedReward): ProcessedReward
	return {
		key = entry.key,
		coins = entry.coins,
		xp = entry.xp,
		time = entry.time,
		outcome = entry.outcome,
		mode = entry.mode,
	}
end

function ProfileRules.createDefault(): Profile
	return {
		schemaVersion = CURRENT_SCHEMA_VERSION,
		economyVersion = EconomyConfig.version,
		coins = 0,
		xp = 0,
		stats = {
			matchesPlayed = 0,
			wins = 0,
			losses = 0,
			draws = 0,
		},
		processedRewards = {},
		inventory = CosmeticRules.createDefault(),
		settings = SettingsRules.createDefault(),
	}
end

function ProfileRules.clone(profile: Profile): Profile
	local rewards = table.create(#profile.processedRewards)
	for index, entry in profile.processedRewards do
		rewards[index] = cloneReward(entry)
	end
	return {
		schemaVersion = profile.schemaVersion,
		economyVersion = profile.economyVersion,
		coins = profile.coins,
		xp = profile.xp,
		stats = {
			matchesPlayed = profile.stats.matchesPlayed,
			wins = profile.stats.wins,
			losses = profile.stats.losses,
			draws = profile.stats.draws,
		},
		processedRewards = rewards,
		inventory = CosmeticRules.clone(profile.inventory),
		settings = SettingsRules.clone(profile.settings),
	}
end

function ProfileRules.validate(value: unknown): (boolean, string?)
	if typeof(value) ~= "table" then
		return false, "invalid_profile"
	end
	local profile = value :: { [any]: any }
	local fieldsValid = onlyHasFields(profile, PROFILE_FIELDS)
	if not fieldsValid then
		return false, "invalid_profile_fields"
	end
	if profile.schemaVersion ~= CURRENT_SCHEMA_VERSION then
		return false, "unsupported_schema"
	end
	if not isIntegerInRange(profile.economyVersion, 1, MAX_SAFE_INTEGER) then
		return false, "invalid_economy_version"
	end
	if not isIntegerInRange(profile.coins, 0, EconomyConfig.maxCoins) then
		return false, "invalid_coins"
	end
	if not isIntegerInRange(profile.xp, 0, EconomyConfig.maxXp) then
		return false, "invalid_xp"
	end
	local statsValid, statsReason = validateStats(profile.stats)
	if not statsValid then
		return false, statsReason
	end
	local ledgerValid, ledgerReason = validateRewardLedger(profile.processedRewards)
	if not ledgerValid then
		return false, ledgerReason
	end
	local inventoryValid, inventoryReason = CosmeticRules.validate(profile.inventory)
	if not inventoryValid then
		return false, inventoryReason
	end
	local settingsValid, settingsReason = SettingsRules.validate(profile.settings)
	if not settingsValid then
		return false, settingsReason
	end
	return true, nil
end

local function migrateLegacyV0(value: { [any]: any }): (Profile?, string?)
	local fieldsValid = onlyHasFields(value, LEGACY_V0_FIELDS)
	if not fieldsValid then
		return nil, "invalid_legacy_fields"
	end
	if not isIntegerInRange(value.coins, 0, EconomyConfig.maxCoins) then
		return nil, "invalid_legacy_coins"
	end

	local hasXp = value.xp ~= nil
	local hasExperience = value.experience ~= nil
	if hasXp == hasExperience then
		return nil, "ambiguous_legacy_xp"
	end
	local xp = if hasXp then value.xp else value.experience
	if not isIntegerInRange(xp, 0, EconomyConfig.maxXp) then
		return nil, "invalid_legacy_xp"
	end

	local migrated = ProfileRules.createDefault()
	migrated.coins = value.coins :: number
	migrated.xp = xp :: number
	return migrated, nil
end

local function migrateLegacyV1(value: { [any]: any }): (Profile?, string?)
	local fieldsValid = onlyHasFields(value, LEGACY_V1_FIELDS)
	if not fieldsValid then
		return nil, "invalid_legacy_v1_fields"
	end
	if not isIntegerInRange(value.economyVersion, 1, MAX_SAFE_INTEGER) then
		return nil, "invalid_economy_version"
	end
	if not isIntegerInRange(value.coins, 0, EconomyConfig.maxCoins) then
		return nil, "invalid_coins"
	end
	if not isIntegerInRange(value.xp, 0, EconomyConfig.maxXp) then
		return nil, "invalid_xp"
	end
	local statsValid, statsReason = validateStats(value.stats)
	if not statsValid then
		return nil, statsReason
	end
	local ledgerValid, ledgerReason = validateRewardLedger(value.processedRewards)
	if not ledgerValid then
		return nil, ledgerReason
	end

	local migrated = ProfileRules.createDefault()
	migrated.economyVersion = value.economyVersion :: number
	migrated.coins = value.coins :: number
	migrated.xp = value.xp :: number
	local stats = value.stats :: MatchStats
	migrated.stats = {
		matchesPlayed = stats.matchesPlayed,
		wins = stats.wins,
		losses = stats.losses,
		draws = stats.draws,
	}
	for _, entry in value.processedRewards :: { ProcessedReward } do
		table.insert(migrated.processedRewards, cloneReward(entry))
	end
	return migrated, nil
end

function ProfileRules.migrate(value: unknown): (Profile?, string?)
	if value == nil then
		return ProfileRules.createDefault(), nil
	end
	if typeof(value) ~= "table" then
		return nil, "invalid_profile"
	end
	local raw = value :: { [any]: any }
	if raw.schemaVersion == CURRENT_SCHEMA_VERSION then
		local valid, reason = ProfileRules.validate(raw)
		if not valid then
			return nil, reason
		end
		return ProfileRules.clone(raw :: any), nil
	end
	if raw.schemaVersion == 0 then
		return migrateLegacyV0(raw)
	end
	if raw.schemaVersion == 1 then
		return migrateLegacyV1(raw)
	end
	if type(raw.schemaVersion) == "number" and raw.schemaVersion > CURRENT_SCHEMA_VERSION then
		return nil, "future_schema"
	end
	return nil, "unsupported_schema"
end

function ProfileRules.xpRequiredForNextLevel(level: number): number?
	assert(
		isIntegerInRange(level, 1, EconomyConfig.levelCap),
		"level must be an integer inside the configured level range"
	)
	if level >= EconomyConfig.levelCap then
		return nil
	end
	return EconomyConfig.levelBaseXp + EconomyConfig.levelXpStep * (level - 1)
end

function ProfileRules.totalXpRequiredForLevel(level: number): number
	assert(
		isIntegerInRange(level, 1, EconomyConfig.levelCap),
		"level must be an integer inside the configured level range"
	)
	local completedLevels = level - 1
	return completedLevels * EconomyConfig.levelBaseXp
		+ EconomyConfig.levelXpStep * completedLevels * (completedLevels - 1) / 2
end

function ProfileRules.levelFromXp(xp: number): number
	assert(
		isIntegerInRange(xp, 0, EconomyConfig.maxXp),
		"xp must be a non-negative bounded integer"
	)
	local level = 1
	local remainingXp = xp
	while level < EconomyConfig.levelCap do
		local required = ProfileRules.xpRequiredForNextLevel(level)
		assert(required ~= nil, "uncapped level must have a next-level requirement")
		if remainingXp < required then
			break
		end
		remainingXp -= required
		level += 1
	end
	return level
end

return table.freeze(ProfileRules)
