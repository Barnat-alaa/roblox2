--!strict

-- Pure logical 2D terrain storage. World coordinates use the X/Y combat plane;
-- callers convert Vector3 positions to Vector2 before using this module. Cells
-- are one-based and stored row-major so snapshots and deltas remain compact.

local TerrainGrid = {}

export type CellKind = "Empty" | "Solid" | "Hazard" | "Indestructible"

export type Config = {
	width: number,
	height: number,
	cellSize: number,
	origin: Vector2?,
	defaultKind: CellKind?,
}

export type Grid = {
	width: number,
	height: number,
	cellSize: number,
	origin: Vector2,
	_cells: { number },
}

export type CellDelta = {
	index: number,
	code: number,
}

export type Snapshot = {
	formatVersion: number,
	width: number,
	height: number,
	cellSize: number,
	originX: number,
	originY: number,
	cells: { number },
}

export type SupportResult = {
	surfaceY: number,
	kind: CellKind,
}

local FORMAT_VERSION = 1
local MAX_DIMENSION = 4_096
local MAX_CELLS = 262_144

local EMPTY = 0
local SOLID = 1
local HAZARD = 2
local INDESTRUCTIBLE = 3

TerrainGrid.FORMAT_VERSION = FORMAT_VERSION
TerrainGrid.MAX_DIMENSION = MAX_DIMENSION
TerrainGrid.MAX_CELLS = MAX_CELLS
TerrainGrid.Codes = table.freeze({
	Empty = EMPTY,
	Solid = SOLID,
	Hazard = HAZARD,
	Indestructible = INDESTRUCTIBLE,
})
TerrainGrid.Kinds = table.freeze({
	Empty = "Empty",
	Solid = "Solid",
	Hazard = "Hazard",
	Indestructible = "Indestructible",
})

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isPositiveInteger(value: number): boolean
	return isFinite(value) and value >= 1 and value == math.floor(value)
end

local function codeForKind(kind: CellKind): number
	if kind == "Empty" then
		return EMPTY
	elseif kind == "Solid" then
		return SOLID
	elseif kind == "Hazard" then
		return HAZARD
	elseif kind == "Indestructible" then
		return INDESTRUCTIBLE
	end

	error("unsupported terrain cell kind")
end

local function kindForCode(code: number): CellKind?
	if code == EMPTY then
		return "Empty"
	elseif code == SOLID then
		return "Solid"
	elseif code == HAZARD then
		return "Hazard"
	elseif code == INDESTRUCTIBLE then
		return "Indestructible"
	end

	return nil
end

local function isFiniteVector2(value: Vector2): boolean
	return isFinite(value.X) and isFinite(value.Y)
end

function TerrainGrid.validateConfig(config: Config): (boolean, string?)
	if
		not isPositiveInteger(config.width)
		or config.width > MAX_DIMENSION
		or not isPositiveInteger(config.height)
		or config.height > MAX_DIMENSION
	then
		return false, string.format("width and height must be integers in [1, %d]", MAX_DIMENSION)
	end

	if config.width * config.height > MAX_CELLS then
		return false, string.format("terrain grid must contain at most %d cells", MAX_CELLS)
	end

	if not isFinite(config.cellSize) or config.cellSize <= 0 then
		return false, "cellSize must be finite and positive"
	end

	local origin = config.origin or Vector2.zero
	if not isFiniteVector2(origin) then
		return false, "origin must be finite"
	end

	if config.defaultKind ~= nil then
		local kindAccepted = pcall(codeForKind, config.defaultKind)
		if not kindAccepted then
			return false, "defaultKind is unsupported"
		end
	end

	return true, nil
end

function TerrainGrid.create(config: Config): Grid
	local valid, reason = TerrainGrid.validateConfig(config)
	assert(valid, reason or "invalid terrain grid config")

	local defaultCode = codeForKind(config.defaultKind or "Empty")
	local cellCount = config.width * config.height
	local cells = table.create(cellCount, defaultCode) :: { number }

	return {
		width = config.width,
		height = config.height,
		cellSize = config.cellSize,
		origin = config.origin or Vector2.zero,
		_cells = cells,
	}
end

function TerrainGrid.isInBounds(grid: Grid, x: number, y: number): boolean
	return isPositiveInteger(x) and x <= grid.width and isPositiveInteger(y) and y <= grid.height
end

function TerrainGrid.toIndex(grid: Grid, x: number, y: number): number?
	if not TerrainGrid.isInBounds(grid, x, y) then
		return nil
	end

	return (y - 1) * grid.width + x
end

function TerrainGrid.fromIndex(grid: Grid, index: number): (number?, number?)
	if not isPositiveInteger(index) or index > grid.width * grid.height then
		return nil, nil
	end

	local zeroBased = index - 1
	local x = zeroBased % grid.width + 1
	local y = math.floor(zeroBased / grid.width) + 1
	return x, y
