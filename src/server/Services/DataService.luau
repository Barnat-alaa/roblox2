--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EnvironmentConfig = require(ReplicatedStorage.Shared.Config.EnvironmentConfig)
local ProfileRules = require(ReplicatedStorage.Shared.Progression.ProfileRules)
local RewardRules = require(ReplicatedStorage.Shared.Progression.RewardRules)
local SessionRules = require(ReplicatedStorage.Shared.Progression.SessionRules)

type Profile = ProfileRules.Profile
type Lease = SessionRules.Lease
type MatchRewardContext = RewardRules.MatchRewardContext

export type ProfileStatus = "Loading" | "Ready" | "ReadOnly" | "Unavailable" | "Released"
export type ProfileStorage = "Persistent" | "SessionMemory" | "ReadOnly" | "Unavailable"
export type EnqueueStatus = "Accepted" | "ReadOnly" | "Unavailable"
export type RewardRequest = {
	matchId: string,
	userId: number,
	outcome: RewardRules.MatchOutcome,
	completion: RewardRules.Completion,
	opponentIsBot: boolean,
	eliminated: boolean,
	legalTurnsCompleted: number,
	grantedAt: number,
}
export type RewardResultStatus = "Granted" | "Duplicate" | "ReadOnly" | "Unavailable"
export type RewardStatus = RewardResultStatus
export type RewardResult = {
	status: RewardResultStatus,
	coins: number,
	experience: number,
}
export type RewardCallback = (result: RewardResult) -> ()

type StoredProfile = {
	formatVersion: number,
	profile: Profile,
	session: Lease?,
}

type StorageBackend = "DataStore" | "SessionMemory"

type LoadItem = { kind: "Load" }
type RewardItem = {
	kind: "Reward",
	request: RewardRequest,
	context: MatchRewardContext,
	callback: RewardCallback,
}
type RenewItem = { kind: "Renew" }
type ReleaseItem = { kind: "Release" }
type QueueItem = LoadItem | RewardItem | RenewItem | ReleaseItem

type ProfileRecord = {
	player: Player,
	key: string,
	storage: StorageBackend,
	status: ProfileStatus,
	profile: Profile?,
	session: Lease?,
	queue: { QueueItem },
	queueHead: number,
	laneActive: boolean,
	workerRunning: boolean,
	acceptingRewards: boolean,
	releaseQueued: boolean,
	renewQueued: boolean,
}

type DecodeKind = "Empty" | "Safe" | "Future" | "Corrupt"
type PersistenceResultKind =
	"Ready"
	| "Locked"
	| "Future"
	| "Corrupt"
	| "Failed"
	| "Rejected"
	| "Lost"
type PersistenceResult = {
	kind: PersistenceResultKind,
	value: StoredProfile?,
	reason: string?,
}
type RewardPersistenceResult = {
	kind: PersistenceResultKind,
	value: StoredProfile?,
	rewardStatus: RewardRules.ApplyStatus?,
	grant: ProfileRules.ProcessedReward?,
	reason: string?,
}

local FORMAT_VERSION = 1
local MAX_SAFE_INTEGER = 9_007_199_254_740_991
local DIAGNOSTIC_LIMIT = 1_000_000_000
local BUDGET_POLL_SECONDS = 0.2

-- Keep environment reads centralized. This makes a reviewed Development ->
-- Staging/Production configuration swap obvious and prevents accidental stores.
local DATA_STORE_NAME: string = EnvironmentConfig.dataStoreName
local PROFILE_KEY_PREFIX: string = EnvironmentConfig.profileKeyPrefix
local LEASE_DURATION_SECONDS: number = EnvironmentConfig.leaseDurationSeconds
local AUTOSAVE_INTERVAL_SECONDS: number = EnvironmentConfig.autosaveIntervalSeconds
local AUTOSAVE_JITTER_SECONDS: number = EnvironmentConfig.autosaveJitterSeconds
local RETRY_ATTEMPTS: number = EnvironmentConfig.retryAttempts
local RETRY_BASE_DELAY_SECONDS: number = EnvironmentConfig.retryBaseDelaySeconds
local RETRY_MAX_DELAY_SECONDS: number = EnvironmentConfig.retryMaxDelaySeconds
local SHUTDOWN_TIMEOUT_SECONDS: number = EnvironmentConfig.shutdownTimeoutSeconds
local ALLOW_UNPUBLISHED_STUDIO_MEMORY: boolean = EnvironmentConfig.allowUnpublishedStudioMemory

local ownerPrefix = if game.JobId ~= "" then game.JobId else "studio"
local SERVER_OWNER_ID = ownerPrefix .. "-" .. HttpService:GenerateGUID(false)
local ownerValid, ownerReason = SessionRules.validateOwnerId(SERVER_OWNER_ID)
assert(ownerValid, ownerReason or "generated profile owner ID is invalid")
assert(
	EnvironmentConfig.schemaVersion == ProfileRules.CURRENT_SCHEMA_VERSION,
	"environment and profile schema versions must match"
)

local DataService = {}

local records: { [Player]: ProfileRecord } = {}
local activeRecordByKey: { [string]: ProfileRecord } = {}
local pendingRecordsByKey: { [string]: { ProfileRecord } } = {}
local sessionMemory: { [string]: StoredProfile } = {}
local nativeStore: DataStore? = nil
local started = false
local shuttingDown = false
local shutdownDeadline: number? = nil
local random = Random.new()

local rewardsGranted = 0
local rewardsDuplicate = 0
local storageFailures = 0

local ENVELOPE_FIELDS: { [string]: boolean } = table.freeze({
	formatVersion = true,
	profile = true,
	session = true,
})

local function saturatingIncrement(value: number): number
	return math.min(DIAGNOSTIC_LIMIT, value + 1)
