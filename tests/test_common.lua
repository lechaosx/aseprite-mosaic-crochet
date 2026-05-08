-- Run with: lua tests/test_common.lua
-- from the extension root directory.

local common = require("src.common")
local framework = require("tests.framework")
local test = framework.test

-- ─── getColorDistance ──────────────────────────────────────────────────────

local function rgb(r, g, b) return { red=r, green=g, blue=b } end

test("getColorDistance returns 0 for identical colors", function()
	assert(common.getColorDistance(rgb(0,0,0), rgb(0,0,0)) == 0)
	assert(common.getColorDistance(rgb(255,128,64), rgb(255,128,64)) == 0)
end)

test("getColorDistance is symmetric", function()
	local a, b = rgb(10, 20, 30), rgb(40, 50, 60)
	assert(common.getColorDistance(a, b) == common.getColorDistance(b, a))
end)

test("getColorDistance uses squared Euclidean (no sqrt)", function()
	-- (3,4,0) vs (0,0,0): sqrt would give 5, squared gives 25.
	assert(common.getColorDistance(rgb(3,4,0), rgb(0,0,0)) == 25)
end)

test("getColorDistance only uses RGB channels (alpha ignored)", function()
	-- Tables have no alpha field; the function should not error.
	assert(common.getColorDistance(rgb(0,0,0), rgb(1,0,0)) == 1)
end)

-- ─── nearestColorIndex ─────────────────────────────────────────────────────

test("nearestColorIndex returns COLOR_A when color equals colorA", function()
	assert(common.nearestColorIndex(rgb(0,0,0), rgb(0,0,0), rgb(255,255,255)) == common.COLOR_A)
end)

test("nearestColorIndex returns COLOR_B when color equals colorB", function()
	assert(common.nearestColorIndex(rgb(255,255,255), rgb(0,0,0), rgb(255,255,255)) == common.COLOR_B)
end)

test("nearestColorIndex snaps to closer color", function()
	-- color=(200,200,200): dist to white(255)=3*(55^2)=9075, dist to black(0)=3*(200^2)=120000 → white wins.
	assert(common.nearestColorIndex(rgb(200,200,200), rgb(0,0,0), rgb(255,255,255)) == common.COLOR_B)
	-- color=(50,50,50): dist to black=3*(50^2)=7500, dist to white=3*(205^2)=126075 → black wins.
	assert(common.nearestColorIndex(rgb(50,50,50), rgb(0,0,0), rgb(255,255,255)) == common.COLOR_A)
end)

test("nearestColorIndex ties resolve to COLOR_A", function()
	-- True midpoint: (5,0,0) between (0,0,0) and (10,0,0); dist=25 each.
	assert(common.nearestColorIndex(rgb(5,0,0), rgb(0,0,0), rgb(10,0,0)) == common.COLOR_A)
end)

-- ─── computeRowHighlights ──────────────────────────────────────────────────

local function makeRowGrid(W, H)
	local g = {}
	for y = 0, H - 1 do
		g[y] = {}
		for x = 0, W - 1 do
			g[y][x] = common.getColorIndex(common.getRowIndex(H, y))
		end
	end
	return g
end

local function runRowHighlights(W, H, overrides)
	local grid = makeRowGrid(W, H)
	for _, ov in ipairs(overrides or {}) do grid[ov[2]][ov[1]] = ov[3] end
	local flatHighlights = {}
	for i = 0, W * H - 1 do flatHighlights[i] = 0 end
	common.computeRowHighlights(
		W, H,
		function(x, y) return grid[y][x] end,
		flatHighlights
	)
	local hl = {}
	for y = 0, H - 1 do
		hl[y] = {}
		for x = 0, W - 1 do
			local value = flatHighlights[y * W + x]
			if value ~= 0 then hl[y][x] = value end
		end
	end
	return hl
end

local V = common.HIGHLIGHT_VALID_OVERLAY
local I = common.HIGHLIGHT_INVALID_PLACEMENT

test("computeRowHighlights: no highlights when pattern is correct", function()
	local hl = runRowHighlights(4, 4)
	for y = 0, 3 do
		for x = 0, 3 do
			assert(hl[y][x] == nil,
				string.format("unexpected highlight at (%d,%d)", x, y))
		end
	end
end)

