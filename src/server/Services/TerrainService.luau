--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local TerrainGrid = require(ReplicatedStorage.Shared.Simulation.TerrainGrid)

local NetworkService = require(script.Parent.NetworkService)

type Remotes = NetworkService.Remotes
type Grid = TerrainGrid.Grid
type CellDelta = TerrainGrid.CellDelta
export type SupportResult = TerrainGrid.SupportResult

local GRID_WIDTH = 45
local GRID_HEIGHT = 24
local CELL_SIZE = 4
local GRID_ORIGIN = Vector2.new(-90, -12)
local CHUNK_SIZE = 8
local TERRAIN_DEPTH = 12
local MAX_CRATER_RADIUS = 32
local MAX_DRILL_LENGTH = 64
local MAX_DRILL_RADIUS = 16
local MAX_EDITED_CELLS = 256
local SNAPSHOT_COOLDOWN_SECONDS = 0.75
local COLLISION_ROOT_NAME = "TerrainCollision"
local COLLISION_TAG = "CritterTerrainCollision"
local INDESTRUCTIBLE_TAG = "CritterTerrainIndestructible"

local TerrainService = {}

local grid: Grid? = nil
local collisionRoot: Folder? = nil
local remotes: Remotes? = nil
local revision = 0
local resetCount = 0
local started = false
local lastSnapshotAt: { [Player]: number } = {}
local hazardContactHandler: ((Model) -> ())? = nil

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isFinitePosition(position: Vector3): boolean
	return isFinite(position.X) and isFinite(position.Y) and isFinite(position.Z)
end

local function chunkKey(chunkX: number, chunkY: number): string
	return string.format("%d:%d", chunkX, chunkY)
end

local function chunkName(chunkX: number, chunkY: number): string
	return string.format("Chunk_%d_%d", chunkX, chunkY)
end

local function setCell(currentGrid: Grid, x: number, y: number, kind: TerrainGrid.CellKind)
	TerrainGrid.setCell(currentGrid, x, y, kind)
end

local function fillHorizontalWorldRange(
	currentGrid: Grid,
	minimumWorldX: number,
	maximumWorldX: number,
	minimumY: number,
	maximumY: number,
	kind: TerrainGrid.CellKind
)
	for y = minimumY, maximumY do
		for x = 1, currentGrid.width do
			local center = TerrainGrid.cellToWorldCenter(currentGrid, x, y)
			assert(center ~= nil, "initial terrain cell must be in bounds")
			if center.X >= minimumWorldX and center.X <= maximumWorldX then
				setCell(currentGrid, x, y, kind)
			end
		end
	end
end

local function createInitialGrid(): Grid
	local currentGrid = TerrainGrid.create({
		width = GRID_WIDTH,
		height = GRID_HEIGHT,
		cellSize = CELL_SIZE,
		origin = GRID_ORIGIN,
		defaultKind = "Empty",
	})

	for x = 1, currentGrid.width do
		setCell(currentGrid, x, 1, "Indestructible")
		setCell(currentGrid, x, 2, "Solid")
		setCell(currentGrid, x, 3, "Solid")
	end
	fillHorizontalWorldRange(currentGrid, -6, 6, 3, 3, "Hazard")

	-- The shelves preserve the readable shape of the original greybox while the
	-- logical grid becomes the single source of truth for collision and visuals.
	fillHorizontalWorldRange(currentGrid, -70, -38, 4, 5, "Solid")
	fillHorizontalWorldRange(currentGrid, 42, 72, 4, 5, "Solid")

	-- Spawn support is protected from the bottom shell through each shelf so a
	-- first-turn crater cannot delete a newly spawned player's footing.
	fillHorizontalWorldRange(currentGrid, -70, -58, 2, 5, "Indestructible")
	fillHorizontalWorldRange(currentGrid, 58, 70, 2, 5, "Indestructible")

	return currentGrid
end

