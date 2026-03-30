-- Pattern data structures and compression algorithm for mosaic crochet export.
-- Run tests with: lua tests/test_pattern.lua (from extension root)
--
-- A sequence element is a two-value table  { content, count }  where:
--   content is a string  → stitch  (e.g. { "sc", 3 })
--   content is a table   → repeat group (e.g. { { item, item, … }, 5 })
-- No explicit "kind" tag needed; use  type(item[1])  to discriminate.

local M = {}

-- { t, count }         – stitch leaf
-- { items, count }     – repeat group
-- Use type(item[1]) to discriminate: "string" → stitch, "table" → repeat group.

local function stitch(t, count)
	return { t, count }
end

local function repeatGroup(items, count)
	return { items, count }
end

local function cost(seq)
	local total = 0
	for _, item in ipairs(seq) do
		if type(item[1]) == "string" then
			total = total + 1
		else
			total = total + 1 + cost(item[1])
		end
	end
	return total
end

-- Run-length encode flat[i..j] (1-based) into a list of stitch items.
local function rle_sub(flat, i, j)
	local r, cur, n = {}, flat[i], 1
	for k = i + 1, j do
		if flat[k] == cur then
			n = n + 1
		else
			r[#r + 1] = stitch(cur, n)
			cur, n = flat[k], 1
		end
	end
	r[#r + 1] = stitch(cur, n)
	return r
end

local function concat(a, b)
	local r = {}
	for _, v in ipairs(a) do r[#r + 1] = v end
	for _, v in ipairs(b) do r[#r + 1] = v end
	return r
end

-- Return true if flat[i .. i+period-1] repeated `count` times equals flat[i .. i+period*count-1].
local function isRepeat(flat, i, period, count)
	for rep = 1, count - 1 do
		for k = 0, period - 1 do
			if flat[i + k] ~= flat[i + rep * period + k] then return false end
		end
	end
	return true
end

-- Maximum-compression DP.
--
-- Takes a flat array of stitch-type strings and returns a nested sequence of
-- stitches / repeatGroups with the fewest total tokens.
--
-- Period detection is done at the character level, so a pattern like
-- {sc,dc,sc, sc,dc,sc, sc,dc,sc} is correctly seen as [sc,dc,sc]×3 even though
-- naïve RLE would merge the boundary sc's and obscure the repeating structure.
--
-- Complexity: O(n³) time, O(n²) space where n = number of stitches in the row.
function M.compress(flat)
	local n = #flat
	if n == 0 then return {} end

	local memo = {}

	local function solve(i, j)
		if memo[i] and memo[i][j] then return memo[i][j] end

		-- Baseline: RLE of the raw sub-sequence.
		local base = rle_sub(flat, i, j)
		local best_repr = base
		local best_cost = #base

		local len = j - i + 1
		if len >= 2 then
			-- Try all splits.
			for k = i, j - 1 do
				local L = solve(i, k)
				local R = solve(k + 1, j)
				local c = L.cost + R.cost
				if c < best_cost then
					best_cost = c
					best_repr = concat(L.repr, R.repr)
				end
			end

			-- Try all repeating periods at the character level.
			for period = 1, math.floor(len / 2) do
				if len % period == 0 then
					local count = len / period
					if isRepeat(flat, i, period, count) then
						local inner = solve(i, i + period - 1)
						local c = inner.cost + 1
						if c < best_cost then
							best_cost = c
							best_repr = { repeatGroup(inner.repr, count) }
						end
					end
				end
			end
		end

		local res = { repr = best_repr, cost = best_cost }
		if not memo[i] then memo[i] = {} end
		memo[i][j] = res
		return res
	end

	return solve(1, n).repr
end

-- Human-readable serialization for debugging / export preview.
-- Count 1 is omitted: stitch("sc",1) → "sc", stitch("dc",3) → "3dc".
-- Example: "2sc, [dc, sc] ×4, dc"
function M.toString(seq)
	local parts = {}
	for _, item in ipairs(seq) do
		if type(item[1]) == "string" then
			local t, n = item[1], item[2]
			parts[#parts + 1] = (n == 1 and t) or (n .. t)
		else
			parts[#parts + 1] = "[" .. M.toString(item[1]) .. "] ×" .. item[2]
		end
	end
	return table.concat(parts, ", ")
end

return M
