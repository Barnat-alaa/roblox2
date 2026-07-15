--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TerrainGrid = require(ReplicatedStorage.Shared.Simulation.TerrainGrid)

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

	describe("TerrainGrid coordinates", function()
		it("uses bounded row-major grid indices", function()
			local grid = createGrid(3, 2, "Empty")

			expect(TerrainGrid.toIndex(grid, 1, 1)).to.equal(1)
			expect(TerrainGrid.toIndex(grid, 3, 1)).to.equal(3)
			expect(TerrainGrid.toIndex(grid, 1, 2)).to.equal(4)
			expect(TerrainGrid.toIndex(grid, 3, 2)).to.equal(6)
			expect(TerrainGrid.toIndex(grid, 0, 1)).to.equal(nil)
			expect(TerrainGrid.toIndex(grid, 4, 1)).to.equal(nil)
			expect(TerrainGrid.toIndex(grid, 1.5, 1)).to.equal(nil)

			local x, y = TerrainGrid.fromIndex(grid, 5)
			expect(x).to.equal(2)
			expect(y).to.equal(2)

			local outsideX, outsideY = TerrainGrid.fromIndex(grid, 7)
			expect(outsideX).to.equal(nil)
			expect(outsideY).to.equal(nil)
		end)

		it("converts configurable world bounds and cell centres", function()
			local grid = TerrainGrid.create({
				width = 4,
				height = 3,
				cellSize = 4,
				origin = Vector2.new(-8, -4),
				defaultKind = "Empty",
			})

			local firstX, firstY = TerrainGrid.worldToCell(grid, Vector2.new(-8, -4))
			expect(firstX).to.equal(1)
			expect(firstY).to.equal(1)

			local middleX, middleY = TerrainGrid.worldToCell(grid, Vector2.new(0, 4))
			expect(middleX).to.equal(3)
			expect(middleY).to.equal(3)

			expect(TerrainGrid.cellToWorldCenter(grid, 1, 1)).to.equal(Vector2.new(-6, -2))
			expect(TerrainGrid.cellToWorldCenter(grid, 4, 3)).to.equal(Vector2.new(6, 6))
			expect(TerrainGrid.cellToWorldCenter(grid, 5, 3)).to.equal(nil)

			local farEdgeX, farEdgeY = TerrainGrid.worldToCell(grid, Vector2.new(8, 0))
			expect(farEdgeX).to.equal(nil)
			expect(farEdgeY).to.equal(nil)

			local beforeOriginX, beforeOriginY =
				TerrainGrid.worldToCell(grid, Vector2.new(-8.001, -4))
			expect(beforeOriginX).to.equal(nil)
			expect(beforeOriginY).to.equal(nil)
		end)
	end)

	describe("TerrainGrid support queries", function()
		it("finds solid and indestructible support beneath a footprint", function()
			local grid = createGrid(4, 4, "Empty")
			TerrainGrid.setCell(grid, 2, 2, "Solid")
			TerrainGrid.setCell(grid, 3, 3, "Indestructible")

			local solid = TerrainGrid.findSupportBelow(grid, 4.5, 7.5, 9, 4)
			local protected = TerrainGrid.findSupportBelow(grid, 8.5, 11.5, 13, 4)

			expect(solid ~= nil and solid.kind).to.equal("Solid")
			expect(solid ~= nil and solid.surfaceY).to.equal(8)
			expect(protected ~= nil and protected.kind).to.equal("Indestructible")
			expect(protected ~= nil and protected.surfaceY).to.equal(12)
		end)

		it("reports a hazard before solid terrain lower in the fall path", function()
			local grid = createGrid(2, 4, "Empty")
			TerrainGrid.setCell(grid, 1, 1, "Solid")
			TerrainGrid.setCell(grid, 1, 3, "Hazard")

			local result = TerrainGrid.findSupportBelow(grid, 0.5, 3.5, 16, 16)

			expect(result ~= nil and result.kind).to.equal("Hazard")
			expect(result ~= nil and result.surfaceY).to.equal(12)
		end)

		it("supports a footprint that overlaps a thin ledge at a cell edge", function()
			local grid = createGrid(3, 2, "Empty")
			TerrainGrid.setCell(grid, 2, 1, "Solid")

			local result = TerrainGrid.findSupportBelow(grid, 3.8, 5.2, 5, 2)

			expect(result ~= nil and result.kind).to.equal("Solid")
			expect(result ~= nil and result.surfaceY).to.equal(4)
		end)

		it("loses support after the supporting cell is destroyed", function()
			local grid = createGrid(3, 3, "Empty")
			TerrainGrid.setCell(grid, 2, 2, "Solid")
			expect(TerrainGrid.findSupportBelow(grid, 4.5, 7.5, 9, 2) ~= nil).to.equal(true)

			TerrainGrid.destroyCircle(grid, Vector2.new(6, 6), 1)
			expect(TerrainGrid.findSupportBelow(grid, 4.5, 7.5, 9, 2)).to.equal(nil)
		end)

		it("rejects out-of-grid and invalid bounded queries", function()
			local grid = createGrid(2, 2, "Solid")

			expect(TerrainGrid.findSupportBelow(grid, 20, 24, 8, 8)).to.equal(nil)
			expect(TerrainGrid.findSupportBelow(grid, 4, 3, 8, 8)).to.equal(nil)
			expect(TerrainGrid.findSupportBelow(grid, 0, 4, 8, -1)).to.equal(nil)
		end)
	end)

	describe("TerrainGrid destruction", function()
		it("clips a circular crater cleanly at a map edge", function()
			local grid = createGrid(3, 3, "Solid")
			local changed = TerrainGrid.destroyCircle(grid, Vector2.new(2, 2), 4)

			expect(#changed).to.equal(3)
			expect(changed[1].index).to.equal(1)
			expect(changed[2].index).to.equal(2)
			expect(changed[3].index).to.equal(4)
			expect(TerrainGrid.getCell(grid, 1, 1)).to.equal("Empty")
			expect(TerrainGrid.getCell(grid, 2, 2)).to.equal("Solid")
		end)

		it("handles thin surfaces and returns only new overlap changes", function()
			local grid = createGrid(5, 3, "Empty")
			for x = 1, 5 do
				TerrainGrid.setCell(grid, x, 2, "Solid")
			end

			local first = TerrainGrid.destroyCircle(grid, Vector2.new(10, 6), 4)
			expect(#first).to.equal(3)
			expect(TerrainGrid.getCell(grid, 1, 2)).to.equal("Solid")
			expect(TerrainGrid.getCell(grid, 2, 2)).to.equal("Empty")
			expect(TerrainGrid.getCell(grid, 3, 2)).to.equal("Empty")
			expect(TerrainGrid.getCell(grid, 4, 2)).to.equal("Empty")

			local overlap = TerrainGrid.destroyCircle(grid, Vector2.new(14, 6), 4)
			expect(#overlap).to.equal(1)
			expect(overlap[1].index).to.equal(TerrainGrid.toIndex(grid, 5, 2))
			expect(TerrainGrid.getCell(grid, 5, 2)).to.equal("Empty")
		end)

		it("preserves indestructible cells while clearing solid and hazard cells", function()
			local grid = createGrid(3, 1, "Solid")
			TerrainGrid.setCell(grid, 2, 1, "Indestructible")
			TerrainGrid.setCell(grid, 3, 1, "Hazard")

			local changed = TerrainGrid.destroyCircle(grid, Vector2.new(6, 2), 4)

			expect(#changed).to.equal(2)
			expect(changed[1].index).to.equal(1)
			expect(changed[2].index).to.equal(3)
			expect(TerrainGrid.getCell(grid, 1, 1)).to.equal("Empty")
			expect(TerrainGrid.getCell(grid, 2, 1)).to.equal("Indestructible")
			expect(TerrainGrid.getCell(grid, 3, 1)).to.equal("Empty")
		end)

		it("deduplicates changed cells across a crater and repeated application", function()
			local grid = createGrid(5, 5, "Solid")
			local first = TerrainGrid.destroyCircle(grid, Vector2.new(10, 10), 20)
			local seen: { [number]: boolean } = {}

			for _, delta in first do
				expect(seen[delta.index]).to.equal(nil)
				seen[delta.index] = true
				expect(delta.code).to.equal(TerrainGrid.Codes.Empty)
			end

			expect(#first).to.equal(25)
			expect(#TerrainGrid.destroyCircle(grid, Vector2.new(10, 10), 20)).to.equal(0)
		end)
	end)

	describe("TerrainGrid snapshots and deltas", function()
		it("round-trips a compact numeric snapshot without aliasing", function()
			local grid = createGrid(2, 2, "Empty")
			TerrainGrid.setCell(grid, 1, 1, "Solid")
			TerrainGrid.setCell(grid, 2, 1, "Hazard")
			TerrainGrid.setCell(grid, 2, 2, "Indestructible")

			local snapshot = TerrainGrid.snapshot(grid)
			expect(#snapshot.cells).to.equal(4)
			expect(snapshot.cells[1]).to.equal(TerrainGrid.Codes.Solid)
			expect(snapshot.cells[2]).to.equal(TerrainGrid.Codes.Hazard)
			expect(snapshot.cells[4]).to.equal(TerrainGrid.Codes.Indestructible)

			local restored = TerrainGrid.fromSnapshot(snapshot)
			TerrainGrid.setCell(grid, 1, 1, "Empty")

			expect(TerrainGrid.getCell(restored, 1, 1)).to.equal("Solid")
			expect(TerrainGrid.getCell(restored, 2, 1)).to.equal("Hazard")
			expect(TerrainGrid.getCell(restored, 2, 2)).to.equal("Indestructible")
		end)

		it("applies validated delta batches and rejects duplicate indices", function()
			local grid = createGrid(2, 2, "Empty")
			local changedCount = TerrainGrid.applyDelta(grid, {
				{
					index = 1,
					code = TerrainGrid.Codes.Solid,
				},
				{
					index = 4,
					code = TerrainGrid.Codes.Hazard,
				},
			})

			expect(changedCount).to.equal(2)
			expect(TerrainGrid.getCell(grid, 1, 1)).to.equal("Solid")
			expect(TerrainGrid.getCell(grid, 2, 2)).to.equal("Hazard")

			local duplicateAccepted = pcall(function()
				TerrainGrid.applyDelta(grid, {
					{
						index = 1,
						code = TerrainGrid.Codes.Empty,
					},
					{
						index = 1,
						code = TerrainGrid.Codes.Solid,
					},
				})
			end)
			expect(duplicateAccepted).to.equal(false)
			expect(TerrainGrid.getCell(grid, 1, 1)).to.equal("Solid")
		end)

		it("returns nil for no-op and out-of-bounds writes", function()
			local grid = createGrid(2, 2, "Empty")

			expect(TerrainGrid.setCell(grid, 1, 1, "Empty")).to.equal(nil)
			expect(TerrainGrid.setCell(grid, 3, 1, "Solid")).to.equal(nil)
		end)
	end)
end
