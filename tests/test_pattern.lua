-- Run with: lua tests/test_pattern.lua
-- from the extension root directory.

local P = require("src.pattern")
local framework = require("tests.framework")
local test = framework.test

-- ─── helpers ───────────────────────────────────────────────────────────────

-- Expand a compressed sequence back to a flat string array (test-only utility).
local function flatten(seq)
	local r = {}
	for _, item in ipairs(seq) do
		if type(item) == "string" then
			r[#r + 1] = item
		else
			for _ = 1, item[2] do
				for _, s in ipairs(flatten(item[1])) do r[#r + 1] = s end
			end
		end
	end
	return r
end

local function assertEqual(got, expected, label)
	local gs, es = P.toString(got), P.toString(expected)
	assert(gs == es,
		(label or "assertEqual") ..
		"\n  got:      " .. gs ..
		"\n  expected: " .. es)
end


-- ─── compress: basics ──────────────────────────────────────────────────────

test("compress: empty input", function()
	assert(#P.compress({}) == 0)
end)

test("compress: single sc", function()
	assertEqual(P.compress({ "sc" }), { "sc" })
end)

test("compress: single dc", function()
	assertEqual(P.compress({ "dc" }), { "dc" })
end)

test("compress: consecutive same type collapses to one stitch", function()
	assertEqual(P.compress({ "sc", "sc", "sc", "sc" }), { { { "sc" }, 4 } })
end)

test("compress: two different non-repeating types – no grouping", function()
	assertEqual(P.compress({ "sc", "dc" }), { "sc", "dc" })
end)

test("compress: three non-repeating items – no grouping", function()
	assertEqual(P.compress({ "sc", "sc", "dc" }), { { { "sc" }, 2 }, "dc" })
end)

-- ─── compress: the boundary-merge case ─────────────────────────────────────
--
-- Naïve RLE-then-compress would merge the "sc" at the end of one period with
-- the "sc" at the start of the next, hiding the repeating structure.
-- Character-level period detection finds it correctly.

test("compress: [sc, dc, sc] × 3 detected across merged RLE boundary", function()
	-- "sc, dc, sc, sc, dc, sc, sc, dc, sc" – the trailing sc and leading sc of adjacent
	-- periods merge in RLE into {sc, 2}, but at character level period=3 is visible.
	assertEqual(
		P.compress({ "sc", "dc", "sc", "sc", "dc", "sc", "sc", "dc", "sc" }),
		{ { { "sc", "dc", "sc" }, 3 } }
	)
end)

test("compress: [dc, sc, dc] × 3 detected across merged RLE boundary", function()
	assertEqual(
		P.compress({ "dc", "sc", "dc", "dc", "sc", "dc", "dc", "sc", "dc" }),
		{ { { "dc", "sc", "dc" }, 3 } }
	)
end)

test("compress: [sc, dc, sc, dc] × 2 detected across merged boundary", function()
	-- Period [sc, dc, sc, dc] ends sc, starts sc → merge at boundary.
	-- period=2 is cheaper than period=4 with count=2.
	assertEqual(
		P.compress({ "sc", "dc", "sc", "dc", "sc", "dc", "sc", "dc" }),
		{ { { "sc", "dc" }, 4 } }
	)
end)

-- ─── compress: clean periods (no boundary merge) ───────────────────────────

test("compress: alternating [sc, dc] × 12", function()
	assertEqual(P.compress(flatten({ { { "sc", "dc" }, 12 } })), { { { "sc", "dc" }, 12 } })
end)

test("compress: checker [2sc, 2dc] × 4", function()
	assertEqual(
		P.compress(flatten({ { { "sc", "sc", "dc", "dc" }, 4 } })),
		{ { { { { "sc" }, 2 }, { { "dc" }, 2 } }, 4 } }
	)
end)

test("compress: [3sc, dc] × 3", function()
	assertEqual(
		P.compress(flatten({ { { "sc", "sc", "sc", "dc" }, 3 } })),
		{ { { { { "sc" }, 3 }, "dc" }, 3 } }
	)
end)

test("compress: long period [sc, dc, 2sc, 2dc, sc, dc] × 3", function()
	-- Period ends dc, starts sc → no boundary merge.
	assertEqual(
		P.compress(flatten({ { { "sc", "dc", "sc", "sc", "dc", "dc", "sc", "dc" }, 3 } })),
		{ { { "sc", "dc", { { "sc" }, 2 }, { { "dc" }, 2 }, "sc", "dc" }, 3 } }
	)
end)

test("compress: period of count 2 saves one token", function()
	assertEqual(
		P.compress(flatten({ { { "sc", "sc", "dc", "dc" }, 2 } })),
		{ { { { { "sc" }, 2 }, { { "dc" }, 2 } }, 2 } }
	)
end)

-- ─── compress: prefix / suffix ─────────────────────────────────────────────

test("compress: unique prefix + repeat group", function()
	assertEqual(
		P.compress({ "sc", "sc", "sc", "dc", "sc", "dc", "sc", "dc", "sc", "dc", "sc" }),
		{ { { "sc" }, 3 }, { { "dc", "sc" }, 4 } }
	)
end)

test("compress: repeat group + unique suffix", function()
	assertEqual(
		P.compress({ "sc", "dc", "sc", "dc", "sc", "dc", "sc", "dc", "sc", "sc", "sc" }),
		{ { { "sc", "dc" }, 4 }, { { "sc" }, 3 } }
	)
end)

test("compress: two separate repeat groups", function()
	assertEqual(
		P.compress({ "sc", "dc", "sc", "dc", "sc", "dc",
		             "sc", "sc", "dc", "dc", "sc", "sc", "dc", "dc" }),
		{ { { "sc", "dc" }, 3 }, { { { { "sc" }, 2 }, { { "dc" }, 2 } }, 2 } }
	)
end)

-- ─── compress: nested repeats ──────────────────────────────────────────────

test("compress: nested [[sc, dc] × 3, dc] × 3", function()
	-- Period = sc, dc, sc, dc, sc, dc, dc  (7 chars, ends dc starts sc → no boundary merge).
	assertEqual(
		P.compress(flatten({ { { "sc", "dc", "sc", "dc", "sc", "dc", "dc" }, 3 } })),
		{ { { { { "sc", "dc" }, 3 }, "dc" }, 3 } }
	)
end)

test("compress: nested [[sc, dc] × 4, dc] × 2", function()
	assertEqual(
		P.compress(flatten({ { { "sc", "dc", "sc", "dc", "sc", "dc", "sc", "dc", "dc" }, 2 } })),
		{ { { { { "sc", "dc" }, 4 }, "dc" }, 2 } }
	)
end)

-- ─── compress: non-divisible length ────────────────────────────────────────

test("compress: 7 chars [sc, dc, sc, dc, sc, dc, sc] – split at leftmost improvement", function()
	-- No period divides 7. Split k=1 is found first: sc + [dc, sc] × 3.
	-- Split k=6 also gives same cost ([sc, dc] × 3 + sc) but is found second → no update.
	assertEqual(
		P.compress({ "sc", "dc", "sc", "dc", "sc", "dc", "sc" }),
		{ "sc", { { "dc", "sc" }, 3 } }
	)
end)

test("compress: period=5 beats naive split when it's cheaper", function()
	assertEqual(
		P.compress({ "sc", "dc", "sc", "dc", "sc",
		             "sc", "dc", "sc", "dc", "sc" }),
		{ { { "sc", { { "dc", "sc" }, 2 } }, 2 } }
	)
end)

-- ─── compress: edge cases ──────────────────────────────────────────────────

test("compress: all sc – single stitch, no grouping cheaper", function()
	-- [sc] × N and a plain stitch run both cost 1 leaf – tie, period wins.
	assertEqual(
		P.compress({ "sc", "sc", "sc", "sc", "sc", "sc", "sc", "sc", "sc", "sc" }),
		{ { { "sc" }, 10 } }
	)
end)

test("compress: count-10 repeat", function()
	assertEqual(P.compress(flatten({ { { "sc", "dc" }, 10 } })), { { { "sc", "dc" }, 10 } })
end)

test("compress: repeat count is integer not float", function()
	-- len/period uses division which gives floats in Lua 5.3+; must be floored
	local result = P.compress({ "sc", "dc", "sc", "dc", "sc", "dc" })
	assert(not P.toString(result):find("%."), "count must not contain a decimal point")
end)

test("compress: leaves cost prefers nested inner over flat inner", function()
	-- Period 5, count 2: inner = sc, dc, sc, dc, dc.
	-- +1-per-group cost: inner [sc, dc, sc, 2dc] costs 4, outer group costs 5.
	-- Leaves-only cost:  inner [[sc, dc] × 2, dc] costs 3, outer group costs 3.
	assertEqual(
		P.compress(flatten({ { { "sc", "dc", "sc", "dc", "dc" }, 2 } })),
		{ { { { { "sc", "dc" }, 2 }, "dc" }, 2 } }
	)
end)

-- ─── roundtrip: no information lost ────────────────────────────────────────

test("roundtrip: boundary-merge case [sc, dc, sc] × 3", function()
	local flat = { "sc", "dc", "sc", "sc", "dc", "sc", "sc", "dc", "sc" }
	assertEqual(flatten(P.compress(flat)), flat)
end)

test("roundtrip: diagonal stripe ×3", function()
	local flat = flatten({ { { "sc", "dc", "sc", "sc", "dc", "dc", "sc", "dc" }, 3 } })
	assertEqual(flatten(P.compress(flat)), flat)
end)

test("roundtrip: all sc", function()
	local flat = flatten({ { { "sc" }, 20 } })
	assertEqual(flatten(P.compress(flat)), flat)
end)

test("roundtrip: alternating sc/dc ×15", function()
	local flat = flatten({ { { "sc", "dc" }, 15 } })
	assertEqual(flatten(P.compress(flat)), flat)
end)

test("roundtrip: nested pattern ×3", function()
	local flat = flatten({ { { "sc", "dc", "sc", "dc", "sc", "dc", "dc" }, 3 } })
	assertEqual(flatten(P.compress(flat)), flat)
end)

test("roundtrip: varied mosaic row", function()
	local flat = { "sc", "sc", "dc", "sc", "dc", "dc", "sc",
	               "sc", "sc", "dc", "sc", "dc", "dc", "sc",
	               "sc", "sc", "dc" }
	assertEqual(flatten(P.compress(flat)), flat)
end)

-- ─── toString ──────────────────────────────────────────────────────────────

test("toString: single stitch", function()
	assert(P.toString({ "sc" }) == "sc")
	assert(P.toString({ "dc" }) == "dc")
end)

test("toString: flat sequence", function()
	assert(P.toString({ "sc", "dc", "sc" }) == "sc, dc, sc")
end)

test("toString: single-stitch repeat uses type-×-count notation", function()
	assert(P.toString({ { { "sc" }, 3 } }) == "sc × 3")
	assert(P.toString({ { { "dc" }, 10 } }) == "dc × 10")
end)

test("toString: shallow repeat group", function()
	assert(P.toString({ { { "sc", "dc" }, 4 } }) == "[sc, dc] × 4")
end)

test("toString: nested repeat group", function()
	local inner = { { "sc", "dc" }, 2 }
	local outer = { { inner, "sc" }, 3 }
	assert(P.toString({ outer }) == "[[sc, dc] × 2, sc] × 3")
end)

test("toString: mixed flat and grouped", function()
	assert(P.toString({ "sc", { { "dc", { { "sc" }, 2 } }, 3 }, "dc" })
		== "sc, [dc, sc × 2] × 3, dc")
end)