end

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isSafeInteger(value: unknown, minimum: number, maximum: number): boolean
	if typeof(value) ~= "number" then
		return false
	end
	local numberValue = value :: number
	return isFinite(numberValue)
		and numberValue == math.floor(numberValue)
		and numberValue >= minimum
		and numberValue <= maximum
end

local function cloneLease(lease: Lease): Lease
	return {
		ownerId = lease.ownerId,
		acquiredAt = lease.acquiredAt,
		expiresAt = lease.expiresAt,
	}
end

local function cloneStored(value: StoredProfile): StoredProfile
	return {
		formatVersion = FORMAT_VERSION,
		profile = ProfileRules.clone(value.profile),
		session = if value.session then cloneLease(value.session) else nil,
	}
end

local function encodeStored(value: StoredProfile): { [string]: any }
	local encoded: { [string]: any } = {
		formatVersion = FORMAT_VERSION,
		profile = ProfileRules.clone(value.profile),
	}
	if value.session then
		encoded.session = cloneLease(value.session)
	end
	return encoded
end

local function classifyProfileFailure(reason: string?): DecodeKind
	if reason == "future_schema" then
		return "Future"
	end
	return "Corrupt"
end

local function decodeStored(value: unknown): (StoredProfile?, DecodeKind, string?)
	if value == nil then
		return nil, "Empty", nil
	end
	if typeof(value) ~= "table" then
		return nil, "Corrupt", "invalid_envelope"
	end

	local raw = value :: { [any]: any }
	if raw.formatVersion == nil then
		-- The only accepted legacy representation is a profile that the shared,
		-- pure migration rules understand. Unknown tables are never overwritten.
		local migrated, reason = ProfileRules.migrate(value)
		if not migrated then
			return nil, classifyProfileFailure(reason), reason
		end
		return {
			formatVersion = FORMAT_VERSION,
			profile = migrated,
			session = nil,
		},
			"Safe",
			nil
	end

	if isSafeInteger(raw.formatVersion, FORMAT_VERSION + 1, MAX_SAFE_INTEGER) then
		return nil, "Future", "future_envelope"
	end
	if raw.formatVersion ~= FORMAT_VERSION then
		return nil, "Corrupt", "invalid_envelope_version"
	end
	for field in raw do
		if typeof(field) ~= "string" or not ENVELOPE_FIELDS[field :: string] then
			return nil, "Corrupt", "invalid_envelope_fields"
		end
	end
	if raw.profile == nil then
		return nil, "Corrupt", "missing_profile"
	end

	local profile, profileReason = ProfileRules.migrate(raw.profile)
	if not profile then
		return nil, classifyProfileFailure(profileReason), profileReason
	end

	local session: Lease? = nil
	if raw.session ~= nil then
		local sessionValid, sessionReason = SessionRules.validateLease(raw.session)
		if not sessionValid then
			return nil, "Corrupt", sessionReason or "invalid_session"
		end
		session = cloneLease((raw.session :: any) :: Lease)
	end
	return {
		formatVersion = FORMAT_VERSION,
		profile = profile,
		session = session,
	},
		"Safe",
		nil
end

