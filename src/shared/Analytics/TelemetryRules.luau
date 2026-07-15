--!strict

local TelemetryConfig = require(script.Parent.Parent.Config.TelemetryConfig)

type FieldKind = "boolean" | "number" | "string"

type FieldRule = {
	kind: FieldKind,
	required: boolean?,
	minimum: number?,
	maximum: number?,
	values: { [string]: boolean }?,
}

export type Payload = { [string]: boolean | number | string }

local function enumValues(values: { string }): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, value in values do
		result[value] = true
	end
	return table.freeze(result)
end

local EVENT_SCHEMAS: { [string]: { [string]: FieldRule } } = {
	session_started = {
		storage = {
			kind = "string",
			values = enumValues({ "Persistent", "SessionMemory", "ReadOnly", "Unavailable" }),
		},
	},
	queue_joined = {
		mode = { kind = "string", required = true, values = enumValues({ "Practice", "Casual" }) },
	},
	queue_cancelled = {
		mode = { kind = "string", required = true, values = enumValues({ "Practice", "Casual" }) },
		waitSeconds = { kind = "number", minimum = 0, maximum = 3_600 },
	},
	queue_matched = {
		mode = { kind = "string", required = true, values = enumValues({ "Practice", "Casual" }) },
		opponent = { kind = "string", required = true, values = enumValues({ "Bot", "Player" }) },
		waitSeconds = { kind = "number", minimum = 0, maximum = 3_600 },
	},
	match_started = {
		mode = {
			kind = "string",
			required = true,
			values = enumValues({ "Practice", "Casual", "Rematch" }),
		},
		versusBot = { kind = "boolean", required = true },
		participantCount = { kind = "number", minimum = 1, maximum = 4 },
	},
	match_completed = {
		reason = { kind = "string", required = true },
		versusBot = { kind = "boolean", required = true },
		durationSeconds = { kind = "number", minimum = 0, maximum = 7_200 },
	},
	rematch_selected = {
		versusBot = { kind = "boolean", required = true },
	},
	shot_fired = {
		weaponId = { kind = "string", required = true },
		actor = { kind = "string", required = true, values = enumValues({ "Bot", "Player" }) },
	},
	projectile_impacted = {
		weaponId = { kind = "string", required = true },
		terrainCellsChanged = { kind = "number", minimum = 0, maximum = 100_000 },
	},
	cosmetic_equipped = {
		cosmeticId = { kind = "string", required = true },
	},
	settings_changed = {
		reducedEffects = { kind = "boolean", required = true },
		cameraShake = { kind = "number", required = true, minimum = 0, maximum = 1 },
		uiScale = { kind = "number", required = true, minimum = 0.8, maximum = 1.2 },
	},
	telemetry_error = {
		source = { kind = "string", required = true },
		code = { kind = "string", required = true },
	},
}

local TelemetryRules = {}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function validateField(value: unknown, rule: FieldRule): boolean
	if typeof(value) ~= rule.kind then
		return false
	end
	if rule.kind == "number" then
		local numberValue = value :: number
		return isFinite(numberValue)
			and (rule.minimum == nil or numberValue >= rule.minimum)
			and (rule.maximum == nil or numberValue <= rule.maximum)
	end
	if rule.kind == "string" then
		local stringValue = value :: string
		return #stringValue > 0
			and #stringValue <= TelemetryConfig.maxTextLength
			and stringValue:find("[%c]") == nil
			and (rule.values == nil or rule.values[stringValue] == true)
	end
	return true
end

function TelemetryRules.sanitize(eventName: unknown, payload: unknown): (Payload?, string?)
	if type(eventName) ~= "string" or not EVENT_SCHEMAS[eventName] then
		return nil, "unknown_event"
	end
	if typeof(payload) ~= "table" then
		return nil, "invalid_payload"
	end

	local schema = EVENT_SCHEMAS[eventName]
	local raw = payload :: { [any]: any }
	local result: Payload = {}
	local fieldCount = 0
	for field, value in raw do
		if type(field) ~= "string" or not schema[field] then
			return nil, "unexpected_field"
		end
		fieldCount += 1
		if fieldCount > TelemetryConfig.maxPayloadFields then
			return nil, "too_many_fields"
		end
		local rule = schema[field]
		if not validateField(value, rule) then
			return nil, "invalid_field"
		end
		result[field] = value :: boolean | number | string
	end

	for field, rule in schema do
		if rule.required and result[field] == nil then
			return nil, "missing_field"
		end
	end
	return table.freeze(result), nil
end

function TelemetryRules.isKnownEvent(eventName: string): boolean
	return EVENT_SCHEMAS[eventName] ~= nil
end

return table.freeze(TelemetryRules)