end

function TerrainGrid.getCell(grid: Grid, x: number, y: number): CellKind?
	local index = TerrainGrid.toIndex(grid, x, y)
	if not index then
		return nil
	end

	local kind = kindForCode(grid._cells[index])
	if kind == nil then
		error("terrain grid contains an invalid cell code")
	end
	return kind :: CellKind
end

-- Returns nil for an out-of-bounds or no-op write. A returned delta contains
-- exactly the row-major index and new compact numeric value needed by a replica.
function TerrainGrid.setCell(grid: Grid, x: number, y: number, kind: CellKind): CellDelta?
	local index = TerrainGrid.toIndex(grid, x, y)
	if not index then
		return nil
	end

	local code = codeForKind(kind)
	if grid._cells[index] == code then
		return nil
	end

	grid._cells[index] = code
	return {
		index = index,
		code = code,
	}
end

-- World bounds are half-open: origin is included and the far width/height edges
-- are excluded. This makes every in-bounds point map to exactly one cell.
function TerrainGrid.worldToCell(grid: Grid, worldPosition: Vector2): (number?, number?)
	if not isFiniteVector2(worldPosition) then
		return nil, nil
	end

	local relativeX = worldPosition.X - grid.origin.X
	local relativeY = worldPosition.Y - grid.origin.Y
	local worldWidth = grid.width * grid.cellSize
	local worldHeight = grid.height * grid.cellSize
	if relativeX < 0 or relativeX >= worldWidth or relativeY < 0 or relativeY >= worldHeight then
		return nil, nil
	end

	return math.floor(relativeX / grid.cellSize) + 1, math.floor(relativeY / grid.cellSize) + 1
end

function TerrainGrid.cellToWorldCenter(grid: Grid, x: number, y: number): Vector2?
	if not TerrainGrid.isInBounds(grid, x, y) then
		return nil
	end

	return grid.origin + Vector2.new((x - 0.5) * grid.cellSize, (y - 0.5) * grid.cellSize)
end

-- Finds the first authoritative terrain surface below a horizontal footprint.
-- A Hazard is returned rather than skipped so runtime settling can eliminate a
-- falling combatant instead of snapping it through danger onto solid below.
function TerrainGrid.findSupportBelow(
	grid: Grid,
	minimumWorldX: number,
	maximumWorldX: number,
	maximumWorldY: number,
	maximumDrop: number,
	penetrationTolerance: number?
): SupportResult?
	if
		not isFinite(minimumWorldX)
		or not isFinite(maximumWorldX)
		or not isFinite(maximumWorldY)
		or not isFinite(maximumDrop)
		or maximumDrop < 0
		or minimumWorldX > maximumWorldX
	then
		return nil
	end

	local tolerance = penetrationTolerance or 0
	if not isFinite(tolerance) or tolerance < 0 then
		return nil
	end

	local worldMinimumX = grid.origin.X
	local worldMaximumX = grid.origin.X + grid.width * grid.cellSize
	local clippedMinimumX = math.max(minimumWorldX, worldMinimumX)
	local clippedMaximumX = math.min(maximumWorldX, worldMaximumX)
	if clippedMinimumX >= worldMaximumX or clippedMaximumX <= worldMinimumX then
		return nil
	end

	-- Treat the footprint's right edge as exclusive when it lies exactly on a
	-- cell boundary, matching worldToCell's half-open convention.
	local edgeEpsilon = math.min(grid.cellSize * 1e-6, 1e-5)
	local firstX =
		math.clamp(math.floor((clippedMinimumX - grid.origin.X) / grid.cellSize) + 1, 1, grid.width)
	local lastSampleX = math.max(clippedMinimumX, clippedMaximumX - edgeEpsilon)
	local lastX =
		math.clamp(math.floor((lastSampleX - grid.origin.X) / grid.cellSize) + 1, 1, grid.width)

	local highestAllowedSurface = maximumWorldY + tolerance
	local lowestAllowedSurface = maximumWorldY - maximumDrop
	local firstY =
		math.min(grid.height, math.floor((highestAllowedSurface - grid.origin.Y) / grid.cellSize))
	if firstY < 1 then
		return nil
	end

	for y = firstY, 1, -1 do
		local surfaceY = grid.origin.Y + y * grid.cellSize
		if surfaceY < lowestAllowedSurface then
			break
		end
		if surfaceY <= highestAllowedSurface then
			local sawSolid = false
			local sawIndestructible = false
			local sawHazard = false
			for x = firstX, lastX do
				local kind = TerrainGrid.getCell(grid, x, y)
				if kind == "Indestructible" then
					sawIndestructible = true
				elseif kind == "Solid" then
					sawSolid = true
				elseif kind == "Hazard" then
					sawHazard = true
				end
			end

			if sawIndestructible or sawSolid then
				return {
					surfaceY = surfaceY,
					kind = if sawIndestructible then "Indestructible" else "Solid",
				}
			end
			if sawHazard then
				return {
					surfaceY = surfaceY,
					kind = "Hazard",
				}
			end
		end
	end

	return nil