local function configureCollisionPart(part: Part, code: number)
	part.Anchored = true
	part.CanCollide = code ~= TerrainGrid.Codes.Hazard
	part.CanQuery = true
	part.CanTouch = code == TerrainGrid.Codes.Hazard
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 1
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("TerrainCode", code)
	CollectionService:AddTag(part, COLLISION_TAG)
	if code == TerrainGrid.Codes.Indestructible then
		CollectionService:AddTag(part, INDESTRUCTIBLE_TAG)
	end
	if code == TerrainGrid.Codes.Hazard then
		part.Touched:Connect(function(otherPart)
			local character = otherPart:FindFirstAncestorOfClass("Model")
			local handler = hazardContactHandler
			if character and handler then
				handler(character)
			end
		end)
	end
end

local function createCollisionRun(
	parent: Instance,
	currentGrid: Grid,
	y: number,
	minimumX: number,
	maximumX: number,
	code: number
)
	local width = maximumX - minimumX + 1
	local firstCenter = TerrainGrid.cellToWorldCenter(currentGrid, minimumX, y)
	local lastCenter = TerrainGrid.cellToWorldCenter(currentGrid, maximumX, y)
	assert(firstCenter ~= nil and lastCenter ~= nil, "collision run must be in bounds")

	local part = Instance.new("Part")
	part.Name = if code == TerrainGrid.Codes.Indestructible
		then "BoundaryRun"
		elseif code == TerrainGrid.Codes.Hazard then "HazardRun"
		else "SolidRun"
	part.Size = Vector3.new(width * currentGrid.cellSize, currentGrid.cellSize, TERRAIN_DEPTH)
	part.CFrame =
		CFrame.new((firstCenter.X + lastCenter.X) * 0.5, firstCenter.Y, GameConfig.combatPlaneZ)
	configureCollisionPart(part, code)
	part.Parent = parent
end

local function buildChunk(currentGrid: Grid, chunkX: number, chunkY: number): Folder
	local name = chunkName(chunkX, chunkY)
	local chunk = Instance.new("Folder")
	chunk.Name = name
	chunk:SetAttribute("ChunkX", chunkX)
	chunk:SetAttribute("ChunkY", chunkY)

	local minimumX = (chunkX - 1) * CHUNK_SIZE + 1
	local minimumY = (chunkY - 1) * CHUNK_SIZE + 1
	local maximumX = math.min(currentGrid.width, minimumX + CHUNK_SIZE - 1)
	local maximumY = math.min(currentGrid.height, minimumY + CHUNK_SIZE - 1)
	if minimumX <= maximumX and minimumY <= maximumY then
		for y = minimumY, maximumY do
			local runStart: number? = nil
			local runCode: number? = nil
			for x = minimumX, maximumX + 1 do
				local code = if x <= maximumX
					then currentGrid._cells[(y - 1) * currentGrid.width + x]
					else TerrainGrid.Codes.Empty
				if code == TerrainGrid.Codes.Empty then
					if runStart and runCode then
						createCollisionRun(chunk, currentGrid, y, runStart, x - 1, runCode)
						runStart = nil
						runCode = nil
					end
				elseif runStart == nil then
					runStart = x
					runCode = code
				elseif code ~= runCode then
					assert(runCode ~= nil, "terrain collision run must have a code")
					createCollisionRun(chunk, currentGrid, y, runStart, x - 1, runCode)
					runStart = x
					runCode = code
				end
			end
		end
	end

	return chunk
end

local function replaceChunk(chunk: Folder)
	local root = collisionRoot
	assert(root ~= nil, "terrain collision root must exist")

	local existing = root:FindFirstChild(chunk.Name)
	chunk.Parent = root
	if existing then
		existing:Destroy()
	end
end

local function rebuildChunk(chunkX: number, chunkY: number)
	local currentGrid = grid
	if not currentGrid or not collisionRoot then
		return
	end

	replaceChunk(buildChunk(currentGrid, chunkX, chunkY))
end

local function rebuildAllChunks()
	local currentGrid = grid
	if not currentGrid then
		return
	end

	local chunkColumns = math.ceil(currentGrid.width / CHUNK_SIZE)
	local chunkRows = math.ceil(currentGrid.height / CHUNK_SIZE)
	for chunkY = 1, chunkRows do
		for chunkX = 1, chunkColumns do
			rebuildChunk(chunkX, chunkY)
		end
	end
end

