--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MatchRules = require(ReplicatedStorage.Shared.Simulation.MatchRules)

local CharacterService = require(script.Parent.CharacterService)
local MatchService = require(script.Parent.MatchService)
local NetworkService = require(script.Parent.NetworkService)

type Remotes = NetworkService.Remotes

type MovementRequest = {
	matchId: string,
	turnToken: number,
	sequence: number,
	moveX: number,
	jumpRequested: boolean,
}

local MAX_SEQUENCE = 2_147_483_647
local REQUEST_BUCKET_CAPACITY = 12
local REQUEST_REFILL_PER_SECOND = 20
local DIAGNOSTICS_INTERVAL_SECONDS = 1

type RequestBucket = {
	tokens: number,
	updatedAt: number,
}

local MovementService = {}

local requestBuckets: { [Player]: RequestBucket } = {}
local acceptedRequestCount = 0
local rejectedRequestCount = 0
local diagnosticsDirty = true
local lastDiagnosticsAt = -math.huge
local started = false

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isPositiveInteger(value: number): boolean
	return isFinite(value) and value >= 1 and value <= MAX_SEQUENCE and value == math.floor(value)
end

local function markDiagnosticsDirty()
	diagnosticsDirty = true
end

local function publishDiagnostics(now: number, force: boolean?)
	if
		not force
		and (not diagnosticsDirty or now - lastDiagnosticsAt < DIAGNOSTICS_INTERVAL_SECONDS)
	then
		return
	end
	Workspace:SetAttribute("CritterClashMovementAcceptedRequestCount", acceptedRequestCount)
	Workspace:SetAttribute("CritterClashMovementRejectedRequestCount", rejectedRequestCount)
	diagnosticsDirty = false
	lastDiagnosticsAt = now
end

local function parseRequest(value: unknown): MovementRequest?
	if typeof(value) ~= "table" then
		return nil
	end
	local request = value :: { [any]: any }
	local fieldCount = 0
	for key in request do
		if
			key ~= "matchId"
			and key ~= "turnToken"
			and key ~= "sequence"
			and key ~= "moveX"
			and key ~= "jumpRequested"
		then
			return nil
		end
		fieldCount += 1
	end
	if fieldCount ~= 5 then
		return nil
	end

	local matchId = request.matchId
	local turnToken = request.turnToken
	local sequence = request.sequence
	local moveX = request.moveX
	local jumpRequested = request.jumpRequested
	if
		not MatchRules.isValidMatchId(matchId)
		or typeof(turnToken) ~= "number"
		or not isPositiveInteger(turnToken)
		or typeof(sequence) ~= "number"
		or not isPositiveInteger(sequence)
		or typeof(moveX) ~= "number"
		or not isFinite(moveX)
		or moveX < -1
		or moveX > 1
		or typeof(jumpRequested) ~= "boolean"
	then
		return nil
	end

	return {
		matchId = matchId :: string,
		turnToken = turnToken,
		sequence = sequence,
		moveX = moveX,
		jumpRequested = jumpRequested,
	}
end

local function reject()
	rejectedRequestCount += 1
	markDiagnosticsDirty()
end

local function consumeRequestToken(player: Player): boolean
	local now = os.clock()
	local bucket = requestBuckets[player]
	if not bucket then
		bucket = {
			tokens = REQUEST_BUCKET_CAPACITY,
			updatedAt = now,
		}
		requestBuckets[player] = bucket
	end
	local elapsed = math.max(0, now - bucket.updatedAt)
	bucket.tokens =
		math.min(REQUEST_BUCKET_CAPACITY, bucket.tokens + elapsed * REQUEST_REFILL_PER_SECOND)
	bucket.updatedAt = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

local function onMovementRequested(player: Player, value: unknown)
	if not consumeRequestToken(player) then
		reject()
		return
	end

	local request = parseRequest(value)
	if not request then
		reject()
		return
	end
	local allowed = MatchService.canMove(player, request.matchId, request.turnToken)
	if not allowed then
		reject()
		return
	end
	local accepted = CharacterService.submitMovement(
		player,
		request.turnToken,
		request.sequence,
		request.moveX,
		request.jumpRequested
	)
	if not accepted then
		reject()
		return
	end
	acceptedRequestCount += 1
	markDiagnosticsDirty()
end

function MovementService.start(remotes: Remotes)
	assert(not started, "MovementService may only be started once")
	started = true
	acceptedRequestCount = 0
	rejectedRequestCount = 0
	diagnosticsDirty = true
	publishDiagnostics(Workspace:GetServerTimeNow(), true)
	remotes.requestMovement.OnServerEvent:Connect(function(player, request)
		onMovementRequested(player, request)
	end)
	Players.PlayerRemoving:Connect(function(player)
		requestBuckets[player] = nil
	end)
	RunService.Heartbeat:Connect(function()
		publishDiagnostics(Workspace:GetServerTimeNow())
	end)
end

return MovementService
