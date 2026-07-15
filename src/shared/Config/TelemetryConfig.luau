--!strict

local TelemetryConfig = {
	version = 1,
	maxTextLength = 64,
	maxPayloadFields = 8,
	maxEvents = 1_000_000_000,
	developmentLoggingEnabled = true,
}

return table.freeze(TelemetryConfig)