local function dirtyChunksFor(deltas: { CellDelta }): { [string]: { x: number, y: number } }
	local currentGrid = grid
	assert(currentGrid ~= nil, "terrain grid must exist")

	local dirty: { [string]: { x: number, y: number } } = {}
	for _, delta in deltas do
		local zeroBased = delta.index - 1
		local cellX = zeroBased % currentGrid.width + 1
		local cellY = math.floor(zeroBased / currentGrid.width) + 1
		local chunkX = math.floor((cellX - 1) / CHUNK_SIZE) + 1
		local chunkY = math.floor((cellY - 1) / CHUNK_SIZE) + 1
		dirty[chunkKey(chunkX, chunkY)] = {
			x = chunkX,
			y = chunkY,
		}
	end
	return dirty
end

local function updateDiagnostics()
	local currentGrid = grid
	local root = collisionRoot
	if not currentGrid or not root then
		return
	end

	root:SetAttribute("TerrainRevision", revision)
	root:SetAttribute("GridWidth", currentGrid.width)
	root:SetAttribute("GridHeight", currentGrid.height)
	root:SetAttribute("CellSize", currentGrid.cellSize)
	root:SetAttribute("ChunkSize", CHUNK_SIZE)
	root:SetAttribute("TerrainDepth", TERRAIN_DEPTH)
	Workspace:SetAttribute("CritterClashTerrainRevision", revision)
	Workspace:SetAttribute("CritterClashTerrainResetCount", resetCount)
end

local function sendSnapshot(player: Player)
	local currentGrid = grid
	local currentRemotes = remotes
	if not currentGrid or not currentRemotes or player.Parent ~= Players then
		return
	end

	currentRemotes.terrainEvent:FireClient(player, "Snapshot", {
		revision = revision,
		chunkSize = CHUNK_SIZE,
		depth = TERRAIN_DEPTH,
		snapshot = TerrainGrid.snapshot(currentGrid),
	})
end

