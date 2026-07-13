--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TerrainGrid = require(ReplicatedStorage.Shared.Simulation.TerrainGrid)

type RevisionedReplica = {
	grid: TerrainGrid.Grid,
	revision: number,
}

return function()
	local testEnvironment: any = getfenv()
	local describe = testEnvironment.describe
	local it = testEnvironment.it
	local expect = testEnvironment.expect

	local function createGrid(
		width: number,
		height: number,
		defaultKind: TerrainGrid.CellKind?
	): TerrainGrid.Grid
		return TerrainGrid.create({
			width = width,
			height = height,
			cellSize = 4,
			origin = Vector2.zero,
			defaultKind = defaultKind or "Empty",
		})
	end

	local function expectSameSnapshot(leftGrid: TerrainGrid.Grid, rightGrid: TerrainGrid.Grid)
		local left = TerrainGrid.snapshot(leftGrid)
		local right = TerrainGrid.snapshot(rightGrid)

		expect(right.formatVersion).to.equal(left.formatVersion)
		expect(right.width).to.equal(left.width)
		expect(right.height).to.equal(left.height)
		expect(right.cellSize).to.equal(left.cellSize)
		expect(right.originX).to.equal(left.originX)
		expect(right.originY).to.equal(left.originY)
		expect(#right.cells).to.equal(#left.cells)
		for index, code in left.cells do
			expect(right.cells[index]).to.equal(code)
		end
	end

	local function collectDirtyChunks(
		grid: TerrainGrid.Grid,
		deltas: { TerrainGrid.CellDelta },
		chunkSize: number
	): { number }
		assert(chunkSize >= 1 and chunkSize == math.floor(chunkSize), "chunkSize must be positive")

		local chunksWide = math.ceil(grid.width / chunkSize)
		local seen: { [number]: boolean } = {}
		local dirty: { number } = {}
		for _, delta in deltas do
			local x, y = TerrainGrid.fromIndex(grid, delta.index)
			assert(x ~= nil and y ~= nil, "dirty-cell delta must be in bounds")
			local chunkX = math.floor((x - 1) / chunkSize) + 1
			local chunkY = math.floor((y - 1) / chunkSize) + 1
			local chunkIndex = (chunkY - 1) * chunksWide + chunkX
			if not seen[chunkIndex] then
				seen[chunkIndex] = true
				table.insert(dirty, chunkIndex)
			end
		end

		table.sort(dirty)
		return dirty
	end

	-- TerrainGrid deliberately owns compact values rather than network revisions.
	-- This helper captures the service contract: only a contiguous next revision
	-- may mutate a replica, and a failed batch leaves its revision unchanged.
	local function applyRevisioned(
		replica: RevisionedReplica,
		baseRevision: number,
		revision: number,
		deltas: { TerrainGrid.CellDelta }
	): (boolean, string?)
		if revision <= replica.revision then
			return false, "stale_revision"
		end
		if baseRevision ~= replica.revision or revision ~= baseRevision + 1 then
			return false, "revision_gap"
		end

		local validBatch = pcall(function()
			TerrainGrid.applyDelta(replica.grid, deltas)
		end)
		if not validBatch then
			return false, "invalid_delta"
		end

		replica.revision = revision
		return true, nil
	end

	describe("Terrain replication contract", function()
		it("replicates compact deterministic crater deltas", function()
			local authority = createGrid(6, 4, "Solid")
			local replica = TerrainGrid.fromSnapshot(TerrainGrid.snapshot(authority))
			local deltas = TerrainGrid.destroyCircle(authority, Vector2.new(10, 6), 4)
			local previousIndex = 0

			expect(#deltas).to.equal(5)
			for _, delta in deltas do
				local fieldCount = 0
				for field in delta do
					fieldCount += 1
					expect(field == "index" or field == "code").to.equal(true)
				end

				expect(fieldCount).to.equal(2)
				expect(delta.index > previousIndex).to.equal(true)
				expect(delta.code).to.equal(TerrainGrid.Codes.Empty)
				previousIndex = delta.index
			end

			expect(TerrainGrid.applyDelta(replica, deltas)).to.equal(#deltas)
			expect(TerrainGrid.applyDelta(replica, deltas)).to.equal(0)
			expectSameSnapshot(authority, replica)
		end)

		it("rejects stale, skipped, and invalid batches before advancing revision", function()
			local replica: RevisionedReplica = {
				grid = createGrid(2, 2, "Empty"),
				revision = 0,
			}
			local accepted, reason = applyRevisioned(replica, 0, 1, {
				{
					index = 1,
					code = TerrainGrid.Codes.Solid,
				},
			})

			expect(accepted).to.equal(true)
			expect(reason).to.equal(nil)
			expect(replica.revision).to.equal(1)
			expect(TerrainGrid.getCell(replica.grid, 1, 1)).to.equal("Solid")

			local staleAccepted, staleReason = applyRevisioned(replica, 0, 1, {
				{
					index = 2,
					code = TerrainGrid.Codes.Hazard,
				},
			})
			expect(staleAccepted).to.equal(false)
			expect(staleReason).to.equal("stale_revision")
			expect(replica.revision).to.equal(1)
			expect(TerrainGrid.getCell(replica.grid, 2, 1)).to.equal("Empty")

			local gapAccepted, gapReason = applyRevisioned(replica, 2, 3, {
				{
					index = 2,
					code = TerrainGrid.Codes.Hazard,
				},
			})
			expect(gapAccepted).to.equal(false)
			expect(gapReason).to.equal("revision_gap")
			expect(replica.revision).to.equal(1)
			expect(TerrainGrid.getCell(replica.grid, 2, 1)).to.equal("Empty")

			local invalidAccepted, invalidReason = applyRevisioned(replica, 1, 2, {
				{
					index = 2,
					code = TerrainGrid.Codes.Hazard,
				},
				{
					index = 5,
					code = TerrainGrid.Codes.Solid,
				},
			})
			expect(invalidAccepted).to.equal(false)
			expect(invalidReason).to.equal("invalid_delta")
			expect(replica.revision).to.equal(1)
			expect(TerrainGrid.getCell(replica.grid, 2, 1)).to.equal("Empty")
		end)

		it("keeps overlapping crater batches idempotent on a replica", function()
			local authority = createGrid(7, 1, "Solid")
			local replica = TerrainGrid.fromSnapshot(TerrainGrid.snapshot(authority))

			local first = TerrainGrid.destroyCircle(authority, Vector2.new(10, 2), 4)
			local second = TerrainGrid.destroyCircle(authority, Vector2.new(14, 2), 4)

			expect(#first).to.equal(3)
			expect(#second).to.equal(1)
			expect(TerrainGrid.applyDelta(replica, first)).to.equal(3)
			expect(TerrainGrid.applyDelta(replica, second)).to.equal(1)
			expect(TerrainGrid.applyDelta(replica, first)).to.equal(0)
			expect(TerrainGrid.applyDelta(replica, second)).to.equal(0)
			expectSameSnapshot(authority, replica)
		end)

		it("never includes protected cells in destruction deltas", function()
			local authority = createGrid(4, 2, "Solid")
			TerrainGrid.setCell(authority, 2, 1, "Indestructible")
			TerrainGrid.setCell(authority, 3, 2, "Indestructible")
			local replica = TerrainGrid.fromSnapshot(TerrainGrid.snapshot(authority))
			local protectedFirst = TerrainGrid.toIndex(authority, 2, 1)
			local protectedSecond = TerrainGrid.toIndex(authority, 3, 2)

			local deltas = TerrainGrid.destroyCircle(authority, Vector2.new(8, 4), 20)
			expect(#deltas).to.equal(6)
			for _, delta in deltas do
				expect(delta.index == protectedFirst).to.equal(false)
				expect(delta.index == protectedSecond).to.equal(false)
			end

			expect(TerrainGrid.applyDelta(replica, deltas)).to.equal(6)
			expect(TerrainGrid.getCell(replica, 2, 1)).to.equal("Indestructible")
			expect(TerrainGrid.getCell(replica, 3, 2)).to.equal("Indestructible")
			expectSameSnapshot(authority, replica)
		end)

		it("deduplicates dirty chunks across an eight-cell boundary", function()
			local authority = createGrid(16, 16, "Solid")
			local deltas = TerrainGrid.destroyCircle(authority, Vector2.new(32, 32), 3)
			local repeatedDeltas: { TerrainGrid.CellDelta } = {}

			expect(#deltas).to.equal(4)
			for _, delta in deltas do
				table.insert(repeatedDeltas, delta)
				table.insert(repeatedDeltas, delta)
			end

			local dirtyChunks = collectDirtyChunks(authority, repeatedDeltas, 8)
			expect(#dirtyChunks).to.equal(4)
			expect(dirtyChunks[1]).to.equal(1)
			expect(dirtyChunks[2]).to.equal(2)
			expect(dirtyChunks[3]).to.equal(3)
			expect(dirtyChunks[4]).to.equal(4)
		end)

		it("converts a world impact to the same logical crater on every replica", function()
			local authority = TerrainGrid.create({
				width = 3,
				height = 3,
				cellSize = 4,
				origin = Vector2.new(-12, -8),
				defaultKind = "Solid",
			})
			local replica = TerrainGrid.fromSnapshot(TerrainGrid.snapshot(authority))
			local impact = Vector3.new(-6, -2, 99)
			local impactOnPlane = Vector2.new(impact.X, impact.Y)
			local x, y = TerrainGrid.worldToCell(authority, impactOnPlane)

			expect(x).to.equal(2)
			expect(y).to.equal(2)
			expect(TerrainGrid.cellToWorldCenter(authority, x :: number, y :: number)).to.equal(
				impactOnPlane
			)

			local deltas = TerrainGrid.destroyCircle(authority, impactOnPlane, 0)
			expect(#deltas).to.equal(1)
			expect(deltas[1].index).to.equal(TerrainGrid.toIndex(authority, 2, 2))
			expect(TerrainGrid.applyDelta(replica, deltas)).to.equal(1)
			expectSameSnapshot(authority, replica)
		end)

		it("recovers a revision gap from a fresh authoritative snapshot", function()
			local authority = createGrid(4, 1, "Solid")
			local replica: RevisionedReplica = {
				grid = TerrainGrid.fromSnapshot(TerrainGrid.snapshot(authority)),
				revision = 0,
			}

			local revisionOne = TerrainGrid.destroyCircle(authority, Vector2.new(2, 2), 0)
			local revisionOneAccepted = applyRevisioned(replica, 0, 1, revisionOne)
			expect(revisionOneAccepted).to.equal(true)

			TerrainGrid.destroyCircle(authority, Vector2.new(6, 2), 0)
			local revisionThree = TerrainGrid.destroyCircle(authority, Vector2.new(10, 2), 0)
			local accepted, reason = applyRevisioned(replica, 2, 3, revisionThree)
			expect(accepted).to.equal(false)
			expect(reason).to.equal("revision_gap")

			replica.grid = TerrainGrid.fromSnapshot(TerrainGrid.snapshot(authority))
			replica.revision = 3
			expectSameSnapshot(authority, replica.grid)

			local revisionFour = TerrainGrid.destroyCircle(authority, Vector2.new(14, 2), 0)
			local revisionFourAccepted = applyRevisioned(replica, 3, 4, revisionFour)
			expect(revisionFourAccepted).to.equal(true)
			expect(replica.revision).to.equal(4)
			expectSameSnapshot(authority, replica.grid)
		end)
	end)
end