test("computeRowHighlights: overlay on top edge (y=0) is invalid", function()
	local H = 4
	-- y=0: rowIndex=H-1=3 (odd) → COLOR_B. Flip to COLOR_A.
	local hl = runRowHighlights(4, H, { {2, 0, common.COLOR_A} })
	assert(hl[0][2] == I, "top-edge overlay must be INVALID")
end)

test("computeRowHighlights: overlay on bottom edge (y=H-1) is invalid", function()
	local H = 4
	-- y=H-1=3: rowIndex=0 (even) → COLOR_A. Flip to COLOR_B.
	local hl = runRowHighlights(4, H, { {2, H-1, common.COLOR_B} })
	assert(hl[H-1][2] == I, "bottom-edge overlay must be INVALID")
end)

test("computeRowHighlights: valid overlay highlights the row above", function()
	-- 4×4: y=1 rowIndex=2 (even) → COLOR_A. Flip to COLOR_B.
	-- Inner pixel y+1=2: rowIndex=1 (odd) → COLOR_B. colorIndex=COLOR_A ≠ COLOR_B → VALID at y-1=0.
	local hl = runRowHighlights(4, 4, { {2, 1, common.COLOR_B} })
	assert(hl[0][2] == V, "valid overlay should highlight row above (y-1)")
	assert(hl[1][2] == nil, "overlay row itself should have no highlight")
end)

test("computeRowHighlights: invalid when inner pixel matches expected color", function()
	-- H=3: y=1 (middle), colorIndex=getColorIndex(getRowIndex(3,1))=getColorIndex(1)=COLOR_B.
	-- Force inner pixel y=2 to COLOR_B (= colorIndex) and flip y=1 to COLOR_A (overlay).
	-- y=2 is the bottom edge, so its own overlay produces INVALID at y=2, not at y=1.
	-- At y=1: inner=COLOR_B=colorIndex → INVALID at (2,1).
	local hl = runRowHighlights(4, 3, { {2, 1, common.COLOR_A}, {2, 2, common.COLOR_B} })
	assert(hl[1][2] == I, "overlay with inner pixel matching expected color must be INVALID")
end)

