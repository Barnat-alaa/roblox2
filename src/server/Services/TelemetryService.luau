--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EnvironmentConfig = require(ReplicatedStorage.Shared.Config.EnvironmentConfig)
local TelemetryConfig = require(ReplicatedStorage.Shared.Config.TelemetryConfig)
local TelemetryRules = require(ReplicatedStorage.Shared.Analytics.TelemetryRules)

type Payload = TelemetryRules.Payload

local TelemetryService = {}

local started = false
local eventCount = 0
local droppedCount = 0

local function publishDiagnostics(eventName: string?)
	Workspace:SetAttribute("CritterClashTelemetryVersion", TelemetryConfig.version)
	Workspace:SetAttribute("CritterClashTelemetryEvents", eventCount)
	Workspace:SetAttribute("CritterClashTelemetryDropped", droppedCount)
	if eventName then
		Workspace:SetAttribute("CritterClashTelemetryLastEvent", eventName)
	end
end

function TelemetryService.start()
	assert(not started, "TelemetryService may only be started once")
	started = true
	publishDiagnostics(nil)
end

function TelemetryService.emit(eventName: string, payload: Payload): boolean
	if not started then
		return false
	end
	local sanitized, reason = TelemetryRules.sanitize(eventName, payload)
	if not sanitized then
		droppedCount = math.min(TelemetryConfig.maxEvents, droppedCount + 1)
		publishDiagnostics(nil)
		warn(
			string.format(
				"[CritterClash] telemetry rejected %s: %s",
				eventName,
				reason or "invalid"
			)
		)
		return false
	end

	eventCount = math.min(TelemetryConfig.maxEvents, eventCount + 1)
	publishDiagnostics(eventName)
	if TelemetryConfig.developmentLoggingEnabled and EnvironmentConfig.name == "Development" then
		local envelope = {
			version = TelemetryConfig.version,
			environment = EnvironmentConfig.name,
			event = eventName,
			serverTime = Workspace:GetServerTimeNow(),
			payload = sanitized,
		}
		local encoded = HttpService:JSONEncode(envelope)
		print("[CritterClashTelemetry] " .. encoded)
	end
	return true
end

return TelemetryService