local function setDiagnostics()
	local readyCount = 0
	local readOnlyCount = 0
	local unavailableCount = 0
	local loadingCount = 0
	local queueDepth = 0
	local recordCount = 0
	for _, record in records do
		recordCount += 1
		if record.status == "Ready" then
			readyCount += 1
		elseif record.status == "ReadOnly" then
			readOnlyCount += 1
		elseif record.status == "Unavailable" then
			unavailableCount += 1
		elseif record.status == "Loading" then
			loadingCount += 1
		end
		queueDepth += math.max(0, #record.queue - record.queueHead + 1)
	end

	Workspace:SetAttribute("CritterClashProfileEnvironment", EnvironmentConfig.name)
	Workspace:SetAttribute("CritterClashProfileRecords", math.min(DIAGNOSTIC_LIMIT, recordCount))
	Workspace:SetAttribute("CritterClashProfileLoading", math.min(DIAGNOSTIC_LIMIT, loadingCount))
	Workspace:SetAttribute("CritterClashProfileReady", math.min(DIAGNOSTIC_LIMIT, readyCount))
	Workspace:SetAttribute("CritterClashProfileReadOnly", math.min(DIAGNOSTIC_LIMIT, readOnlyCount))
	Workspace:SetAttribute(
		"CritterClashProfileUnavailable",
		math.min(DIAGNOSTIC_LIMIT, unavailableCount)
	)
	Workspace:SetAttribute("CritterClashProfileQueueDepth", math.min(DIAGNOSTIC_LIMIT, queueDepth))
	Workspace:SetAttribute("CritterClashProfileRewardsGranted", rewardsGranted)
	Workspace:SetAttribute("CritterClashProfileRewardsDuplicate", rewardsDuplicate)
	Workspace:SetAttribute("CritterClashProfileStorageFailures", storageFailures)
end

local function profileProgress(profile: Profile?): (number, number, number, number, number)
	if not profile then
		return 0, 0, 1, 0, ProfileRules.xpRequiredForNextLevel(1) or 0
	end
	local level = ProfileRules.levelFromXp(profile.xp)
	local levelStartXp = ProfileRules.totalXpRequiredForLevel(level)
	local requiredForNextLevel = ProfileRules.xpRequiredForNextLevel(level)
	local xpIntoLevel = if requiredForNextLevel then math.max(0, profile.xp - levelStartXp) else 0
	local xpForNextLevel = requiredForNextLevel or 0
	return profile.coins, profile.xp, level, xpIntoLevel, xpForNextLevel
end

local function publishRecord(record: ProfileRecord)
	if record.player.Parent ~= Players then
		return
	end
	local coins, experience, level, xpIntoLevel, xpForNextLevel = profileProgress(record.profile)
	local player = record.player
	local publishedStorage: ProfileStorage = if record.status == "ReadOnly"
		then "ReadOnly"
		elseif record.status == "Unavailable" or record.status == "Released" then "Unavailable"
		elseif record.storage == "SessionMemory" then "SessionMemory"
		else "Persistent"
	player:SetAttribute("ProfileStorage", publishedStorage)
	player:SetAttribute("ProfileCoins", coins)
	player:SetAttribute("ProfileExperience", experience)
	player:SetAttribute("ProfileLevel", level)
	player:SetAttribute("ProfileXPIntoLevel", xpIntoLevel)
	player:SetAttribute("ProfileXPForNextLevel", xpForNextLevel)
	-- Status is the commit marker observed by the client controller.
	player:SetAttribute("ProfileStatus", record.status)
end

local function setStatus(record: ProfileRecord, status: ProfileStatus)
	record.status = status
	publishRecord(record)
	setDiagnostics()
end

local function rewardResult(
	status: RewardResultStatus,
	coins: number,
	experience: number
): RewardResult
	return table.freeze({
		status = status,
		coins = coins,
		experience = experience,
	}) :: RewardResult
end

local function deferCallback(callback: RewardCallback, result: RewardResult)
	task.defer(function()
		local ok, callbackError = pcall(function(): boolean
			callback(result)
			return true
		end)
		if not ok then
			warn(
				string.format(
					"[CritterClash] profile reward callback failed: %s",
					tostring(callbackError)
				)
			)
		end
	end)
end

local function cloneAndValidateRequest(
	player: Player,
	value: unknown
): (RewardRequest?, MatchRewardContext?)
	if typeof(value) ~= "table" then
		return nil, nil
	end
	local raw = value :: { [any]: any }
	if raw.userId ~= player.UserId then
		return nil, nil
	end
	if not isSafeInteger(raw.grantedAt, 0, MAX_SAFE_INTEGER) then
		return nil, nil
	end

	local context: MatchRewardContext = {
		matchId = raw.matchId,
		userId = raw.userId,
		outcome = raw.outcome,
		completion = raw.completion,
		opponentIsBot = raw.opponentIsBot,
		eliminated = raw.eliminated,
		legalTurnsCompleted = raw.legalTurnsCompleted,
	}
	local eligible = RewardRules.isEligible(context)
	if not eligible then
		return nil, nil
	end

	local request: RewardRequest = {
		matchId = context.matchId,
		userId = context.userId,
		outcome = context.outcome,
		completion = context.completion,
		opponentIsBot = context.opponentIsBot,
		eliminated = context.eliminated,
		legalTurnsCompleted = context.legalTurnsCompleted,
		grantedAt = raw.grantedAt,
	}
	return table.freeze(request) :: RewardRequest, table.freeze(context) :: MatchRewardContext
end

local function currentRequestDeadline(): number?
	return shutdownDeadline
end

local function waitAtMost(seconds: number): boolean
	local deadline = currentRequestDeadline()
	if deadline then
		local remaining = deadline - os.clock()
		if remaining <= 0 then
			return false
		end
		task.wait(math.min(seconds, remaining))
		return os.clock() < deadline
	end
	task.wait(seconds)
	return true
end

local function waitForBudget(requestType: Enum.DataStoreRequestType): boolean
	local localDeadline = os.clock() + RETRY_MAX_DELAY_SECONDS
	local closeDeadline = currentRequestDeadline()
	if closeDeadline then
		localDeadline = math.min(localDeadline, closeDeadline)
	end

	repeat
		local budgetOk, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(requestType)
		end)
		-- Budget inspection is advisory. If Roblox rejects the inspection itself,
		-- the protected request below remains the authoritative result.
		if not budgetOk or (budget :: number) > 0 then
			return true
		end
		local remaining = localDeadline - os.clock()
		if remaining <= 0 then
			return false
		end
		task.wait(math.min(BUDGET_POLL_SECONDS, remaining))
	until os.clock() >= localDeadline
	return false
end

local function runDataStoreRequest(
	requestType: Enum.DataStoreRequestType,
	operation: () -> any
): (boolean, any, string?)
	local lastError = "request_failed"
	for attempt = 1, RETRY_ATTEMPTS do
		local deadline = currentRequestDeadline()
		if deadline and os.clock() >= deadline then
			return false, nil, "shutdown_deadline"
		end
		if waitForBudget(requestType) then
			local ok, result = pcall(operation)
			if ok then
				return true, result, nil
			end
			lastError = tostring(result)
		else
			lastError = "request_budget_timeout"
		end

		storageFailures = saturatingIncrement(storageFailures)
		setDiagnostics()
		if attempt < RETRY_ATTEMPTS then
			local exponential = RETRY_BASE_DELAY_SECONDS * 2 ^ (attempt - 1)
			local backoff = math.min(RETRY_MAX_DELAY_SECONDS, exponential)
			backoff *= random:NextNumber(0.85, 1.15)
			if not waitAtMost(backoff) then
				break
			end
		end
	end
	return false, nil, lastError
end

local function getNativeStore(): DataStore?
	if nativeStore then
		return nativeStore
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATA_STORE_NAME)
	end)
	if not ok then
		storageFailures = saturatingIncrement(storageFailures)
		setDiagnostics()
		return nil
	end
	nativeStore = result :: DataStore
	return nativeStore
end

local function currentUnixTime(): number
	return os.time()
end

