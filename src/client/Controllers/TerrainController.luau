--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local TerrainGrid = require(ReplicatedStorage.Shared.Simulation.TerrainGrid)

local CHUNK_SIZE = 8
local CHUNKS_PER_HEARTBEAT = 4
local MAX_POOL_SIZE = 1_024
local SNAPSHOT_RETRY_SECONDS = 2.5
local WARNING_INTERVAL_SECONDS = 2
local MAX_CELL_SIZE = 1_024
local MAX_TERRAIN_DEPTH = 1_024
local MAX_WORLD_COORDINATE = 1_000_000

local EMPTY = 0
local SOLID = 1
local HAZARD = 2
local INDESTRUCTIBLE = 3

local SOLID_COLOR = Color3.fromRGB(91, 123, 105)
local HAZARD_COLOR = Color3.fromRGB(242, 140, 40)
local INDESTRUCTIBLE_COLOR = Color3.fromRGB(20, 40, 61)

type NetworkTable = { [any]: any }
type Grid = TerrainGrid.Grid
type Snapshot = TerrainGrid.Snapshot
type CellDelta = TerrainGrid.CellDelta

type ParsedSnapshot = {
	revision: number,
	depth: number,
	snapshot: Snapshot,
}

type ChunkCoordinate = {
	x: number,
	y: number,
	key: string,
}

type ChunkVisual = {
	folder: Folder,
	parts: { Part },
}

export type Controller = {
	getRevision: () -> number?,
	requestSnapshot: () -> (),
	destroy: () -> (),
}

local TerrainController = {}

local VALID_CODES: { [number]: boolean } = {
	[EMPTY] = true,
	[SOLID] = true,
	[HAZARD] = true,
	[INDESTRUCTIBLE] = true,
}

local function asTable(value: any): NetworkTable?
	if type(value) ~= "table" then
		return nil
	end
	return value :: NetworkTable
end