local function commitDeltas(deltas: { CellDelta }): number
	if #deltas == 0 then
		return 0
	end
	if #deltas > MAX_EDITED_CELLS then
		warn("[CritterClash] Terrain edit rejected because it exceeded the cell safety cap")
		return 0
	end

	local currentGrid = grid
	if not currentGrid then
		return 0
	end
	local dirtyChunks = dirtyChunksFor(deltas)
	local rollback: { CellDelta } = table.create(#deltas)
	for index, delta in deltas do
		rollback[index] = {
			index = delta.index,
			code = currentGrid._cells[delta.index],
		}
	end

	local applied, applyError = pcall(TerrainGrid.applyDelta, currentGrid, deltas)
	if not applied then
		warn(
			string.format("[CritterClash] Terrain edit validation failed: %s", tostring(applyError))
		)
		return 0
	end

	local replacements: { Folder } = {}
	local built, buildError = pcall(function()
		for _, coordinate in dirtyChunks do
			table.insert(replacements, buildChunk(currentGrid, coordinate.x, coordinate.y))
		end
	end)
	if not built then
		TerrainGrid.applyDelta(currentGrid, rollback)
		warn(
			string.format(
				"[CritterClash] Terrain collision staging failed: %s",
				tostring(buildError)
			)
		)
		for _, replacement in replacements do
			replacement:Destroy()
		end
		return 0
	end

	local replaced, replaceError = pcall(function()
		for _, replacement in replacements do
			replaceChunk(replacement)
		end
	end)
	if not replaced then
		TerrainGrid.applyDelta(currentGrid, rollback)
		for _, replacement in replacements do
			if replacement.Parent == nil then
				replacement:Destroy()
			end
		end
		local recovered = pcall(rebuildAllChunks)
		if not recovered then
			warn("[CritterClash] Terrain collision recovery failed")
		end
		warn(
			string.format(
				"[CritterClash] Terrain collision replacement failed: %s",
				tostring(replaceError)
			)
		)
		return 0
	end

	local baseRevision = revision
	revision += 1
	updateDiagnostics()

	local currentRemotes = remotes
	if currentRemotes then
		local sent, sendError = pcall(function()
			currentRemotes.terrainEvent:FireAllClients("Delta", {
				baseRevision = baseRevision,
				revision = revision,
				deltas = deltas,
			})
		end)
		if not sent then
			warn(
				string.format(
					"[CritterClash] Terrain delta replication failed: %s",
					tostring(sendError)
				)
			)
			for _, player in Players:GetPlayers() do
				task.defer(sendSnapshot, player)
			end
		end
	end
	return #deltas
end

type CellBounds = {
	minimumX: number,
	maximumX: number,
	minimumY: number,
	maximumY: number,
}

local function cellBoundsForWorldRectangle(
	currentGrid: Grid,
	minimumWorldX: number,
	maximumWorldX: number,
	minimumWorldY: number,
	maximumWorldY: number
): CellBounds?
	local farWorldX = currentGrid.origin.X + currentGrid.width * currentGrid.cellSize
	local farWorldY = currentGrid.origin.Y + currentGrid.height * currentGrid.cellSize
	if
		maximumWorldX < currentGrid.origin.X
		or minimumWorldX >= farWorldX
		or maximumWorldY < currentGrid.origin.Y
		or minimumWorldY >= farWorldY
	then
		return nil
	end

	return {
		minimumX = math.clamp(
			math.floor((minimumWorldX - currentGrid.origin.X) / currentGrid.cellSize) + 1,
			1,
			currentGrid.width
		),
		maximumX = math.clamp(
			math.floor((maximumWorldX - currentGrid.origin.X) / currentGrid.cellSize) + 1,
			1,
			currentGrid.width
		),
		minimumY = math.clamp(
			math.floor((minimumWorldY - currentGrid.origin.Y) / currentGrid.cellSize) + 1,
			1,
			currentGrid.height
		),
		maximumY = math.clamp(
			math.floor((maximumWorldY - currentGrid.origin.Y) / currentGrid.cellSize) + 1,
			1,
			currentGrid.height
		),
	}
end

local function isDestructibleCode(code: number): boolean
	return code == TerrainGrid.Codes.Solid or code == TerrainGrid.Codes.Hazard
end

local function planCircle(position: Vector3, radius: number): { CellDelta }
	local currentGrid = grid
	if not currentGrid or not isFinitePosition(position) or not isFinite(radius) or radius < 0 then
		return {}
	end

	local boundedRadius = math.min(radius, MAX_CRATER_RADIUS)
	local bounds = cellBoundsForWorldRectangle(
		currentGrid,
		position.X - boundedRadius,
		position.X + boundedRadius,
		position.Y - boundedRadius,
		position.Y + boundedRadius
	)
	if not bounds then
		return {}
	end

	local center = Vector2.new(position.X, position.Y)
	local radiusSquared = boundedRadius * boundedRadius
	local deltas: { CellDelta } = {}
	for y = bounds.minimumY, bounds.maximumY do
		for x = bounds.minimumX, bounds.maximumX do
			local index = TerrainGrid.toIndex(currentGrid, x, y)
			local cellCenter = TerrainGrid.cellToWorldCenter(currentGrid, x, y)
			assert(index ~= nil and cellCenter ~= nil, "planned terrain cell must be in bounds")
			local offset = cellCenter - center
			if
				isDestructibleCode(currentGrid._cells[index])
				and offset:Dot(offset) <= radiusSquared
			then
				table.insert(deltas, {
					index = index,
					code = TerrainGrid.Codes.Empty,
				})
			end
		end
	end
	return deltas
end

function TerrainService.start(networkRemotes: Remotes, arena: Model)
	assert(not started, "TerrainService may only be started once")
	started = true
	remotes = networkRemotes
	grid = createInitialGrid()
	revision = 0
	resetCount = 0

	for _, legacyName in { "Ground", "LeftShelf", "RightShelf" } do
		local legacy = arena:FindFirstChild(legacyName)
		if legacy then
			legacy:Destroy()
		end
	end
	local existingRoot = arena:FindFirstChild(COLLISION_ROOT_NAME)
	if existingRoot then
		existingRoot:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = COLLISION_ROOT_NAME
	root.Parent = arena
	collisionRoot = root
	rebuildAllChunks()
	updateDiagnostics()

	networkRemotes.requestTerrainSnapshot.OnServerEvent:Connect(function(player)
		local now = os.clock()
		local previous = lastSnapshotAt[player]
		if previous and now - previous < SNAPSHOT_COOLDOWN_SECONDS then
			return
		end
		lastSnapshotAt[player] = now
		sendSnapshot(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSnapshotAt[player] = nil
	end)
end

function TerrainService.applyImpact(position: Vector3, radius: number): number
	return commitDeltas(planCircle(position, radius))
end

function TerrainService.reset(): number
	local currentRoot = collisionRoot
	local currentGrid = grid
	assert(
		started and currentGrid ~= nil and currentRoot ~= nil,
		"TerrainService must be started before reset"
	)
	local rootParent = currentRoot.Parent
	assert(rootParent ~= nil, "terrain collision root must have a parent")

	local nextGrid = createInitialGrid()
	local nextRoot = Instance.new("Folder")
	nextRoot.Name = COLLISION_ROOT_NAME

	local built, buildError = pcall(function()
		local chunkColumns = math.ceil(nextGrid.width / CHUNK_SIZE)
		local chunkRows = math.ceil(nextGrid.height / CHUNK_SIZE)
		for chunkY = 1, chunkRows do
			for chunkX = 1, chunkColumns do
				buildChunk(nextGrid, chunkX, chunkY).Parent = nextRoot
			end
		end
	end)
	if not built then
		nextRoot:Destroy()
		error(string.format("terrain reset staging failed: %s", tostring(buildError)))
	end

	-- Parent and publish the complete replacement while the old root is still
	-- available for rollback. Only retire old collision after diagnostics commit.
	local previousRevision = revision
	local previousResetCount = resetCount
	local committed, commitError = pcall(function()
		nextRoot.Parent = rootParent
		grid = nextGrid
		collisionRoot = nextRoot
		revision = previousRevision + 1
		resetCount = previousResetCount + 1
		updateDiagnostics()
	end)
	if not committed then
		grid = currentGrid
		collisionRoot = currentRoot
		revision = previousRevision
		resetCount = previousResetCount
		nextRoot:Destroy()
		pcall(updateDiagnostics)
		error(string.format("terrain reset commit failed: %s", tostring(commitError)))
	end
	currentRoot:Destroy()

	for _, player in Players:GetPlayers() do
		local sendError = "unknown snapshot error"
		local sent = xpcall(function()
			sendSnapshot(player)
		end, function(message)
			sendError = tostring(message)
			return message
		end)
		if not sent then
			warn(
				string.format(
					"[CritterClash] Terrain reset snapshot failed for %d: %s",
					player.UserId,
					tostring(sendError)
				)
			)
		end
	end
	return revision
end

function TerrainService.clipDrillEndpoint(startPosition: Vector3, endPosition: Vector3): Vector3
	local currentGrid = grid
	if
		not currentGrid
		or not isFinitePosition(startPosition)
		or not isFinitePosition(endPosition)
	then
		return startPosition
	end

	local displacement = endPosition - startPosition
	local requestedDistance = displacement.Magnitude
	if requestedDistance <= 0 then
		return startPosition
	end

	local distance = math.min(requestedDistance, MAX_DRILL_LENGTH)
	local direction = displacement.Unit
	local minimumX = currentGrid.origin.X
	local minimumY = currentGrid.origin.Y
	local maximumX = minimumX + currentGrid.width * currentGrid.cellSize
	local maximumY = minimumY + currentGrid.height * currentGrid.cellSize
	if
		startPosition.X < minimumX
		or startPosition.X >= maximumX
		or startPosition.Y < minimumY
		or startPosition.Y >= maximumY
	then
		return startPosition
	end

	if direction.X > 0 then
		distance = math.min(distance, (maximumX - startPosition.X) / direction.X)
	elseif direction.X < 0 then
		distance = math.min(distance, (minimumX - startPosition.X) / direction.X)
	end
	if direction.Y > 0 then
		distance = math.min(distance, (maximumY - startPosition.Y) / direction.Y)
	elseif direction.Y < 0 then
		distance = math.min(distance, (minimumY - startPosition.Y) / direction.Y)
	end
	distance = math.max(0, distance)
	if distance <= 0 then
		return startPosition
	end

	local indestructibleParts = CollectionService:GetTagged(INDESTRUCTIBLE_TAG)
	if #indestructibleParts > 0 then
		local parameters = RaycastParams.new()
		parameters.FilterType = Enum.RaycastFilterType.Include
		parameters.FilterDescendantsInstances = indestructibleParts
		parameters.IgnoreWater = true
		local result = Workspace:Raycast(startPosition, direction * distance, parameters)
		if result then
			local hitDistance = (result.Position - startPosition):Dot(direction)
			local safeDistance = math.clamp(hitDistance - 0.02, 0, distance)
			return startPosition + direction * safeDistance
		end
	end

	return startPosition + direction * distance
end

function TerrainService.applyDrillPath(
	startPosition: Vector3,
	endPosition: Vector3,
	radius: number
): number
	if
		not grid
		or not isFinitePosition(startPosition)
		or not isFinitePosition(endPosition)
		or not isFinite(radius)
		or radius < 0
	then
		return 0
	end

	local clippedEnd = TerrainService.clipDrillEndpoint(startPosition, endPosition)
	local startOnPlane = Vector2.new(startPosition.X, startPosition.Y)
	local endOnPlane = Vector2.new(clippedEnd.X, clippedEnd.Y)
	local path = endOnPlane - startOnPlane
	local pathLength = path.Magnitude
	if pathLength <= 0 then
		return 0
	end
	local direction = path.Unit
	local drillRadius = math.min(radius, MAX_DRILL_RADIUS)
	local bounds = cellBoundsForWorldRectangle(
		grid :: Grid,
		math.min(startOnPlane.X, endOnPlane.X) - drillRadius,
		math.max(startOnPlane.X, endOnPlane.X) + drillRadius,
		math.min(startOnPlane.Y, endOnPlane.Y) - drillRadius,
		math.max(startOnPlane.Y, endOnPlane.Y) + drillRadius
	)
	if not bounds then
		return 0
	end

	local currentGrid = grid :: Grid
	local deltas: { CellDelta } = {}
	local radiusSquared = drillRadius * drillRadius
	for y = bounds.minimumY, bounds.maximumY do
		for x = bounds.minimumX, bounds.maximumX do
			local index = TerrainGrid.toIndex(currentGrid, x, y)
			local cellCenter = TerrainGrid.cellToWorldCenter(currentGrid, x, y)
			assert(index ~= nil and cellCenter ~= nil, "planned drill cell must be in bounds")
			local fromStart = cellCenter - startOnPlane
			local distanceAlongPath = fromStart:Dot(direction)
			local closestPoint = startOnPlane + direction * distanceAlongPath
			local perpendicular = cellCenter - closestPoint
			if
				distanceAlongPath >= 0
				and distanceAlongPath <= pathLength
				and perpendicular:Dot(perpendicular) <= radiusSquared
				and isDestructibleCode(currentGrid._cells[index])
			then
				table.insert(deltas, {
					index = index,
					code = TerrainGrid.Codes.Empty,
				})
			end
		end
	end

	return commitDeltas(deltas)
end

function TerrainService.isTerrainInstance(instance: Instance): boolean
	local root = collisionRoot
	return root ~= nil and instance:IsDescendantOf(root)
end

function TerrainService.isIndestructibleInstance(instance: Instance): boolean
	return TerrainService.isTerrainInstance(instance)
		and instance:GetAttribute("TerrainCode") == TerrainGrid.Codes.Indestructible
end

function TerrainService.findSupportBelow(
	minimumWorldX: number,
	maximumWorldX: number,
	maximumWorldY: number,
	maximumDrop: number,
	penetrationTolerance: number?
): SupportResult?
	local currentGrid = grid
	if not currentGrid then
		return nil
	end
	return TerrainGrid.findSupportBelow(
		currentGrid,
		minimumWorldX,
		maximumWorldX,
		maximumWorldY,
		maximumDrop,
		penetrationTolerance
	)
end

function TerrainService.setHazardContactHandler(handler: (Model) -> ())
	assert(hazardContactHandler == nil, "hazard contact handler may only be registered once")
	hazardContactHandler = handler
end

function TerrainService.getRevision(): number
	return revision
end

return TerrainService