local function acquireInSessionMemory(key: string): PersistenceResult
	local current = sessionMemory[key]
	local stored: StoredProfile
	if current then
		stored = cloneStored(current)
	else
		local profile, reason = ProfileRules.migrate(nil)
		if not profile then
			return { kind = "Corrupt", reason = reason or "default_profile_failed" }
		end
		stored = {
			formatVersion = FORMAT_VERSION,
			profile = profile,
			session = nil,
		}
	end

	local acquisition, reason = SessionRules.acquire(
		stored.session,
		SERVER_OWNER_ID,
		currentUnixTime(),
		LEASE_DURATION_SECONDS
	)
	if not acquisition then
		return { kind = "Corrupt", value = stored, reason = reason or "lease_failed" }
	end
	if acquisition.status == "Locked" then
		return { kind = "Locked", value = stored, reason = "session_locked" }
	end
	stored.session = cloneLease(acquisition.lease)
	sessionMemory[key] = cloneStored(stored)
	return { kind = "Ready", value = cloneStored(stored) }
end

local function acquireInDataStore(key: string): PersistenceResult
	local store = getNativeStore()
	if not store then
		return { kind = "Failed", reason = "data_store_unavailable" }
	end

	local disposition: PersistenceResultKind = "Failed"
	local observed: StoredProfile? = nil
	local dispositionReason: string? = nil
	local ok, updatedValue, requestError = runDataStoreRequest(
		Enum.DataStoreRequestType.UpdateAsync,
		function()
			return store:UpdateAsync(key, function(currentValue: any)
				local decoded, decodeKind, decodeReason = decodeStored(currentValue)
				local stored: StoredProfile
				if decodeKind == "Empty" then
					local profile, migrationReason = ProfileRules.migrate(nil)
					if not profile then
						disposition = "Corrupt"
						dispositionReason = migrationReason or "default_profile_failed"
						return nil
					end
					stored = {
						formatVersion = FORMAT_VERSION,
						profile = profile,
						session = nil,
					}
				elseif decodeKind == "Safe" and decoded then
					stored = decoded
					observed = cloneStored(decoded)
				else
					disposition = if decodeKind == "Future" then "Future" else "Corrupt"
					dispositionReason = decodeReason
					return nil
				end

				local acquisition, acquisitionReason = SessionRules.acquire(
					stored.session,
					SERVER_OWNER_ID,
					currentUnixTime(),
					LEASE_DURATION_SECONDS
				)
				if not acquisition then
					disposition = "Corrupt"
					dispositionReason = acquisitionReason or "lease_failed"
					return nil
				end
				if acquisition.status == "Locked" then
					disposition = "Locked"
					dispositionReason = "session_locked"
					return nil
				end

				local nextStored: StoredProfile = {
					formatVersion = FORMAT_VERSION,
					profile = ProfileRules.clone(stored.profile),
					session = cloneLease(acquisition.lease),
				}
				disposition = "Ready"
				observed = cloneStored(nextStored)
				dispositionReason = nil
				return encodeStored(nextStored)
			end)
		end
	)
	if not ok then
		return { kind = "Failed", value = observed, reason = requestError }
	end
	if disposition ~= "Ready" then
		return { kind = disposition, value = observed, reason = dispositionReason }
	end

	local decoded, decodeKind, decodeReason = decodeStored(updatedValue)
	if decodeKind ~= "Safe" or not decoded then
		return {
			kind = if decodeKind == "Future" then "Future" else "Corrupt",
			reason = decodeReason or "invalid_update_result",
		}
	end
	return { kind = "Ready", value = decoded }
end

local function readDataStore(key: string): PersistenceResult
	local store = getNativeStore()
	if not store then
		return { kind = "Failed", reason = "data_store_unavailable" }
	end
	local options = Instance.new("DataStoreGetOptions")
	options.UseCache = false
	local ok, value, requestError = runDataStoreRequest(
		Enum.DataStoreRequestType.GetAsync,
		function()
			return store:GetAsync(key, options)
		end
	)
	options:Destroy()
	if not ok then
		return { kind = "Failed", reason = requestError }
	end
	local decoded, decodeKind, decodeReason = decodeStored(value)
	if decodeKind == "Safe" and decoded then
		return { kind = "Ready", value = decoded }
	end
	if decodeKind == "Empty" then
		return { kind = "Failed", reason = "profile_missing" }
	end
	return {
		kind = if decodeKind == "Future" then "Future" else "Corrupt",
		reason = decodeReason,
	}
end

local function applyLoadResult(record: ProfileRecord, acquisition: PersistenceResult)
	if acquisition.kind == "Ready" and acquisition.value then
		record.profile = ProfileRules.clone(acquisition.value.profile)
		record.session = if acquisition.value.session
			then cloneLease(acquisition.value.session)
			else nil
		setStatus(record, "Ready")
		return
	end

	if record.storage == "SessionMemory" then
		if acquisition.kind == "Locked" and acquisition.value then
			record.profile = ProfileRules.clone(acquisition.value.profile)
			record.session = nil
			setStatus(record, "ReadOnly")
		else
			record.profile = nil
			record.session = nil
			setStatus(record, "Unavailable")
		end
		return
	end

	if acquisition.kind == "Locked" and acquisition.value then
		record.profile = ProfileRules.clone(acquisition.value.profile)
		record.session = nil
		setStatus(record, "ReadOnly")
		return
	end
	if acquisition.kind == "Future" or acquisition.kind == "Corrupt" then
		record.profile = nil
		record.session = nil
		setStatus(record, "Unavailable")
		return
	end

	-- A failed write never falls back to a default. GetAsync may prove that the
	-- ambiguous UpdateAsync actually acquired this server's lease; otherwise a
	-- validated snapshot is exposed read-only.
	local fallback = readDataStore(record.key)
	if fallback.kind == "Ready" and fallback.value then
		record.profile = ProfileRules.clone(fallback.value.profile)
		local session = fallback.value.session
		if session and SessionRules.isActiveOwner(session, SERVER_OWNER_ID, currentUnixTime()) then
			record.session = cloneLease(session)
			setStatus(record, "Ready")
		else
			record.session = nil
			setStatus(record, "ReadOnly")
		end
	else
		record.profile = nil
		record.session = nil
		setStatus(record, "Unavailable")
	end
