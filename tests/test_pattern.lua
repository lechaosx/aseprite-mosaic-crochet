-- Run with: lua tests/test_pattern.lua
-- from the extension root directory.

local P = require("src.pattern")
local framework = require("tests.framework")
local test = framework.test

-- ─── helpers ───────────────────────────────────────────────────────────────

-- Local constructors (mirrors the internal structure; not part of the public API).
local function sc(n)  return { "sc", n } end
local function dc(n)  return { "dc", n } end
local function grp(items, n) return { items, n } end

-- Expand a compressed sequence back to a flat string array (test-only utility).
local function flatten(seq)
	local r = {}
	for _, item in ipairs(seq) do
		if type(item[1]) == "string" then
			for _ = 1, item[2] do r[#r + 1] = item[1] end
		else
			for _ = 1, item[2] do
				for _, s in ipairs(flatten(item[1])) do r[#r + 1] = s end
			end
		end
	end
	return r
end

-- Build a flat string array of `n` repetitions of `pattern`.
local function rep(pattern, n)
	local r = {}
	for _ = 1, n do for _, v in ipairs(pattern) do r[#r + 1] = v end end
	return r
end

-- Assert compress(flat) serialises to expected_str.
local function assertStr(flat, expected_str, label)
	local got = P.toString(P.compress(flat))
	assert(got == expected_str,
		(label or "assertStr") ..
		"\n  got:      " .. got ..
		"\n  expected: " .. expected_str)
end

-- Assert that compress(flat) reconstructs to the original flat sequence.
local function assertRoundtrip(flat, label)
	local recovered = flatten(P.compress(flat))
	assert(#recovered == #flat,
		(label or "roundtrip") .. ": length " .. #recovered .. " ≠ " .. #flat)
	for i, v in ipairs(flat) do
		assert(recovered[i] == v,
			(label or "roundtrip") .. ": mismatch at [" .. i .. "] got " ..
			tostring(recovered[i]) .. " want " .. v)
	end
end

-- ─── compress: basics ──────────────────────────────────────────────────────

test("compress: empty input", function()
	assert(#P.compress({}) == 0)
end)

test("compress: single sc", function()
	assertStr({ "sc" }, "sc")
end)

test("compress: single dc", function()
	assertStr({ "dc" }, "dc")
end)

test("compress: consecutive same type collapses to one stitch", function()
	assertStr({ "sc", "sc", "sc", "sc" }, "4sc")
end)

test("compress: two different non-repeating types – no grouping", function()
	assertStr({ "sc", "dc" }, "sc, dc")
end)

test("compress: three non-repeating items – no grouping", function()
	assertStr({ "sc", "sc", "dc" }, "2sc, dc")
end)

-- ─── compress: the boundary-merge case ─────────────────────────────────────
--
-- Naïve RLE-then-compress would merge the "sc" at the end of one period with
-- the "sc" at the start of the next, hiding the repeating structure.
-- Character-level period detection finds it correctly.

test("compress: [sc,dc,sc]×3 detected across merged RLE boundary", function()
	-- "sc,dc,sc, sc,dc,sc, sc,dc,sc" – the trailing sc and leading sc of adjacent
	-- periods merge in RLE into {sc,2}, but at character level period=3 is visible.
	assertStr(
		{ "sc", "dc", "sc", "sc", "dc", "sc", "sc", "dc", "sc" },
		"[sc, dc, sc] ×3"
	)
end)

test("compress: [dc,sc,dc]×3 detected across merged RLE boundary", function()
	assertStr(
		{ "dc", "sc", "dc", "dc", "sc", "dc", "dc", "sc", "dc" },
		"[dc, sc, dc] ×3"
	)
end)

test("compress: [sc,dc,sc,dc]×2 detected across merged boundary", function()
	-- Period [sc,dc,sc,dc] ends sc, starts sc → merge at boundary.
	assertStr(
		{ "sc", "dc", "sc", "dc", "sc", "dc", "sc", "dc" },
		"[sc, dc] ×4"  -- period=2 is cheaper than period=4 with count=2
	)
end)

-- ─── compress: clean periods (no boundary merge) ───────────────────────────

test("compress: alternating [sc,dc]×12", function()
	assertStr(rep({ "sc", "dc" }, 12), "[sc, dc] ×12")
end)

test("compress: checker [2sc,2dc]×4", function()
	assertStr(rep({ "sc", "sc", "dc", "dc" }, 4), "[2sc, 2dc] ×4")
end)

test("compress: [3sc,dc]×3", function()
	assertStr(rep({ "sc", "sc", "sc", "dc" }, 3), "[3sc, dc] ×3")
end)

test("compress: long period [sc,dc,2sc,2dc,sc,dc]×3", function()
	-- Period ends dc, starts sc → no boundary merge.
	assertStr(
		rep({ "sc", "dc", "sc", "sc", "dc", "dc", "sc", "dc" }, 3),
		"[sc, dc, 2sc, 2dc, sc, dc] ×3"
	)
end)

test("compress: period of count 2 saves one token", function()
	-- [sc,sc,dc,dc, sc,sc,dc,dc]: inner=[2sc,2dc] cost=2, group=3 < flat=4.
	assertStr(rep({ "sc", "sc", "dc", "dc" }, 2), "[2sc, 2dc] ×2")
end)

-- ─── compress: prefix / suffix ─────────────────────────────────────────────

test("compress: unique prefix + repeat group", function()
	-- 3sc then [dc,sc]×4
	assertStr(
		{ "sc", "sc", "sc", "dc", "sc", "dc", "sc", "dc", "sc", "dc", "sc" },
		"3sc, [dc, sc] ×4"
	)
end)

test("compress: repeat group + unique suffix", function()
	-- [sc,dc]×4 then 3sc
	assertStr(
		{ "sc", "dc", "sc", "dc", "sc", "dc", "sc", "dc", "sc", "sc", "sc" },
		"[sc, dc] ×4, 3sc"
	)
end)

test("compress: two separate repeat groups", function()
	-- [sc,dc]×3 then [2sc,2dc]×2
	assertStr(
		{ "sc", "dc", "sc", "dc", "sc", "dc",
		  "sc", "sc", "dc", "dc", "sc", "sc", "dc", "dc" },
		"[sc, dc] ×3, [2sc, 2dc] ×2"
	)
end)

-- ─── compress: nested repeats ──────────────────────────────────────────────

test("compress: nested [[sc,dc]×3, dc]×3", function()
	-- Period = sc,dc,sc,dc,sc,dc,dc  (7 chars, ends dc starts sc → no boundary merge).
	-- Inner: [sc,dc,sc,dc,sc,dc] = [sc,dc]×3, then dc → split gives cost 4.
	-- Outer RepeatGroup: cost = 4+1 = 5.
	assertStr(
		rep({ "sc", "dc", "sc", "dc", "sc", "dc", "dc" }, 3),
		"[[sc, dc] ×3, dc] ×3"
	)
end)

test("compress: nested [[sc,dc]×4, dc]×2", function()
	-- Period = sc,dc,sc,dc,sc,dc,sc,dc,dc  (9 chars, ends dc starts sc → no merge).
	-- Inner best split: [sc,dc]×4 + dc = cost 4; outer group = cost 5.
	-- "[sc,[dc,sc]×3,2dc]×2" would have cost 6 – the DP correctly finds the cheaper form.
	assertStr(
		rep({ "sc", "dc", "sc", "dc", "sc", "dc", "sc", "dc", "dc" }, 2),
		"[[sc, dc] ×4, dc] ×2"
	)
end)

-- ─── compress: non-divisible length ────────────────────────────────────────

test("compress: 7 chars [sc,dc,sc,dc,sc,dc,sc] – split at leftmost improvement", function()
	-- No period divides 7. Split k=1 is found first: sc + [dc,sc]×3 = cost 4.
	-- Split k=6 also gives cost 4 ([sc,dc]×3 + sc) but is found second → no update.
	assertStr(
		{ "sc", "dc", "sc", "dc", "sc", "dc", "sc" },
		"sc, [dc, sc] ×3"
	)
end)

test("compress: period=5 beats naive split when it's cheaper", function()
	-- [sc,dc,sc,dc,sc, sc,dc,sc,dc,sc]: period=5 count=2, inner has nested group.
	-- inner [sc,dc,sc,dc,sc]: split at k=1 → sc + [dc,sc]×2 = cost 4.
	-- RepGroup(inner=4, 2) = cost 5 < naive flat cost of 10 chars RLE.
	assertStr(
		{ "sc", "dc", "sc", "dc", "sc",
		  "sc", "dc", "sc", "dc", "sc" },
		"[sc, [dc, sc] ×2] ×2"
	)
end)

-- ─── compress: edge cases ──────────────────────────────────────────────────

test("compress: all sc – single stitch, no grouping cheaper", function()
	-- Rep([sc],N) costs 2, RLE [{sc,N}] costs 1 – baseline always wins.
	assertStr({ "sc", "sc", "sc", "sc", "sc", "sc", "sc", "sc", "sc", "sc" }, "10sc")
end)

test("compress: count-10 repeat", function()
	assertStr(rep({ "sc", "dc" }, 10), "[sc, dc] ×10")
end)

-- ─── roundtrip: no information lost ────────────────────────────────────────

test("roundtrip: boundary-merge case [sc,dc,sc]×3", function()
	assertRoundtrip(
		{ "sc", "dc", "sc", "sc", "dc", "sc", "sc", "dc", "sc" },
		"boundary-merge"
	)
end)

test("roundtrip: diagonal stripe ×3", function()
	assertRoundtrip(rep({ "sc", "dc", "sc", "sc", "dc", "dc", "sc", "dc" }, 3), "diagonal-stripe")
end)

test("roundtrip: all sc", function()
	assertRoundtrip(rep({ "sc" }, 20), "all-sc")
end)

test("roundtrip: alternating sc/dc ×15", function()
	assertRoundtrip(rep({ "sc", "dc" }, 15), "alt-x15")
end)

test("roundtrip: nested pattern ×3", function()
	assertRoundtrip(rep({ "sc", "dc", "sc", "dc", "sc", "dc", "dc" }, 3), "nested-x3")
end)

test("roundtrip: varied mosaic row", function()
	assertRoundtrip(
		{ "sc", "sc", "dc", "sc", "dc", "dc", "sc",
		  "sc", "sc", "dc", "sc", "dc", "dc", "sc",
		  "sc", "sc", "dc" },
		"varied"
	)
end)

-- ─── toString ──────────────────────────────────────────────────────────────

test("toString: count 1 omits the number prefix", function()
	assert(P.toString({ sc(1) }) == "sc")
	assert(P.toString({ dc(1) }) == "dc")
end)

test("toString: count > 1 shows the number prefix", function()
	assert(P.toString({ sc(3) }) == "3sc")
	assert(P.toString({ dc(10) }) == "10dc")
end)

test("toString: flat sequence", function()
	assert(P.toString({ sc(2), dc(1), sc(4) }) == "2sc, dc, 4sc")
end)

test("toString: shallow repeat group", function()
	assert(P.toString({ grp({ sc(2), dc(1) }, 4) }) == "[2sc, dc] ×4")
end)

test("toString: nested repeat group", function()
	local inner = grp({ sc(1), dc(1) }, 2)
	local outer = grp({ inner, sc(1) }, 3)
	assert(P.toString({ outer }) == "[[sc, dc] ×2, sc] ×3")
end)

test("toString: mixed flat and grouped", function()
	assert(P.toString({ sc(1), grp({ dc(1), sc(2) }, 3), dc(1) })
		== "sc, [dc, 2sc] ×3, dc")
end)
