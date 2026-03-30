-- Run with: lua tests/test_common.lua
-- from the extension root directory.

local common = require("src.common")
local framework = require("tests.framework")
local test = framework.test

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