end

local function loadRecord(record: ProfileRecord)
	local result = if record.storage == "SessionMemory"
		then acquireInSessionMemory(record.key)
		else acquireInDataStore(record.key)
	applyLoadResult(record, result)
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

local function findGrant(profile: Profile, grantId: string): ProfileRules.ProcessedReward?
	for _, grant in profile.processedRewards do
		if grant.key == grantId then
			return cloneGrant(grant)
		end
	end
	return nil
end

local function applyRewardInSessionMemory(
	item: RewardItem,
	record: ProfileRecord
): RewardPersistenceResult
	local current = sessionMemory[record.key]
	if not current then
		return { kind = "Corrupt", reason = "profile_missing_during_reward" }
	end
	local stored = cloneStored(current)
	local acquisition, acquisitionReason = SessionRules.acquire(
		stored.session,
		SERVER_OWNER_ID,
		currentUnixTime(),
		LEASE_DURATION_SECONDS
	)
	if not acquisition then
		return { kind = "Corrupt", value = stored, reason = acquisitionReason }
	end
	if acquisition.status == "Locked" then
		return { kind = "Locked", value = stored, reason = "session_locked" }
	end

	local applied, applyReason =
		RewardRules.applyMatchReward(stored.profile, item.context, item.request.grantedAt)
	if not applied then
		return { kind = "Rejected", value = stored, reason = applyReason }
	end
	local nextStored: StoredProfile = {
		formatVersion = FORMAT_VERSION,
		profile = applied.profile,
		session = cloneLease(acquisition.lease),
	}
	sessionMemory[record.key] = cloneStored(nextStored)
	return {
		kind = "Ready",
		value = cloneStored(nextStored),
		rewardStatus = applied.status,
		grant = cloneGrant(applied.grant),
	}
end

local function applyRewardInDataStore(
	item: RewardItem,
	record: ProfileRecord
): RewardPersistenceResult
	local store = getNativeStore()
	if not store then
		return { kind = "Failed", reason = "data_store_unavailable" }
	end

	local disposition: PersistenceResultKind = "Failed"
	local observed: StoredProfile? = nil
	local appliedStatus: RewardRules.ApplyStatus? = nil
	local appliedGrant: ProfileRules.ProcessedReward? = nil
	local dispositionReason: string? = nil
	local ok, updatedValue, requestError = runDataStoreRequest(
		Enum.DataStoreRequestType.UpdateAsync,
		function()
			return store:UpdateAsync(record.key, function(currentValue: any)
				local decoded, decodeKind, decodeReason = decodeStored(currentValue)
				if decodeKind ~= "Safe" or not decoded then
					disposition = if decodeKind == "Future" then "Future" else "Corrupt"
					dispositionReason = decodeReason or "profile_missing_during_reward"
					return nil
				end
				observed = cloneStored(decoded)

				local acquisition, acquisitionReason = SessionRules.acquire(
					decoded.session,
					SERVER_OWNER_ID,
					currentUnixTime(),
					LEASE_DURATION_SECONDS
				)
				if not acquisition then
					disposition = "Corrupt"
					dispositionReason = acquisitionReason or "lease_failed"
					return nil
				end
				if acquisition.status == "Locked" then
					disposition = "Locked"
					dispositionReason = "session_locked"
					return nil
				end

				-- RewardRules is the sole reward authority. Its pure call calculates the
				-- amount, validates participation, updates stats/balances, and appends
				-- the idempotency ledger inside this one atomic transform.
				local applied, applyReason = RewardRules.applyMatchReward(
					decoded.profile,
					item.context,
					item.request.grantedAt
				)
				if not applied then
					disposition = "Rejected"
					dispositionReason = applyReason or "reward_rejected"
					return nil
				end

				local nextStored: StoredProfile = {
					formatVersion = FORMAT_VERSION,
					profile = applied.profile,
					session = cloneLease(acquisition.lease),
				}
				disposition = "Ready"
				observed = cloneStored(nextStored)
				appliedStatus = applied.status
				appliedGrant = cloneGrant(applied.grant)
				dispositionReason = nil
				return encodeStored(nextStored)
			end)
		end
	)
	if not ok then
		return {
			kind = "Failed",
			value = observed,
			rewardStatus = appliedStatus,
			grant = appliedGrant,
			reason = requestError,
		}
	end
	if disposition ~= "Ready" then
		return {
			kind = disposition,
			value = observed,
			rewardStatus = appliedStatus,
			grant = appliedGrant,
			reason = dispositionReason,
		}
	end

	local decoded, decodeKind, decodeReason = decodeStored(updatedValue)
	if decodeKind ~= "Safe" or not decoded or not appliedStatus or not appliedGrant then
		return {
			kind = if decodeKind == "Future" then "Future" else "Corrupt",
			reason = decodeReason or "invalid_reward_update_result",
		}
	end
	return {
		kind = "Ready",
		value = decoded,
		rewardStatus = appliedStatus,
		grant = appliedGrant,
	}
end