test("computeRowHighlights: each column is independent", function()
	-- Flip every pixel in one row; verify highlight appears one row above for each column.
	local W, H = 6, 4
	local overrides = {}
	-- y=1: colorIndex=COLOR_A. Flip all columns to COLOR_B.
	for x = 0, W - 1 do overrides[#overrides + 1] = {x, 1, common.COLOR_B} end
	local hl = runRowHighlights(W, H, overrides)
	for x = 0, W - 1 do
		assert(hl[0][x] == V, string.format("column %d: expected VALID highlight at y=0", x))
	end
end)

test("computeRowHighlights: adjacent wrong pixels — inner is crochetable, outer is not", function()
	-- H=5. y=1 expects COLOR_B (rowIndex=3, odd); flip to COLOR_A.
	--       y=2 expects COLOR_A (rowIndex=2, even); flip to COLOR_B.
	--       y=3 expects COLOR_B (rowIndex=1, odd); correct, stays.
	-- y=1: inner y=2=COLOR_B == colorIndex(y=1)=COLOR_B → INVALID at y=1.
	-- y=2: inner y=3=COLOR_B ≠ colorIndex(y=2)=COLOR_A → valid OC candidate,
	--       but OC target y=1 is already INVALID → y=2 gets no mark.
	-- Regression: the old outer-pixel guard incorrectly marked y=2 as INVALID too.
	local hl = runRowHighlights(4, 5, {
		{2, 1, common.COLOR_A},
		{2, 2, common.COLOR_B},
	})
	assert(hl[1][2] == I, "y=1 must be INVALID (inner pixel matches expected color)")
	assert(hl[2][2] ~= I, "y=2 must not be INVALID (regression: adjacent invalid incorrectly propagated)")
end)


test("getColorIndex alternates COLOR_A and COLOR_B", function()
	assert(common.getColorIndex(0) == common.COLOR_A)
	assert(common.getColorIndex(1) == common.COLOR_B)
	assert(common.getColorIndex(2) == common.COLOR_A)
	assert(common.getColorIndex(3) == common.COLOR_B)
end)

test("getRowIndex maps top row to max index and bottom to 0", function()
	assert(common.getRowIndex(9, 0) == 8)
	assert(common.getRowIndex(9, 8) == 0)
	assert(common.getRowIndex(9, 4) == 4)
	assert(common.getRowIndex(1, 0) == 0)
end)

test("getRoundFromEdge returns 0 at all edges and corners", function()
	assert(common.getRoundFromEdge(9, 9, 0, 0) == 0)
	assert(common.getRoundFromEdge(9, 9, 8, 0) == 0)
	assert(common.getRoundFromEdge(9, 9, 0, 8) == 0)
	assert(common.getRoundFromEdge(9, 9, 8, 8) == 0)
	assert(common.getRoundFromEdge(9, 9, 0, 4) == 0)
	assert(common.getRoundFromEdge(9, 9, 4, 0) == 0)
end)

test("getRoundFromEdge increases towards center in square image", function()
	assert(common.getRoundFromEdge(9, 9, 1, 4) == 1)
	assert(common.getRoundFromEdge(9, 9, 2, 4) == 2)
	assert(common.getRoundFromEdge(9, 9, 1, 1) == 1)
	assert(common.getRoundFromEdge(9, 9, 2, 2) == 2)
	assert(common.getRoundFromEdge(9, 9, 3, 3) == 3)
	assert(common.getRoundFromEdge(9, 9, 4, 4) == 4)
end)

test("getRoundFromEdge is limited by shorter dimension in rectangular image", function()
	-- 16x6 image: max roundFromEdge is 2 (floor((6-1)/2))
	assert(common.getRoundFromEdge(16, 6, 0,  0) == 0)
	assert(common.getRoundFromEdge(16, 6, 3,  0) == 0)
	assert(common.getRoundFromEdge(16, 6, 3,  1) == 1)
	assert(common.getRoundFromEdge(16, 6, 3,  2) == 2)
	assert(common.getRoundFromEdge(16, 6, 8,  2) == 2)
	assert(common.getRoundFromEdge(16, 6, 8,  3) == 2)
	assert(common.getRoundFromEdge(16, 6, 15, 5) == 0)
end)

test("getRoundIndex returns negative for inner hole pixels in 9x9 r=3", function()
	-- inner hole: pixels where roundFromEdge >= rounds=3
	assert(common.getRoundIndex(9, 9, 3, 3, 3) == -1)
	assert(common.getRoundIndex(9, 9, 3, 4, 4) == -2)
	assert(common.getRoundIndex(9, 9, 3, 5, 4)  < 0)
end)

test("getRoundIndex returns correct ring indices in 9x9 r=3", function()
	assert(common.getRoundIndex(9, 9, 3, 2, 4) == 0) -- innermost ring
	assert(common.getRoundIndex(9, 9, 3, 1, 4) == 1)
	assert(common.getRoundIndex(9, 9, 3, 0, 4) == 2) -- outermost ring
	-- symmetric sides
	assert(common.getRoundIndex(9, 9, 3, 6, 4) == 0)
	assert(common.getRoundIndex(9, 9, 3, 7, 4) == 1)
	assert(common.getRoundIndex(9, 9, 3, 8, 4) == 2)
end)

test("getRoundIndex has no inner hole in 16x6 r=3 (innerHeight=0)", function()
	-- max roundFromEdge=2 < rounds=3, so no pixel is transparent
	for y = 0, 5 do
		for x = 0, 15 do
			assert(common.getRoundIndex(16, 6, 3, x, y) >= 0,
				string.format("pixel (%d,%d) should not be in hole", x, y))
		end
	end
end)

test("getRoundIndex ring indices in 16x6 r=3", function()
	assert(common.getRoundIndex(16, 6, 3, 0,  0) == 2) -- outermost
	assert(common.getRoundIndex(16, 6, 3, 8,  2) == 0) -- innermost
	assert(common.getRoundIndex(16, 6, 3, 8,  3) == 0) -- innermost (symmetric row)
	assert(common.getRoundIndex(16, 6, 3, 15, 5) == 2) -- outermost far corner
end)

test("getRoundFromEdge same on both sides of zero-dimension seam in 16x6 r=3", function()
	-- For innerHeight=0, rows 2 and 3 are the innermost ring on opposite sides of the
	-- virtual seam. getRoundFromEdge must return the same value for both so the highlight
	-- logic can detect the seam crossing and allow overlays on the innermost ring.
	for x = 0, 15 do
		assert(common.getRoundFromEdge(16, 6, x, 2) == common.getRoundFromEdge(16, 6, x, 3),
			string.format("seam mismatch at x=%d", x))
	end
end)
