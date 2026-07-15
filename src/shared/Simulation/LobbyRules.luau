--!strict

local LobbyRules = {}

export type Mode = "Practice" | "Casual"

export type Request = {
	action: "Practice" | "Casual" | "Cancel" | "ReturnToLobby",
	queueToken: string?,
}

export type QueueEntry = {
	userId: number,
	mode: Mode,
	joinedAt: number,
}

export type Selection = {
	firstIndex: number,
	secondIndex: number?,
	mode: Mode,
	botFilled: boolean,
}

local MAXIMUM_QUEUE_TOKEN_LENGTH = 96

local function hasOnlyFields(value: { [any]: any }, allowed: { [string]: boolean }): boolean
	for key in value do
		if typeof(key) ~= "string" or not allowed[key :: string] then
			return false
		end
	end
	return true
end

function LobbyRules.isMode(value: unknown): boolean
	return value == "Practice" or value == "Casual"
end

function LobbyRules.isQueueToken(value: unknown): boolean
	return typeof(value) == "string"
		and #value >= 1
		and #value <= MAXIMUM_QUEUE_TOKEN_LENGTH
		and (value :: string):find("[%c%s]") == nil
end

-- Practice and Casual are actions rather than a generic action/mode pair. This
-- keeps the remote surface tiny and makes unknown requests fail closed.
function LobbyRules.parseRequest(value: unknown): Request?
	if typeof(value) ~= "table" then
		return nil
	end

	local request = value :: { [any]: any }
	local action = request.action
	if action == "Practice" or action == "Casual" or action == "ReturnToLobby" then
		if not hasOnlyFields(request, { action = true }) then
			return nil
		end
		local parsed: Request = {
			action = action,
			queueToken = nil,
		}
		return table.freeze(parsed)
	end

	if action == "Cancel" then
		if not hasOnlyFields(request, { action = true, queueToken = true }) then
			return nil
		end
		local queueToken: string? = nil
		if request.queueToken ~= nil then
			if typeof(request.queueToken) ~= "string" then
				return nil
			end
			queueToken = request.queueToken :: string
			if not LobbyRules.isQueueToken(queueToken) then
				return nil
			end
		end
		local parsed: Request = {
			action = "Cancel",
			queueToken = queueToken,
		}
		return table.freeze(parsed)
	end

	return nil
end

-- A tokenless cancel is retained for compatibility and is idempotent. Clients
-- that echo the published token gain stale-request protection after requeueing.
function LobbyRules.cancelMatches(activeToken: string, requestedToken: string?): boolean
	return requestedToken == nil or requestedToken == activeToken
end

-- A ready two-human Casual pair has priority. Otherwise Practice is immediate
-- and does not wait behind a lone Casual search. Casual bot-fill only begins at
-- the oldest Casual entry's bounded deadline.
function LobbyRules.selectMatch(
	queue: { QueueEntry },
	now: number,
	casualBotFillSeconds: number
): Selection?
	local first = queue[1]
	if not first then
		return nil
	end
	if first.mode == "Practice" then
		local selection: Selection = {
			firstIndex = 1,
			secondIndex = nil,
			mode = "Practice",
			botFilled = true,
		}
		return table.freeze(selection)
	end

	for index = 2, #queue do
		if queue[index].mode == "Casual" then
			local selection: Selection = {
				firstIndex = 1,
				secondIndex = index,
				mode = "Casual",
				botFilled = false,
			}
			return table.freeze(selection)
		end
	end

	for index = 2, #queue do
		if queue[index].mode == "Practice" then
			local selection: Selection = {
				firstIndex = index,
				secondIndex = nil,
				mode = "Practice",
				botFilled = true,
			}
			return table.freeze(selection)
		end
	end

	if now >= first.joinedAt + math.max(0, casualBotFillSeconds) then
		local selection: Selection = {
			firstIndex = 1,
			secondIndex = nil,
			mode = "Casual",
			botFilled = true,
		}
		return table.freeze(selection)
	end
	return nil
end

function LobbyRules.queuePosition(queue: { QueueEntry }, userId: number): number?
	for index, entry in queue do
		if entry.userId == userId then
			return index
		end
	end
	return nil
end

return table.freeze(LobbyRules)