local function applySafeRewardFallback(record: ProfileRecord, item: RewardItem): boolean
	if record.storage ~= "DataStore" then
		return false
	end
	local fallback = readDataStore(record.key)
	if fallback.kind ~= "Ready" or not fallback.value then
		record.profile = nil
		record.session = nil
		setStatus(record, "Unavailable")
		deferCallback(item.callback, rewardResult("Unavailable", 0, 0))
		return true
	end

	local stored = fallback.value
	local grantId = RewardRules.buildGrantId(item.context.matchId, item.context.userId)
	local grant = if grantId then findGrant(stored.profile, grantId) else nil
	record.profile = ProfileRules.clone(stored.profile)
	local session = stored.session
	if session and SessionRules.isActiveOwner(session, SERVER_OWNER_ID, currentUnixTime()) then
		record.session = cloneLease(session)
		setStatus(record, "Ready")
	else
		record.session = nil
		setStatus(record, "ReadOnly")
	end
	if grant then
		rewardsDuplicate = saturatingIncrement(rewardsDuplicate)
		setDiagnostics()
		deferCallback(item.callback, rewardResult("Duplicate", grant.coins, grant.xp))
		return true
	end
	local status: RewardResultStatus = if record.status == "ReadOnly"
		then "ReadOnly"
		else "Unavailable"
	deferCallback(item.callback, rewardResult(status, 0, 0))
	return true
end

local function processReward(record: ProfileRecord, item: RewardItem)
	if record.status == "ReadOnly" then
		deferCallback(item.callback, rewardResult("ReadOnly", 0, 0))
		return
	end
	if record.status ~= "Ready" then
		deferCallback(item.callback, rewardResult("Unavailable", 0, 0))
		return
	end

	local result = if record.storage == "SessionMemory"
		then applyRewardInSessionMemory(item, record)
		else applyRewardInDataStore(item, record)
	if result.kind == "Ready" and result.value and result.rewardStatus and result.grant then
		record.profile = ProfileRules.clone(result.value.profile)
		record.session = if result.value.session then cloneLease(result.value.session) else nil
		publishRecord(record)
		if result.rewardStatus == "Granted" then
			rewardsGranted = saturatingIncrement(rewardsGranted)
		else
			rewardsDuplicate = saturatingIncrement(rewardsDuplicate)
		end
		setDiagnostics()
		deferCallback(
			item.callback,
			rewardResult(result.rewardStatus, result.grant.coins, result.grant.xp)
		)
		return
	end

	if result.kind == "Rejected" then
		deferCallback(item.callback, rewardResult("Unavailable", 0, 0))
		return
	end
	if result.kind == "Failed" and applySafeRewardFallback(record, item) then
		return
	end
	if result.kind == "Locked" then
		if record.storage == "DataStore" and applySafeRewardFallback(record, item) then
			return
		end
		record.session = nil
		setStatus(record, "ReadOnly")
		deferCallback(item.callback, rewardResult("ReadOnly", 0, 0))
		return
	end
	if result.kind == "Future" then
		record.profile = nil
		record.session = nil
		setStatus(record, "Unavailable")
		deferCallback(item.callback, rewardResult("Unavailable", 0, 0))
		return
	end

	if record.status == "Ready" then
		record.profile = nil
		record.session = nil
		setStatus(record, "Unavailable")
	end
	deferCallback(item.callback, rewardResult("Unavailable", 0, 0))
end

local function renewInSessionMemory(record: ProfileRecord): PersistenceResult
	local current = sessionMemory[record.key]
	if not current then
		return { kind = "Corrupt", reason = "profile_missing_during_renew" }
	end
	local stored = cloneStored(current)
	local acquisition, reason = SessionRules.acquire(
		stored.session,
		SERVER_OWNER_ID,
		currentUnixTime(),
		LEASE_DURATION_SECONDS
	)
	if not acquisition then
		return { kind = "Corrupt", value = stored, reason = reason }
	end
	if acquisition.status == "Locked" then
		return { kind = "Locked", value = stored, reason = "session_locked" }
	end
	stored.session = cloneLease(acquisition.lease)
	sessionMemory[record.key] = cloneStored(stored)
	return { kind = "Ready", value = cloneStored(stored) }
end

local function renewInDataStore(record: ProfileRecord): PersistenceResult
	local store = getNativeStore()
	if not store then
		return { kind = "Failed", reason = "data_store_unavailable" }
	end

	local disposition: PersistenceResultKind = "Failed"
	local observed: StoredProfile? = nil
	local dispositionReason: string? = nil
	local ok, updatedValue, requestError = runDataStoreRequest(
		Enum.DataStoreRequestType.UpdateAsync,
		function()
			return store:UpdateAsync(record.key, function(currentValue: any)
				local decoded, decodeKind, decodeReason = decodeStored(currentValue)
				if decodeKind ~= "Safe" or not decoded then
					disposition = if decodeKind == "Future" then "Future" else "Corrupt"
					dispositionReason = decodeReason or "profile_missing_during_renew"
					return nil
				end
				observed = cloneStored(decoded)

				local acquisition, acquisitionReason = SessionRules.acquire(
					decoded.session,
					SERVER_OWNER_ID,
					currentUnixTime(),
					LEASE_DURATION_SECONDS
				)
				if not acquisition then
					disposition = "Corrupt"
					dispositionReason = acquisitionReason or "lease_failed"
					return nil
				end
				if acquisition.status == "Locked" then
					disposition = "Locked"
					dispositionReason = "session_locked"
					return nil
				end

				local nextStored: StoredProfile = {
					formatVersion = FORMAT_VERSION,
					profile = ProfileRules.clone(decoded.profile),
					session = cloneLease(acquisition.lease),
				}
				disposition = "Ready"
				observed = cloneStored(nextStored)
				dispositionReason = nil
				return encodeStored(nextStored)
			end)
		end
	)
	if not ok then
		return { kind = "Failed", value = observed, reason = requestError }
	end
	if disposition ~= "Ready" then
		return { kind = disposition, value = observed, reason = dispositionReason }
	end
	local decoded, decodeKind, decodeReason = decodeStored(updatedValue)
	if decodeKind ~= "Safe" or not decoded then
		return {
			kind = if decodeKind == "Future" then "Future" else "Corrupt",
			reason = decodeReason or "invalid_renew_result",
		}
	end
	return { kind = "Ready", value = decoded }
end

