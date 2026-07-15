--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local SettingsRules = require(ReplicatedStorage.Shared.Progression.SettingsRules)

local DataService = require(script.Parent.DataService)
local NetworkService = require(script.Parent.NetworkService)
local TelemetryService = require(script.Parent.TelemetryService)

type Remotes = NetworkService.Remotes
type MutationResult = DataService.MutationResult

local CustomizationService = {}

type RateState = {
	lastAcceptedAt: number,
	windowStartedAt: number,
	acceptedInWindow: number,
}
type TelemetryDedupe = {
	key: string,
	emittedAt: number,
}

local REQUEST_COOLDOWN_SECONDS = 1
local REQUEST_WINDOW_SECONDS = 60
local MAX_REQUESTS_PER_WINDOW = 20
local SERVER_BUCKET_CAPACITY = 12
local SERVER_REFILL_PER_SECOND = 1
local INGRESS_COOLDOWN_SECONDS = 0.15
local REJECTION_FEEDBACK_SECONDS = 1
local rateByPlayer: { [Player]: RateState } = {}
local telemetryDedupeByPlayer: { [Player]: TelemetryDedupe } = {}
local ingressByPlayer: { [Player]: { [string]: number } } = {}
local rejectionFeedbackByPlayer: { [Player]: { [string]: number } } = {}
local serverTokens = SERVER_BUCKET_CAPACITY
local serverRefilledAt = os.clock()
local started = false

local function acceptsIngress(player: Player, action: string): boolean
	local now = os.clock()
	local byAction = ingressByPlayer[player]
	if not byAction then
		byAction = {}
		ingressByPlayer[player] = byAction
	end
	local previous = byAction[action]
	if previous and now - previous < INGRESS_COOLDOWN_SECONDS then
		return false
	end
	byAction[action] = now
	return true
end

local function hasOnlyField(payload: { [any]: any }, expected: string): boolean
	local found = false
	for field in payload do
		if field ~= expected then
			return false
		end
		found = true
	end
	return found
end

local function isRateLimited(player: Player): boolean
	local now = os.clock()
	local state = rateByPlayer[player]
	if not state then
		state = {
			lastAcceptedAt = -math.huge,
			windowStartedAt = now,
			acceptedInWindow = 0,
		}
		rateByPlayer[player] = state
	elseif now - state.windowStartedAt >= REQUEST_WINDOW_SECONDS then
		state.windowStartedAt = now
		state.acceptedInWindow = 0
	end
	if
		now - state.lastAcceptedAt < REQUEST_COOLDOWN_SECONDS
		or state.acceptedInWindow >= MAX_REQUESTS_PER_WINDOW
	then
		return true
	end
	local refillElapsed = math.max(0, now - serverRefilledAt)
	serverRefilledAt = now
	serverTokens =
		math.min(SERVER_BUCKET_CAPACITY, serverTokens + refillElapsed * SERVER_REFILL_PER_SECOND)
	if serverTokens < 1 then
		return true
	end
	serverTokens -= 1
	state.lastAcceptedAt = now
	state.acceptedInWindow += 1
	return false
end

local function sendResult(remotes: Remotes, player: Player, action: string, result: MutationResult)
	if player.Parent ~= Players then
		return
	end
	remotes.lobbyEvent:FireClient(player, "ProfileActionResult", {
		action = action,
		status = result.status,
		reason = result.reason,
	})
end

local function rejected(reason: string): MutationResult
	local result: MutationResult = {
		status = "Rejected",
		reason = reason,
	}
	return table.freeze(result)
end

local function sendRejection(remotes: Remotes, player: Player, action: string, reason: string)
	local now = os.clock()
	local byAction = rejectionFeedbackByPlayer[player]
	if not byAction then
		byAction = {}
		rejectionFeedbackByPlayer[player] = byAction
	end
	local previous = byAction[action]
	if previous and now - previous < REJECTION_FEEDBACK_SECONDS then
		return
	end
	byAction[action] = now
	sendResult(remotes, player, action, rejected(reason))
end

local function claimTelemetry(player: Player, key: string): boolean
	if player.Parent ~= Players then
		return false
	end
	local now = os.clock()
	local previous = telemetryDedupeByPlayer[player]
	if previous and previous.key == key and now - previous.emittedAt < 2 then
		return false
	end
	telemetryDedupeByPlayer[player] = {
		key = key,
		emittedAt = now,
	}
	return true
end

local function onEquipRequested(remotes: Remotes, player: Player, payload: unknown)
	if not acceptsIngress(player, "EquipCosmetic") then
		return
	end
	if typeof(payload) ~= "table" then
		sendRejection(remotes, player, "EquipCosmetic", "invalid_request")
		return
	end
	local request = payload :: { [any]: any }
	if
		not hasOnlyField(request, "cosmeticId")
		or type(request.cosmeticId) ~= "string"
		or Cosmetics.get(request.cosmeticId) == nil
	then
		sendRejection(remotes, player, "EquipCosmetic", "invalid_request")
		return
	end
	if isRateLimited(player) then
		sendRejection(remotes, player, "EquipCosmetic", "rate_limited")
		return
	end
	local cosmeticId = request.cosmeticId :: string
	DataService.enqueueEquipCosmetic(player, cosmeticId, function(result)
		if
			result.status == "Applied"
			and result.reason ~= "unchanged"
			and claimTelemetry(player, "cosmetic:" .. cosmeticId)
		then
			TelemetryService.emit("cosmetic_equipped", { cosmeticId = cosmeticId })
		end
		sendResult(remotes, player, "EquipCosmetic", result)
	end)
end

local function onSettingsRequested(remotes: Remotes, player: Player, payload: unknown)
	if not acceptsIngress(player, "Settings") then
		return
	end
	local validated = SettingsRules.applyPatch(SettingsRules.createDefault(), payload)
	if not validated or typeof(payload) ~= "table" or next(payload :: { [any]: any }) == nil then
		sendRejection(remotes, player, "Settings", "invalid_request")
		return
	end
	if isRateLimited(player) then
		sendRejection(remotes, player, "Settings", "rate_limited")
		return
	end
	DataService.enqueueSettings(player, payload, function(result)
		local settings = result.settings
		local telemetryKey = if settings
			then string.format(
				"settings:%s:%.3f:%.3f",
				tostring(settings.reducedEffects),
				settings.cameraShake,
				settings.uiScale
			)
			else "settings:missing"
		if
			result.status == "Applied"
			and result.reason ~= "unchanged"
			and settings
			and claimTelemetry(player, telemetryKey)
		then
			TelemetryService.emit("settings_changed", {
				reducedEffects = settings.reducedEffects,
				cameraShake = settings.cameraShake,
				uiScale = settings.uiScale,
			})
		end
		sendResult(remotes, player, "Settings", result)
	end)
end

function CustomizationService.start(remotes: Remotes)
	assert(not started, "CustomizationService may only be started once")
	started = true
	remotes.requestEquipCosmetic.OnServerEvent:Connect(function(player, payload)
		onEquipRequested(remotes, player, payload)
	end)
	remotes.requestSettings.OnServerEvent:Connect(function(player, payload)
		onSettingsRequested(remotes, player, payload)
	end)
	Players.PlayerRemoving:Connect(function(player)
		rateByPlayer[player] = nil
		telemetryDedupeByPlayer[player] = nil
		ingressByPlayer[player] = nil
		rejectionFeedbackByPlayer[player] = nil
	end)
end

return CustomizationService
