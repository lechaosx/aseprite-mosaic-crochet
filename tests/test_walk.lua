-- Run with: lua tests/test_walk.lua
-- from the extension root directory.

local walk      = require("src.walk")
local framework = require("tests.framework")
local test      = framework.test

local function collect(iter)
	local t = {}
	for xy in iter do t[#t + 1] = xy end
	return t
end

local function collectAll(outerIter)
	local t = {}
	for inner in outerIter do t[#t + 1] = collect(inner) end
	return t
end

local function countCorners(coords, offX, offY, vW, vH)
	local n = 0
	for _, c in ipairs(coords) do
		if walk.isCornerCoord(c[1], c[2], offX, offY, vW, vH) then n = n + 1 end
	end
	return n
end

-- ─── rowWalk ───────────────────────────────────────────────────────────────

test("rowWalk: yields H-1 rows", function()
	assert(#collectAll(walk.rowWalk(3, 4)) == 3)
	assert(#collectAll(walk.rowWalk(1, 2)) == 1)
end)

test("rowWalk: each row has W pixels", function()
	for row in walk.rowWalk(5, 4) do
		assert(#collect(row) == 5)
	end
end)

test("rowWalk: walks left-to-right at correct y", function()
	local rows = collectAll(walk.rowWalk(3, 4))
	-- row 1: y = 4-1-1 = 2
	assert(rows[1][1][1] == 0 and rows[1][1][2] == 2)
	assert(rows[1][2][1] == 1 and rows[1][2][2] == 2)
	assert(rows[1][3][1] == 2 and rows[1][3][2] == 2)
end)

test("rowWalk: y decreases across rows", function()
	local rows = collectAll(walk.rowWalk(1, 4))
	assert(rows[1][1][2] == 2)
	assert(rows[2][1][2] == 1)
	assert(rows[3][1][2] == 0)
end)

-- ─── roundWalk ─────────────────────────────────────────────────────────────

test("roundWalk: yields exactly `rounds` rounds", function()
	assert(#collectAll(walk.roundWalk(5, 5, 2)) == 2)
	assert(#collectAll(walk.roundWalk(7, 7, 3)) == 3)
end)

test("roundWalk: each full round has 4 corners", function()
	-- no clipping: all 4 corners are always present
	for round in walk.roundWalk(5, 5, 2) do
		assert(countCorners(collect(round), 0, 0, 5, 5) == 4)
	end
end)

test("roundWalk: total coords = 2*(LR+TB) + 4 corners (innerWidth=1)", function()
	-- vW=vH=2*rounds+1; total per round r = 4*(2r-1)+4 = 8r
	local rounds = collectAll(walk.roundWalk(7, 7, 3))
	assert(#rounds[1] == 8,  "r=1: 8")
	assert(#rounds[2] == 16, "r=2: 16")
	assert(#rounds[3] == 24, "r=3: 24")
end)

test("roundWalk: total coords correct with innerWidth=3", function()
	-- vW=vH=7, rounds=2: r=1: LR=TB=3 → 16; r=2: LR=TB=5 → 24
	local rounds = collectAll(walk.roundWalk(7, 7, 2))
	assert(#rounds[1] == 16, "r=1: 16")
	assert(#rounds[2] == 24, "r=2: 24")
end)

test("roundWalk: flat coord order starts at TL corner, anti-clockwise", function()
	-- vW=vH=5, rounds=2, innerWidth=1. r=1: LR=TB=1
	-- TL:(1,1), side1(left↓):(1,2), BL:(1,3), side2(bot→):(2,3),
	-- BR:(3,3), side3(right↑):(3,2), TR:(3,1), side4(top←):(2,1)
	local r1 = collectAll(walk.roundWalk(5, 5, 2))[1]
	assert(r1[1][1] == 1 and r1[1][2] == 1, "TL corner (1,1)")
	assert(r1[2][1] == 1 and r1[2][2] == 2, "side1 (1,2)")
	assert(r1[3][1] == 1 and r1[3][2] == 3, "BL corner (1,3)")
	assert(r1[4][1] == 2 and r1[4][2] == 3, "side2 (2,3)")
	assert(r1[5][1] == 3 and r1[5][2] == 3, "BR corner (3,3)")
	assert(r1[6][1] == 3 and r1[6][2] == 2, "side3 (3,2)")
	assert(r1[7][1] == 3 and r1[7][2] == 1, "TR corner (3,1)")
	assert(r1[8][1] == 2 and r1[8][2] == 1, "side4 (2,1)")
end)

test("roundWalk: side 1 walks downward", function()
	-- vW=vH=7, rounds=3. r=2: edgeDistance=1, LR=3
	-- r2[1]=TL corner (1,1), r2[2..4]=side1 left↓
	local r2 = collectAll(walk.roundWalk(7, 7, 3))[2]
	assert(r2[2][1] == 1 and r2[2][2] == 2)
	assert(r2[3][1] == 1 and r2[3][2] == 3)
	assert(r2[4][1] == 1 and r2[4][2] == 4)
	-- r2[5] is BL corner (1,5)
end)

test("roundWalk: side 3 walks upward", function()
	-- vW=vH=7, rounds=3. r=2: LR=3, TB=3.
	-- side3 starts at TL(1)+side1(3)+BL(1)+side2(3)+BR(1)+1 = index 10
	local r2 = collectAll(walk.roundWalk(7, 7, 3))[2]
	assert(r2[10][1] == 5 and r2[10][2] == 4)
	assert(r2[11][1] == 5 and r2[11][2] == 3)
	assert(r2[12][1] == 5 and r2[12][2] == 2)
end)

-- ─── window ────────────────────────────────────────────────────────────────

local function translate(iter, offX, offY)
	return coroutine.wrap(function()
		for coord in iter do coroutine.yield({ coord[1] - offX, coord[2] - offY }) end
	end)
end

test("window: passes coords inside bounds and drops those outside", function()
	local src = coroutine.wrap(function()
		for _, c in ipairs({{ -1,0 }, { 0,0 }, { 2,2 }, { 4,4 }, { 5,0 }, { 0,5 }}) do
			coroutine.yield(c)
		end
	end)
	local result = collect(walk.window(src, 5, 5))
	assert(#result == 3)
	assert(result[1][1] == 0 and result[1][2] == 0)
	assert(result[2][1] == 2 and result[2][2] == 2)
	assert(result[3][1] == 4 and result[3][2] == 4)
end)

test("roundWalk + window: all coords within physical canvas after translation", function()
	-- half mode: upper virtual half maps to negative y after offY=5 subtraction
	for round in walk.roundWalk(5, 10, 1) do
		for coord in walk.window(translate(round, 0, 5), 5, 5) do
			assert(coord[1] >= 0 and coord[1] < 5, "x in [0,4]")
			assert(coord[2] >= 0 and coord[2] < 5, "y in [0,4]")
		end
	end
end)

test("roundWalk + window: half mode yields 2 corners per round", function()
	-- vW=5, vH=10, offY=5, W=5, H=5: BL and BR corners in bounds, TR and TL out
	for round in walk.roundWalk(5, 10, 1) do
		local coords = collect(walk.window(translate(round, 0, 5), 5, 5))
		assert(countCorners(coords, 0, 5, 5, 10) == 2)
	end
end)

test("roundWalk + window: quarter mode yields 1 corner per round", function()
	-- vW=5, vH=10, offY=5, W=3, H=5: only BL corner in bounds
	for round in walk.roundWalk(5, 10, 1) do
		local coords = collect(walk.window(translate(round, 0, 5), 3, 5))
		assert(countCorners(coords, 0, 5, 5, 10) == 1)
	end
end)

-- ─── isCornerCoord ─────────────────────────────────────────────────────────

test("isCornerCoord: detects ring corners in full 5x5 grid", function()
	assert(walk.isCornerCoord(1, 1, 0, 0, 5, 5), "TL (1,1)")
	assert(walk.isCornerCoord(1, 3, 0, 0, 5, 5), "BL (1,3)")
	assert(walk.isCornerCoord(3, 3, 0, 0, 5, 5), "BR (3,3)")
	assert(walk.isCornerCoord(3, 1, 0, 0, 5, 5), "TR (3,1)")
	assert(not walk.isCornerCoord(1, 2, 0, 0, 5, 5), "left side — not corner")
	assert(not walk.isCornerCoord(2, 3, 0, 0, 5, 5), "bottom side — not corner")
end)

test("isCornerCoord: works with offset", function()
	-- physical (0,0) + offset(1,1) → virtual (1,1): corner of 5x5
	assert(walk.isCornerCoord(0, 0, 1, 1, 5, 5))
	-- physical (0,1) + offset(1,1) → virtual (1,2): not corner
	assert(not walk.isCornerCoord(0, 1, 1, 1, 5, 5))
end)

test("isCornerCoord: outermost ring corners of full 7x7 grid", function()
	assert(walk.isCornerCoord(0, 0, 0, 0, 7, 7), "TL (0,0)")
	assert(walk.isCornerCoord(0, 6, 0, 0, 7, 7), "BL (0,6)")
	assert(walk.isCornerCoord(6, 6, 0, 0, 7, 7), "BR (6,6)")
	assert(walk.isCornerCoord(6, 0, 0, 0, 7, 7), "TR (6,0)")
	assert(not walk.isCornerCoord(0, 3, 0, 0, 7, 7), "left side mid — not corner")
end)