local function processRenew(record: ProfileRecord)
	if record.status ~= "Ready" then
		return
	end
	local result = if record.storage == "SessionMemory"
		then renewInSessionMemory(record)
		else renewInDataStore(record)
	if result.kind == "Ready" and result.value then
		record.profile = ProfileRules.clone(result.value.profile)
		record.session = if result.value.session then cloneLease(result.value.session) else nil
		publishRecord(record)
		return
	end
	if result.kind == "Locked" and result.value then
		record.profile = ProfileRules.clone(result.value.profile)
		record.session = nil
		setStatus(record, "ReadOnly")
		return
	end
	if result.kind == "Future" then
		record.profile = nil
		record.session = nil
		setStatus(record, "Unavailable")
		return
	end
	if result.kind == "Failed" and record.storage == "DataStore" then
		local fallback = readDataStore(record.key)
		if fallback.kind == "Ready" and fallback.value then
			record.profile = ProfileRules.clone(fallback.value.profile)
			local session = fallback.value.session
			if
				session and SessionRules.isActiveOwner(session, SERVER_OWNER_ID, currentUnixTime())
			then
				record.session = cloneLease(session)
				publishRecord(record)
			else
				record.session = nil
				setStatus(record, "ReadOnly")
			end
			return
		elseif fallback.kind == "Future" then
			record.profile = nil
			record.session = nil
			setStatus(record, "Unavailable")
			return
		end
	end

	record.profile = nil
	record.session = nil
	setStatus(record, "Unavailable")
end

local function releaseSessionMemory(record: ProfileRecord)
	local current = sessionMemory[record.key]
	if not current then
		return
	end
	local stored = cloneStored(current)
	local session = stored.session
	if session and SessionRules.isOwnedBy(session, SERVER_OWNER_ID) then
		stored.session = nil
		sessionMemory[record.key] = cloneStored(stored)
	end
end

local function releaseDataStore(record: ProfileRecord): PersistenceResult
	local store = getNativeStore()
	if not store then
		return { kind = "Failed", reason = "data_store_unavailable" }
	end

	local disposition: PersistenceResultKind = "Failed"
	local observed: StoredProfile? = nil
	local dispositionReason: string? = nil
	local ok, updatedValue, requestError = runDataStoreRequest(
		Enum.DataStoreRequestType.UpdateAsync,
		function()
			return store:UpdateAsync(record.key, function(currentValue: any)
				local decoded, decodeKind, decodeReason = decodeStored(currentValue)
				if decodeKind ~= "Safe" or not decoded then
					disposition = if decodeKind == "Future" then "Future" else "Corrupt"
					dispositionReason = decodeReason or "profile_missing_during_release"
					return nil
				end
				observed = cloneStored(decoded)
				local session = decoded.session
				if not session or not SessionRules.isOwnedBy(session, SERVER_OWNER_ID) then
					disposition = "Lost"
					dispositionReason = "session_not_owned"
					return nil
				end

				local nextStored: StoredProfile = {
					formatVersion = FORMAT_VERSION,
					profile = ProfileRules.clone(decoded.profile),
					session = nil,
				}
				disposition = "Ready"
				observed = cloneStored(nextStored)
				dispositionReason = nil
				return encodeStored(nextStored)
			end)
		end
	)
	if not ok then
		return { kind = "Failed", value = observed, reason = requestError }
	end
	if disposition ~= "Ready" then
		return { kind = disposition, value = observed, reason = dispositionReason }
	end
	local decoded, decodeKind, decodeReason = decodeStored(updatedValue)
	if decodeKind ~= "Safe" or not decoded then
		return {
			kind = if decodeKind == "Future" then "Future" else "Corrupt",
			reason = decodeReason or "invalid_release_result",
		}
	end
	return { kind = "Ready", value = decoded }
end

local function processRelease(record: ProfileRecord)
	if record.status == "Ready" then
		if record.storage == "SessionMemory" then
			releaseSessionMemory(record)
		else
			releaseDataStore(record)
		end
	end
	record.session = nil
	setStatus(record, "Released")
end

local runWorker: (record: ProfileRecord) -> ()

local function startWorker(record: ProfileRecord)
	if not record.laneActive or record.workerRunning then
		return
	end
	if record.queue[record.queueHead] == nil then
		return
	end
	record.workerRunning = true
	-- Deferring the worker guarantees the caller can replicate its immediate
	-- Pending/Result state before any in-memory adapter callback resolves.
	task.defer(runWorker, record)
end

local function enqueueItem(record: ProfileRecord, item: QueueItem)
	table.insert(record.queue, item)
	setDiagnostics()
	startWorker(record)
end

local function compactQueue(record: ProfileRecord)
	if record.queueHead <= 64 or record.queueHead <= #record.queue / 2 then
		return
	end
	local compacted: { QueueItem } = {}
	for index = record.queueHead, #record.queue do
		table.insert(compacted, record.queue[index])
	end
	record.queue = compacted
	record.queueHead = 1
end

local function handleWorkerFailure(record: ProfileRecord, item: QueueItem, workerError: any)
	storageFailures = saturatingIncrement(storageFailures)
	warn(string.format("[CritterClash] profile queue operation failed: %s", tostring(workerError)))
	if item.kind == "Reward" then
		record.profile = nil
		record.session = nil
		setStatus(record, "Unavailable")
		deferCallback(item.callback, rewardResult("Unavailable", 0, 0))
	elseif item.kind == "Release" then
		record.session = nil
		setStatus(record, "Released")
	else
		record.profile = nil
		record.session = nil
		setStatus(record, "Unavailable")
	end
	setDiagnostics()
end

