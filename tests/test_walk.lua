-- Run with: lua tests/test_walk.lua
-- from the extension root directory.

local common    = require("src.common")
local vec2      = require("src.vec2")
local walk      = require("src.walk")
local framework = require("tests.framework")
local test      = framework.test

local function collect(sourceIterator)
	local collectedItems = {}
	for currentItem in sourceIterator do collectedItems[#collectedItems + 1] = currentItem end
	return collectedItems
end

local function collectAll(outerIterator)
	local collectedRounds = {}
	for innerIterator in outerIterator do collectedRounds[#collectedRounds + 1] = collect(innerIterator) end
	return collectedRounds
end

local filter = common.filter
local map    = common.map

-- roundWalk yields {coord, parent} pairs; extract the coord component for corner checks.
local function countCorners(pairs, offset, virtualSize)
	local cornerCount = 0
	for _, pair in ipairs(pairs) do
		if walk.isCornerCoord(pair[1], offset, virtualSize) then cornerCount = cornerCount + 1 end
	end
	return cornerCount
end

-- ─── rowWalk ───────────────────────────────────────────────────────────────

test("rowWalk: yields H-1 rows", function()
	assert(#collectAll(walk.rowWalk(vec2(3, 4))) == 3)
	assert(#collectAll(walk.rowWalk(vec2(1, 2))) == 1)
end)

test("rowWalk: each row has W pixels", function()
	for row in walk.rowWalk(vec2(5, 4)) do
		assert(#collect(row) == 5)
	end
end)

test("rowWalk: walks left-to-right at correct y", function()
	local rows = collectAll(walk.rowWalk(vec2(3, 4)))
	-- row 1: y = 4-1-1 = 2
	assert(rows[1][1].x == 0 and rows[1][1].y == 2)
	assert(rows[1][2].x == 1 and rows[1][2].y == 2)
	assert(rows[1][3].x == 2 and rows[1][3].y == 2)
end)

test("rowWalk: y decreases across rows", function()
	local rows = collectAll(walk.rowWalk(vec2(1, 4)))
	assert(rows[1][1].y == 2)
	assert(rows[2][1].y == 1)
	assert(rows[3][1].y == 0)
end)

-- ─── roundWalk ─────────────────────────────────────────────────────────────

test("roundWalk: yields exactly `rounds` rounds", function()
	assert(#collectAll(walk.roundWalk(vec2(5, 5), 2)) == 2)
	assert(#collectAll(walk.roundWalk(vec2(7, 7), 3)) == 3)
end)

test("roundWalk: each full round has 4 corners", function()
	-- no clipping: all 4 corners are always present
	for round in walk.roundWalk(vec2(5, 5), 2) do
		assert(countCorners(collect(round), vec2(0, 0), vec2(5, 5)) == 4)
	end
end)

test("roundWalk: total coords = 2*(LR+TB) + 4 corners (innerWidth=1)", function()
	-- vW=vH=2*rounds+1; total per round r = 4*(2r-1)+4 = 8r
	local rounds = collectAll(walk.roundWalk(vec2(7, 7), 3))
	assert(#rounds[1] == 8,  "r=1: 8")
	assert(#rounds[2] == 16, "r=2: 16")
	assert(#rounds[3] == 24, "r=3: 24")
end)

test("roundWalk: total coords correct with innerWidth=3", function()
	-- vW=vH=7, rounds=2: r=1: LR=TB=3 → 16; r=2: LR=TB=5 → 24
	local rounds = collectAll(walk.roundWalk(vec2(7, 7), 2))
	assert(#rounds[1] == 16, "r=1: 16")
	assert(#rounds[2] == 24, "r=2: 24")
end)

test("roundWalk: flat coord order starts one right of TL, anti-clockwise", function()
	-- vW=vH=5, rounds=2, innerWidth=1. r=1: LR=TB=1
	-- pre-start:(2,1), TL:(1,1), left↓:(1,2), BL:(1,3), bot→:(2,3),
	-- BR:(3,3), right↑:(3,2), TR:(3,1)  [top← exhausted by pre-start]
	-- Each element is a {coord, parent} pair; [1] is the position coord vec2.
	local r1 = collectAll(walk.roundWalk(vec2(5, 5), 2))[1]
	assert(r1[1][1].x == 2 and r1[1][1].y == 1, "pre-start (2,1)")
	assert(r1[2][1].x == 1 and r1[2][1].y == 1, "TL corner (1,1)")
	assert(r1[3][1].x == 1 and r1[3][1].y == 2, "left↓ (1,2)")
	assert(r1[4][1].x == 1 and r1[4][1].y == 3, "BL corner (1,3)")
	assert(r1[5][1].x == 2 and r1[5][1].y == 3, "bot→ (2,3)")
	assert(r1[6][1].x == 3 and r1[6][1].y == 3, "BR corner (3,3)")
	assert(r1[7][1].x == 3 and r1[7][1].y == 2, "right↑ (3,2)")
	assert(r1[8][1].x == 3 and r1[8][1].y == 1, "TR corner (3,1)")
end)

test("roundWalk: side 1 walks downward", function()
	-- vW=vH=7, rounds=3. r=2: edgeDistance=1, LR=3
	-- r2[1]=pre-start, r2[2]=TL corner (1,1), r2[3..5]=left↓
	local r2 = collectAll(walk.roundWalk(vec2(7, 7), 3))[2]
	assert(r2[3][1].x == 1 and r2[3][1].y == 2)
	assert(r2[4][1].x == 1 and r2[4][1].y == 3)
	assert(r2[5][1].x == 1 and r2[5][1].y == 4)
	-- r2[6] is BL corner (1,5)
end)

test("roundWalk: side 3 walks upward", function()
	-- vW=vH=7, rounds=3. r=2: LR=3, TB=3.
	-- pre(1)+TL(1)+left(3)+BL(1)+bot(3)+BR(1) = index 10 is first of right↑
	local r2 = collectAll(walk.roundWalk(vec2(7, 7), 3))[2]
	assert(r2[11][1].x == 5 and r2[11][1].y == 4)
	assert(r2[12][1].x == 5 and r2[12][1].y == 3)
	assert(r2[13][1].x == 5 and r2[13][1].y == 2)
end)

-- ─── window ────────────────────────────────────────────────────────────────

test("window: returns true for coords inside bounds", function()
	assert(walk.window(vec2(0, 0), vec2(5, 5)))
	assert(walk.window(vec2(4, 4), vec2(5, 5)))
	assert(walk.window(vec2(2, 3), vec2(5, 5)))
end)

test("window: returns false for coords outside bounds", function()
	assert(not walk.window(vec2(-1, 0), vec2(5, 5)))
	assert(not walk.window(vec2(5,  0), vec2(5, 5)))
	assert(not walk.window(vec2(0,  5), vec2(5, 5)))
	assert(not walk.window(vec2(0, -1), vec2(5, 5)))
end)

local function shiftPairs(pairIterator, delta)
	return map(pairIterator, function(virtualPair)
		return { virtualPair[1] + delta, virtualPair[2] + delta }
	end)
end

test("roundWalk + window: all coords within physical canvas after translation", function()
	-- half mode: upper virtual half maps to negative y after offY=5 subtraction
	local canvasSize = vec2(5, 5)
	for round in walk.roundWalk(vec2(5, 10), 1) do
		local physicalPairIterator = shiftPairs(round, vec2(0, -5))
		local windowedPairIterator = filter(physicalPairIterator, function(physicalPair)
			return walk.window(physicalPair[1], canvasSize)
		end)
		for physicalPair in windowedPairIterator do
			local physicalCoord = physicalPair[1]
			assert(physicalCoord.x >= 0 and physicalCoord.x < 5, "x in [0,4]")
			assert(physicalCoord.y >= 0 and physicalCoord.y < 5, "y in [0,4]")
		end
	end
end)

test("roundWalk + window: half mode yields 2 corners per round", function()
	-- vW=5, vH=10, offY=5, W=5, H=5: BL and BR corners in bounds, TR and TL out
	local canvasSize   = vec2(5, 5)
	local virtualSize  = vec2(5, 10)
	local offset       = vec2(0, 5)
	for round in walk.roundWalk(virtualSize, 1) do
		local windowedPairs = collect(filter(shiftPairs(round, vec2(0, -5)), function(physicalPair)
			return walk.window(physicalPair[1], canvasSize)
		end))
		assert(countCorners(windowedPairs, offset, virtualSize) == 2)
	end
end)

test("roundWalk + window: quarter mode yields 1 corner per round", function()
	-- vW=5, vH=10, offY=5, W=3, H=5: only BL corner in bounds
	local canvasSize   = vec2(3, 5)
	local virtualSize  = vec2(5, 10)
	local offset       = vec2(0, 5)
	for round in walk.roundWalk(virtualSize, 1) do
		local windowedPairs = collect(filter(shiftPairs(round, vec2(0, -5)), function(physicalPair)
			return walk.window(physicalPair[1], canvasSize)
		end))
		assert(countCorners(windowedPairs, offset, virtualSize) == 1)
	end
end)

-- ─── isCornerCoord ─────────────────────────────────────────────────────────

test("isCornerCoord: detects ring corners in full 5x5 grid", function()
	local noOffset   = vec2(0, 0)
	local gridSize   = vec2(5, 5)
	assert(walk.isCornerCoord(vec2(1, 1), noOffset, gridSize), "TL (1,1)")
	assert(walk.isCornerCoord(vec2(1, 3), noOffset, gridSize), "BL (1,3)")
	assert(walk.isCornerCoord(vec2(3, 3), noOffset, gridSize), "BR (3,3)")
	assert(walk.isCornerCoord(vec2(3, 1), noOffset, gridSize), "TR (3,1)")
	assert(not walk.isCornerCoord(vec2(1, 2), noOffset, gridSize), "left side — not corner")
	assert(not walk.isCornerCoord(vec2(2, 3), noOffset, gridSize), "bottom side — not corner")
end)

test("isCornerCoord: works with offset", function()
	-- physical (0,0) + offset(1,1) → virtual (1,1): corner of 5x5
	assert(walk.isCornerCoord(vec2(0, 0), vec2(1, 1), vec2(5, 5)))
	-- physical (0,1) + offset(1,1) → virtual (1,2): not corner
	assert(not walk.isCornerCoord(vec2(0, 1), vec2(1, 1), vec2(5, 5)))
end)

test("isCornerCoord: outermost ring corners of full 7x7 grid", function()
	local noOffset = vec2(0, 0)
	local gridSize = vec2(7, 7)
	assert(walk.isCornerCoord(vec2(0, 0), noOffset, gridSize), "TL (0,0)")
	assert(walk.isCornerCoord(vec2(0, 6), noOffset, gridSize), "BL (0,6)")
	assert(walk.isCornerCoord(vec2(6, 6), noOffset, gridSize), "BR (6,6)")
	assert(walk.isCornerCoord(vec2(6, 0), noOffset, gridSize), "TR (6,0)")
	assert(not walk.isCornerCoord(vec2(0, 3), noOffset, gridSize), "left side mid — not corner")
end)