local function finiteNumber(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function integer(value: any): number?
	local numberValue = finiteNumber(value)
	if not numberValue or numberValue ~= math.floor(numberValue) then
		return nil
	end
	return numberValue
end

local function positiveInteger(value: any): number?
	local numberValue = integer(value)
	if not numberValue or numberValue < 1 then
		return nil
	end
	return numberValue
end

local function nonNegativeInteger(value: any): number?
	local numberValue = integer(value)
	if not numberValue or numberValue < 0 then
		return nil
	end
	return numberValue
end

local function parseCells(value: any, expectedCount: number): { number }?
	local source = asTable(value)
	if not source then
		return nil
	end

	local cells = table.create(expectedCount) :: { number }
	local entryCount = 0
	for rawIndex, rawCode in source do
		local index = positiveInteger(rawIndex)
		local code = integer(rawCode)
		if not index or index > expectedCount or not code or not VALID_CODES[code] then
			return nil
		end
		entryCount += 1
		cells[index] = code
	end
	if entryCount ~= expectedCount then
		return nil
	end

	for index = 1, expectedCount do
		if cells[index] == nil then
			return nil
		end
	end
	return cells
end

local function parseSnapshot(value: any): ParsedSnapshot?
	local payload = asTable(value)
	if not payload then
		return nil
	end

	local revision = nonNegativeInteger(payload.revision)
	local chunkSize = positiveInteger(payload.chunkSize)
	local depth = finiteNumber(payload.depth)
	local rawSnapshot = asTable(payload.snapshot)
	if
		not revision
		or chunkSize ~= CHUNK_SIZE
		or not depth
		or depth <= 0
		or depth > MAX_TERRAIN_DEPTH
		or not rawSnapshot
	then
		return nil
	end

	local formatVersion = positiveInteger(rawSnapshot.formatVersion)
	local width = positiveInteger(rawSnapshot.width)
	local height = positiveInteger(rawSnapshot.height)
	local cellSize = finiteNumber(rawSnapshot.cellSize)
	local originX = finiteNumber(rawSnapshot.originX)
	local originY = finiteNumber(rawSnapshot.originY)
	if
		not formatVersion
		or formatVersion ~= TerrainGrid.FORMAT_VERSION
		or not width
		or width > TerrainGrid.MAX_DIMENSION
		or not height
		or height > TerrainGrid.MAX_DIMENSION
		or not cellSize
		or cellSize <= 0
		or cellSize > MAX_CELL_SIZE
		or not originX
		or not originY
		or math.abs(originX) > MAX_WORLD_COORDINATE
		or math.abs(originY) > MAX_WORLD_COORDINATE
	then
		return nil
	end

	local cellCount = width * height
	if cellCount > TerrainGrid.MAX_CELLS then
		return nil
	end
	if
		width * cellSize > MAX_WORLD_COORDINATE
		or height * cellSize > MAX_WORLD_COORDINATE
		or math.abs(originX + width * cellSize) > MAX_WORLD_COORDINATE
		or math.abs(originY + height * cellSize) > MAX_WORLD_COORDINATE
	then
		return nil
	end

	local cells = parseCells(rawSnapshot.cells, cellCount)
	if not cells then
		return nil
	end

	local snapshot: Snapshot = {
		formatVersion = formatVersion,
		width = width,
		height = height,
		cellSize = cellSize,
		originX = originX,
		originY = originY,
		cells = cells,
	}
	local validConfig = TerrainGrid.validateConfig({
		width = width,
		height = height,
		cellSize = cellSize,
		origin = Vector2.new(originX, originY),
		defaultKind = "Empty",
	})
	if not validConfig then
		return nil
	end

	return {
		revision = revision,
		depth = depth,
		snapshot = snapshot,
	}
end

local function parseDelta(value: any, grid: Grid): (number?, number?, { CellDelta }?)
	local payload = asTable(value)
	if not payload then
		return nil, nil, nil
	end

	local baseRevision = nonNegativeInteger(payload.baseRevision)
	local revision = nonNegativeInteger(payload.revision)
	local rawDeltas = asTable(payload.deltas)
	if not baseRevision or not revision or revision ~= baseRevision + 1 or not rawDeltas then
		return nil, nil, nil
	end

	local maximumIndex = grid.width * grid.height
	local deltas: { CellDelta } = {}
	local seenIndices: { [number]: boolean } = {}
	local entryCount = 0
	for rawArrayIndex, rawDelta in rawDeltas do
		local arrayIndex = positiveInteger(rawArrayIndex)
		local deltaTable = asTable(rawDelta)
		if not arrayIndex or not deltaTable or arrayIndex > maximumIndex then
			return nil, nil, nil
		end

		local index = positiveInteger(deltaTable.index)
		local code = integer(deltaTable.code)
		if
			not index
			or index > maximumIndex
			or not code
			or not VALID_CODES[code]
			or seenIndices[index]
		then
			return nil, nil, nil
		end
		seenIndices[index] = true
		entryCount += 1
		deltas[arrayIndex] = {
			index = index,
			code = code,
		}
	end
	if entryCount > maximumIndex or entryCount ~= #deltas then
		return nil, nil, nil
	end

	return baseRevision, revision, deltas
end

local function chunkKey(chunkX: number, chunkY: number): string
	return string.format("%d:%d", chunkX, chunkY)
end

local function configurePart(part: Part, code: number)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = code ~= HAZARD
	part.Material = if code == HAZARD
		then Enum.Material.Neon
		elseif code == INDESTRUCTIBLE then Enum.Material.Slate
		else Enum.Material.Ground
	part.Color = if code == HAZARD
		then HAZARD_COLOR
		elseif code == INDESTRUCTIBLE then INDESTRUCTIBLE_COLOR
		else SOLID_COLOR
	part.Transparency = if code == HAZARD then 0.08 else 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("TerrainCode", code)
end

function TerrainController.create(
	terrainEventRemote: RemoteEvent,
	requestSnapshotRemote: RemoteEvent
): Controller
	local renderRoot = Instance.new("Folder")
	renderRoot.Name = "CritterClashClientTerrain"
	renderRoot.Archivable = false
	renderRoot.Parent = Workspace

	local grid: Grid? = nil
	local currentRevision: number? = nil
	local terrainDepth = 0
	local chunkVisuals: { [string]: ChunkVisual } = {}
	local partPool: { Part } = {}
	local dirtyChunks: { [string]: boolean } = {}
	local dirtyQueue: { ChunkCoordinate } = {}
	local dirtyQueueHead = 1
	local resyncPending = false
	local requestSerial = 0
	local lastRequestAt = -math.huge
	local lastWarningAt = -math.huge
	local destroyed = false

	local function reportProblem(reason: string)
		local now = os.clock()
		if now - lastWarningAt >= WARNING_INTERVAL_SECONDS then
			lastWarningAt = now
			warn(`[CritterClash Terrain] {reason}; requesting authoritative snapshot`)
		end
	end

	local function requestSnapshot()
		if destroyed then
			return
		end

		local now = os.clock()
		if resyncPending and now - lastRequestAt < SNAPSHOT_RETRY_SECONDS then
			return
		end
		resyncPending = true
		lastRequestAt = now
		requestSerial += 1
		local serial = requestSerial
		requestSnapshotRemote:FireServer()

		task.delay(SNAPSHOT_RETRY_SECONDS, function()
			if destroyed or not resyncPending or requestSerial ~= serial then
				return
			end
			resyncPending = false
			requestSnapshot()
		end)
	end

	local function releasePart(part: Part)
		part.Parent = nil
		if #partPool < MAX_POOL_SIZE then
			table.insert(partPool, part)
		else
			part:Destroy()
		end
	end

	local function acquirePart(parent: Instance): Part
		local pooledPart = table.remove(partPool)
		local part: Part = if pooledPart then pooledPart else Instance.new("Part")
		part.Parent = parent
		return part
	end

	local function removeChunkVisual(key: string)
		local visual = chunkVisuals[key]
		if not visual then
			return
		end
		chunkVisuals[key] = nil
		for _, part in visual.parts do
			releasePart(part)
		end
		visual.folder:Destroy()
	end

	local function clearRenderState()
		for _, visual in chunkVisuals do
			for _, part in visual.parts do
				releasePart(part)
			end
			visual.folder:Destroy()
		end
		table.clear(chunkVisuals)
		table.clear(dirtyChunks)
		table.clear(dirtyQueue)
		dirtyQueueHead = 1
	end

	local function enqueueChunk(chunkX: number, chunkY: number)
		local key = chunkKey(chunkX, chunkY)
		if dirtyChunks[key] then
			return
		end
		dirtyChunks[key] = true
		table.insert(dirtyQueue, {
			x = chunkX,
			y = chunkY,
			key = key,
		})
	end

	local function enqueueAllChunks(currentGrid: Grid)
		local chunkColumns = math.ceil(currentGrid.width / CHUNK_SIZE)
		local chunkRows = math.ceil(currentGrid.height / CHUNK_SIZE)
		for chunkY = 1, chunkRows do
			for chunkX = 1, chunkColumns do
				enqueueChunk(chunkX, chunkY)
			end
		end
	end

	local function ensureChunkVisual(coordinate: ChunkCoordinate): ChunkVisual
		local visual = chunkVisuals[coordinate.key]
		if visual then
			return visual
		end

		local folder = Instance.new("Folder")
		folder.Name = string.format("Chunk_%d_%d", coordinate.x, coordinate.y)
		folder.Parent = renderRoot
		local newVisual: ChunkVisual = {
			folder = folder,
			parts = {},
		}
		chunkVisuals[coordinate.key] = newVisual
		return newVisual
	end

	local function renderRectangle(
		visual: ChunkVisual,
		currentGrid: Grid,
		code: number,
		minimumX: number,
		minimumY: number,
		width: number,
		height: number
	)
		local part = acquirePart(visual.folder)
		configurePart(part, code)
		part.Name = if code == HAZARD
			then "HazardRun"
			elseif code == INDESTRUCTIBLE then "BoundaryRun"
			else "SolidRun"

		local sizeX = width * currentGrid.cellSize
		local sizeY = height * currentGrid.cellSize
		local centerX = currentGrid.origin.X + (minimumX - 1) * currentGrid.cellSize + sizeX * 0.5
		local centerY = currentGrid.origin.Y + (minimumY - 1) * currentGrid.cellSize + sizeY * 0.5
		part.Size = Vector3.new(sizeX, sizeY, terrainDepth)
		part.CFrame = CFrame.new(centerX, centerY, GameConfig.combatPlaneZ)
		table.insert(visual.parts, part)
	end

	local function rebuildChunk(coordinate: ChunkCoordinate)
		local currentGrid = grid
		if not currentGrid then
			return
		end

		removeChunkVisual(coordinate.key)
		local minimumX = (coordinate.x - 1) * CHUNK_SIZE + 1
		local minimumY = (coordinate.y - 1) * CHUNK_SIZE + 1
		local maximumX = math.min(currentGrid.width, minimumX + CHUNK_SIZE - 1)
		local maximumY = math.min(currentGrid.height, minimumY + CHUNK_SIZE - 1)
		if minimumX > maximumX or minimumY > maximumY then
			return
		end

		local visited: { [number]: boolean } = {}
		local visual: ChunkVisual? = nil
		for y = minimumY, maximumY do
			for x = minimumX, maximumX do
				local index = (y - 1) * currentGrid.width + x
				local code = currentGrid._cells[index]
				if code ~= EMPTY and not visited[index] then
					local rectangleWidth = 1
					while x + rectangleWidth <= maximumX do
						local candidateIndex = (y - 1) * currentGrid.width + x + rectangleWidth
						if
							visited[candidateIndex]
							or currentGrid._cells[candidateIndex] ~= code
						then
							break
						end
						rectangleWidth += 1
					end

					local rectangleHeight = 1
					while y + rectangleHeight <= maximumY do
						local rowMatches = true
						for candidateX = x, x + rectangleWidth - 1 do
							local candidateIndex = (y + rectangleHeight - 1) * currentGrid.width
								+ candidateX
							if
								visited[candidateIndex]
								or currentGrid._cells[candidateIndex] ~= code
							then
								rowMatches = false
								break
							end
						end
						if not rowMatches then
							break
						end
						rectangleHeight += 1
					end

					for visitedY = y, y + rectangleHeight - 1 do
						for visitedX = x, x + rectangleWidth - 1 do
							visited[(visitedY - 1) * currentGrid.width + visitedX] = true
						end
					end
					local rectangleVisual: ChunkVisual
					if visual then
						rectangleVisual = visual
					else
						rectangleVisual = ensureChunkVisual(coordinate)
						visual = rectangleVisual
					end
					renderRectangle(
						rectangleVisual,
						currentGrid,
						code,
						x,
						y,
						rectangleWidth,
						rectangleHeight
					)
				end
			end
		end
	end

	local function acceptSnapshot(snapshotData: ParsedSnapshot)
		local existingRevision = currentRevision
		if existingRevision and snapshotData.revision < existingRevision then
			reportProblem("ignored a stale terrain snapshot")
			requestSnapshot()
			return
		end

		local success, result = pcall(function(): Grid
			return TerrainGrid.fromSnapshot(snapshotData.snapshot)
		end)
		if not success then
			reportProblem("rejected an invalid terrain snapshot")
			requestSnapshot()
			return
		end

		clearRenderState()
		grid = result
		currentRevision = snapshotData.revision
		terrainDepth = snapshotData.depth
		renderRoot:SetAttribute("TerrainRevision", snapshotData.revision)
		renderRoot:SetAttribute("GridWidth", result.width)
		renderRoot:SetAttribute("GridHeight", result.height)
		renderRoot:SetAttribute("CellSize", result.cellSize)
		renderRoot:SetAttribute("ChunkSize", CHUNK_SIZE)
		resyncPending = false
		requestSerial += 1
		enqueueAllChunks(result)
	end

	local function handleDelta(value: any)
		local currentGrid = grid
		local revisionBefore = currentRevision
		if not currentGrid or revisionBefore == nil then
			reportProblem("received terrain delta before initial state")
			requestSnapshot()
			return
		end

		local baseRevision, revision, deltas = parseDelta(value, currentGrid)
		if not baseRevision or not revision or not deltas then
			reportProblem("rejected a malformed terrain delta")
			requestSnapshot()
			return
		end
		if revision <= revisionBefore then
			return
		end
		if baseRevision ~= revisionBefore then
			reportProblem("detected a terrain revision gap")
			requestSnapshot()
			return
		end

		local success = pcall(TerrainGrid.applyDelta, currentGrid, deltas)
		if not success then
			reportProblem("could not apply terrain delta atomically")
			requestSnapshot()
			return
		end
		currentRevision = revision
		renderRoot:SetAttribute("TerrainRevision", revision)

		for _, delta in deltas do
			local zeroBased = delta.index - 1
			local cellX = zeroBased % currentGrid.width + 1
			local cellY = math.floor(zeroBased / currentGrid.width) + 1
			enqueueChunk(
				math.floor((cellX - 1) / CHUNK_SIZE) + 1,
				math.floor((cellY - 1) / CHUNK_SIZE) + 1
			)
		end
	end

	local terrainConnection = terrainEventRemote.OnClientEvent:Connect(
		function(kind: any, payload: any)
			if kind == "Snapshot" then
				local snapshotData = parseSnapshot(payload)
				if not snapshotData then
					reportProblem("rejected a malformed terrain snapshot payload")
					requestSnapshot()
					return
				end
				acceptSnapshot(snapshotData)
			elseif kind == "Delta" then
				handleDelta(payload)
			end
		end
	)

	local heartbeatConnection = RunService.Heartbeat:Connect(function()
		for _ = 1, CHUNKS_PER_HEARTBEAT do
			local coordinate = dirtyQueue[dirtyQueueHead]
			if not coordinate then
				if dirtyQueueHead > 1 then
					table.clear(dirtyQueue)
					dirtyQueueHead = 1
				end
				break
			end

			dirtyQueueHead += 1
			if dirtyChunks[coordinate.key] then
				dirtyChunks[coordinate.key] = nil
				rebuildChunk(coordinate)
			end
		end
	end)

	task.defer(requestSnapshot)

	local controller: Controller = {
		getRevision = function(): number?
			return currentRevision
		end,
		requestSnapshot = requestSnapshot,
		destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			requestSerial += 1
			terrainConnection:Disconnect()
			heartbeatConnection:Disconnect()
			clearRenderState()
			for _, part in partPool do
				part:Destroy()
			end
			table.clear(partPool)
			renderRoot:Destroy()
		end,
	}

	return controller
end

return TerrainController