local function activateNextRecord(key: string)
	local pending = pendingRecordsByKey[key]
	if not pending then
		return
	end
	while #pending > 0 do
		local nextRecord = table.remove(pending, 1)
		if nextRecord and records[nextRecord.player] == nextRecord then
			nextRecord.laneActive = true
			activeRecordByKey[key] = nextRecord
			if #pending == 0 then
				pendingRecordsByKey[key] = nil
			end
			startWorker(nextRecord)
			return
		end
	end
	pendingRecordsByKey[key] = nil
end

runWorker = function(record: ProfileRecord)
	while true do
		local item = record.queue[record.queueHead]
		if not item then
			record.workerRunning = false
			if record.status == "Released" and records[record.player] == record then
				records[record.player] = nil
				if activeRecordByKey[record.key] == record then
					activeRecordByKey[record.key] = nil
					record.laneActive = false
					activateNextRecord(record.key)
				end
			end
			setDiagnostics()
			return
		end
		record.queueHead += 1

		local ok, workerError = pcall(function()
			if item.kind == "Load" then
				loadRecord(record)
			elseif item.kind == "Reward" then
				processReward(record, item)
			elseif item.kind == "Renew" then
				processRenew(record)
			elseif item.kind == "Release" then
				processRelease(record)
			end
		end)
		if item.kind == "Renew" then
			record.renewQueued = false
		end
		if not ok then
			handleWorkerFailure(record, item, workerError)
		end
		compactQueue(record)
		setDiagnostics()
	end
end

local function queueRenew(record: ProfileRecord)
	if record.status ~= "Ready" or record.releaseQueued or record.renewQueued or shuttingDown then
		return
	end
	record.renewQueued = true
	enqueueItem(record, { kind = "Renew" })
end

local function queueRelease(record: ProfileRecord)
	if record.releaseQueued or record.status == "Released" then
		return
	end
	record.acceptingRewards = false
	record.releaseQueued = true
	enqueueItem(record, { kind = "Release" })
end

local function storageBackendForPlayer(player: Player): StorageBackend
	if
		ALLOW_UNPUBLISHED_STUDIO_MEMORY
		and RunService:IsStudio()
		and (game.PlaceId == 0 or player.UserId <= 0)
	then
		return "SessionMemory"
	end
	return "DataStore"
end

local function addPlayer(player: Player)
	if shuttingDown or records[player] then
		return
	end
	local key = PROFILE_KEY_PREFIX .. tostring(player.UserId)
	local hasActiveLane = activeRecordByKey[key] ~= nil
	local record: ProfileRecord = {
		player = player,
		key = key,
		storage = storageBackendForPlayer(player),
		status = "Loading",
		profile = nil,
		session = nil,
		queue = { { kind = "Load" } },
		queueHead = 1,
		laneActive = not hasActiveLane,
		workerRunning = false,
		acceptingRewards = true,
		releaseQueued = false,
		renewQueued = false,
	}
	records[player] = record
	publishRecord(record)
	if hasActiveLane then
		local pending = pendingRecordsByKey[key]
		if not pending then
			pending = {}
			pendingRecordsByKey[key] = pending
		end
		table.insert(pending, record)
	else
		activeRecordByKey[key] = record
		startWorker(record)
	end
	setDiagnostics()
end

local function removePlayer(player: Player)
	local record = records[player]
	if not record then
		return
	end
	-- Signal callbacks registered by MatchService may synchronously finalize a
	-- match because of this same departure. Deferring puts those rewards before
	-- the release marker while still rejecting every later reward.
	task.defer(function()
		if records[player] == record then
			queueRelease(record)
		end
	end)
end

local function startAutosaveLoop()
	task.spawn(function()
		while started and not shuttingDown do
			local jitter = random:NextNumber(-AUTOSAVE_JITTER_SECONDS, AUTOSAVE_JITTER_SECONDS)
			task.wait(math.max(1, AUTOSAVE_INTERVAL_SECONDS + jitter))
			if shuttingDown then
				return
			end
			for _, record in records do
				queueRenew(record)
			end
		end
	end)
end

local function closeServer()
	if shuttingDown then
		return
	end
	shuttingDown = true
	shutdownDeadline = os.clock() + SHUTDOWN_TIMEOUT_SECONDS
	for _, record in records do
		queueRelease(record)
	end

	while os.clock() < (shutdownDeadline :: number) do
		local pending = false
		for _, record in records do
			if record.status ~= "Released" or record.workerRunning then
				pending = true
				break
			end
		end
		if not pending then
			break
		end
		task.wait(0.05)
	end
	setDiagnostics()
end

function DataService.enqueueMatchReward(
	player: Player,
	requestValue: RewardRequest,
	callback: RewardCallback
): EnqueueStatus
	local request, context = cloneAndValidateRequest(player, requestValue)
	if not request or not context or typeof(callback) ~= "function" then
		if typeof(callback) == "function" then
			deferCallback(callback, rewardResult("Unavailable", 0, 0))
		end
		return "Unavailable"
	end

	local record = records[player]
	if not record or not record.acceptingRewards or record.releaseQueued or shuttingDown then
		deferCallback(callback, rewardResult("Unavailable", 0, 0))
		return "Unavailable"
	end
	if record.status == "ReadOnly" then
		deferCallback(callback, rewardResult("ReadOnly", 0, 0))
		return "ReadOnly"
	end
	if record.status == "Unavailable" or record.status == "Released" then
		deferCallback(callback, rewardResult("Unavailable", 0, 0))
		return "Unavailable"
	end

	enqueueItem(record, {
		kind = "Reward",
		request = request,
		context = context,
		callback = callback,
	})
	return "Accepted"
end

function DataService.start()
	assert(not started, "DataService may only be started once")
	started = true
	shuttingDown = false
	Workspace:SetAttribute("CritterClashProfileEnvironment", EnvironmentConfig.name)
	setDiagnostics()

	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(removePlayer)
	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end
	startAutosaveLoop()
	game:BindToClose(closeServer)
end

return DataService