end

-- A cell is inside a crater when its world-space centre is inside or on the
-- circle. Solid and Hazard cells become Empty; Empty and Indestructible cells
-- remain unchanged. The row-major scan makes every returned index unique and
-- deterministic, while the candidate bounds avoid scanning the whole map.
function TerrainGrid.destroyCircle(grid: Grid, worldCenter: Vector2, radius: number): { CellDelta }
	assert(isFiniteVector2(worldCenter), "worldCenter must be finite")
	assert(isFinite(radius) and radius >= 0, "radius must be finite and non-negative")

	local changed: { CellDelta } = {}
	local minimumX =
		math.max(1, math.floor((worldCenter.X - radius - grid.origin.X) / grid.cellSize) + 1)
	local maximumX = math.min(
		grid.width,
		math.floor((worldCenter.X + radius - grid.origin.X) / grid.cellSize) + 1
	)
	local minimumY =
		math.max(1, math.floor((worldCenter.Y - radius - grid.origin.Y) / grid.cellSize) + 1)
	local maximumY = math.min(
		grid.height,
		math.floor((worldCenter.Y + radius - grid.origin.Y) / grid.cellSize) + 1
	)

	if minimumX > maximumX or minimumY > maximumY then
		return changed
	end

	local radiusSquared = radius * radius
	for y = minimumY, maximumY do
		for x = minimumX, maximumX do
			local cellCenter = TerrainGrid.cellToWorldCenter(grid, x, y)
			assert(cellCenter ~= nil, "candidate terrain cell must be in bounds")
			local offset = cellCenter - worldCenter
			if offset:Dot(offset) <= radiusSquared then
				local index = TerrainGrid.toIndex(grid, x, y)
				assert(index ~= nil, "candidate terrain cell must have an index")
				local code = grid._cells[index]
				if code ~= EMPTY and code ~= INDESTRUCTIBLE then
					grid._cells[index] = EMPTY
					table.insert(changed, {
						index = index,
						code = EMPTY,
					})
				end
			end
		end
	end

	return changed
end

function TerrainGrid.snapshot(grid: Grid): Snapshot
	return {
		formatVersion = FORMAT_VERSION,
		width = grid.width,
		height = grid.height,
		cellSize = grid.cellSize,
		originX = grid.origin.X,
		originY = grid.origin.Y,
		cells = table.clone(grid._cells),
	}
end

function TerrainGrid.fromSnapshot(snapshot: Snapshot): Grid
	assert(snapshot.formatVersion == FORMAT_VERSION, "unsupported terrain snapshot format")

	local config: Config = {
		width = snapshot.width,
		height = snapshot.height,
		cellSize = snapshot.cellSize,
		origin = Vector2.new(snapshot.originX, snapshot.originY),
		defaultKind = "Empty",
	}
	local valid, reason = TerrainGrid.validateConfig(config)
	assert(valid, reason or "invalid terrain snapshot config")

	local expectedCellCount = snapshot.width * snapshot.height
	assert(#snapshot.cells == expectedCellCount, "terrain snapshot has an invalid cell count")

	local cells = table.create(expectedCellCount) :: { number }
	for index, code in snapshot.cells do
		assert(isPositiveInteger(index) and index <= expectedCellCount, "invalid snapshot index")
		assert(kindForCode(code) ~= nil, "terrain snapshot contains an invalid cell code")
		cells[index] = code
	end

	return {
		width = snapshot.width,
		height = snapshot.height,
		cellSize = snapshot.cellSize,
		origin = Vector2.new(snapshot.originX, snapshot.originY),
		_cells = cells,
	}
end

-- Deltas are validated as one atomic batch before mutation. Duplicate indices
-- are rejected so a malformed batch cannot make ordering affect the final state.
-- The return value counts actual changes; valid no-op entries are harmless.
function TerrainGrid.applyDelta(grid: Grid, deltas: { CellDelta }): number
	local seen: { [number]: boolean } = {}
	for _, delta in deltas do
		assert(
			isPositiveInteger(delta.index) and delta.index <= grid.width * grid.height,
			"terrain delta index is out of bounds"
		)
		assert(kindForCode(delta.code) ~= nil, "terrain delta contains an invalid cell code")
		assert(not seen[delta.index], "terrain delta contains a duplicate index")
		seen[delta.index] = true
	end

	local changedCount = 0
	for _, delta in deltas do
		if grid._cells[delta.index] ~= delta.code then
			grid._cells[delta.index] = delta.code
			changedCount += 1
		end
	end

	return changedCount
end

return table.freeze(TerrainGrid)
