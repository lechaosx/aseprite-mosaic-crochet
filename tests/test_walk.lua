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

local function collectSegs(roundIter)
	local rounds = {}
	for segIter in roundIter do
		local segs = {}
		for seg in segIter do segs[#segs + 1] = collect(seg) end
		rounds[#rounds + 1] = segs
	end
	return rounds
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

-- ─── roundWalk: round count ────────────────────────────────────────────────

test("roundWalk: yields exactly `rounds` rounds", function()
	-- vW=5=1+2*2, rounds=2 (innerWidth=1)
	assert(#collectSegs(walk.roundWalk(5, 5, 5, 5, 0, 0, 2)) == 2)
	-- vW=7=1+2*3, rounds=3 (innerWidth=1)
	assert(#collectSegs(walk.roundWalk(7, 7, 7, 7, 0, 0, 3)) == 3)
end)

-- ─── roundWalk: segment count ──────────────────────────────────────────────

test("roundWalk full: 4 segments per round (W==vW, H==vH)", function()
	for segIter in walk.roundWalk(5, 5, 5, 5, 0, 0, 2) do
		local t = {}
		for seg in segIter do t[#t + 1] = seg end
		assert(#t == 4)
	end
end)

test("roundWalk half: 2 segments per round (W==vW, H<vH)", function()
	for segIter in walk.roundWalk(5, 5, 5, 10, 0, 5, 1) do
		local t = {}
		for seg in segIter do t[#t + 1] = seg end
		assert(#t == 2)
	end
end)

test("roundWalk quarter: 1 segment per round (W<vW)", function()
	for segIter in walk.roundWalk(3, 5, 5, 10, 0, 5, 1) do
		local t = {}
		for seg in segIter do t[#t + 1] = seg end
		assert(#t == 1)
	end
end)

-- ─── roundWalk: side lengths ───────────────────────────────────────────────

test("roundWalk: side length = vH - 2*(rounds-r) - 2 for left/right sides", function()
	-- innerWidth=1: vW=vH=2*rounds+1, side length = 2r-1
	local rounds = collectSegs(walk.roundWalk(7, 7, 7, 7, 0, 0, 3))
	assert(#rounds[1][1] == 1, "r=1: n=1")
	assert(#rounds[2][1] == 3, "r=2: n=3")
	assert(#rounds[3][1] == 5, "r=3: n=5")
end)

test("roundWalk: innerWidth=3 gives correct side lengths (bug: was using 2r-1)", function()
	-- vW=vH=7=3+2*2, rounds=2, innerWidth=3
	-- r=1: k=1, n=7-2-2=3
	-- r=2: k=0, n=7-0-2=5
	local rounds = collectSegs(walk.roundWalk(7, 7, 7, 7, 0, 0, 2))
	assert(#rounds[1][1] == 3, "r=1 with innerWidth=3: n=3, not 2*1-1=1")
	assert(#rounds[2][1] == 5, "r=2 with innerWidth=3: n=5, not 2*2-1=3")
end)

-- ─── roundWalk: coordinates ────────────────────────────────────────────────

-- Use innerWidth=1 (vW=2*rounds+1) for predictable coordinates.
test("roundWalk full: side order anti-clockwise from top-left", function()
	-- vW=vH=5, rounds=2, innerWidth=1. r=1: k=1, n=1
	local rounds = collectSegs(walk.roundWalk(5, 5, 5, 5, 0, 0, 2))
	local segs = rounds[1]
	assert(segs[1][1][1] == 1 and segs[1][1][2] == 2, "side 1 left↓  (1,2)")
	assert(segs[2][1][1] == 2 and segs[2][1][2] == 3, "side 2 bottom→(2,3)")
	assert(segs[3][1][1] == 3 and segs[3][1][2] == 2, "side 3 right↑ (3,2)")
	assert(segs[4][1][1] == 2 and segs[4][1][2] == 1, "side 4 top←   (2,1)")
end)

test("roundWalk full: side 1 walks downward", function()
	-- vW=vH=7, rounds=3, innerWidth=1. r=2: k=1, n=3, left↓ from (1,2)
	local rounds = collectSegs(walk.roundWalk(7, 7, 7, 7, 0, 0, 3))
	local seg1 = rounds[2][1]
	assert(seg1[1][1] == 1 and seg1[1][2] == 2)
	assert(seg1[2][1] == 1 and seg1[2][2] == 3)
	assert(seg1[3][1] == 1 and seg1[3][2] == 4)
end)

test("roundWalk full: side 3 walks upward", function()
	-- vW=vH=7, rounds=3, innerWidth=1. r=2: k=1, right↑ from (5,4)
	local rounds = collectSegs(walk.roundWalk(7, 7, 7, 7, 0, 0, 3))
	local seg3 = rounds[2][3]
	assert(seg3[1][1] == 5 and seg3[1][2] == 4)
	assert(seg3[2][1] == 5 and seg3[2][2] == 3)
	assert(seg3[3][1] == 5 and seg3[3][2] == 2)
end)

-- ─── roundWalk: offset ─────────────────────────────────────────────────────

test("roundWalk: offset translates virtual to physical coordinates", function()
	-- vW=5, vH=6, offX=0, offY=3, rounds=1, innerWidth=5-2=3, innerHeight=6-2=4
	-- r=1: k=0, left↓: virtual x=0, y=1 → physical (0-0, 1-3)=... hmm out of bounds
	-- Let's use vW=5,vH=4,rounds=1,offY=2: innerHeight=4-2=2
	-- r=1: k=0, nLR=4-0-2=2, left↓: virtual (0,1),(0,2) → physical (0,-1),(0,0)
	-- Use vW=5,vH=6,rounds=2,offY=3: innerWidth=1,innerHeight=2
	-- r=1: k=1, nLR=6-2-2=2, left↓: virtual (1,2),(1,3) → physical (1,-1),(1,0)
	-- Simplest: full 5×5, rounds=2, offset (1,1)
	-- numSides: W=3,H=3,vW=5,vH=5 → W<vW → numSides=1
	-- r=1: k=1, left↓: virtual (1,2) → physical (1-1,2-1)=(0,1)
	local rounds = collectSegs(walk.roundWalk(3, 3, 5, 5, 1, 1, 2))
	assert(rounds[1][1][1][1] == 0 and rounds[1][1][1][2] == 1,
		"virtual (1,2) → physical (0,1) with offset (1,1)")
end)
