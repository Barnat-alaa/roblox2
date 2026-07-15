--!strict

-- Server-local matchmaking intentionally stays small and deterministic for the
-- first public slice. Cross-server matchmaking can replace the runtime service
-- later without changing the client contract or these admission rules.

return table.freeze({
	casualBotFillSeconds = 8,
	queuePollSeconds = 0.2,
	requestRateLimitSeconds = 0.15,
	maximumQueueTokenLength = 96,
})
