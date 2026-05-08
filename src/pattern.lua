-- Pattern data structures and compression algorithm for mosaic crochet export.
-- Run tests with: lua tests/test_pattern.lua (from extension root)
--
-- A sequence is a list where each element is either:
--   a string         → stitch  (e.g. "sc")
--   { items, count } → repeat group  (e.g. { {"sc", "dc"}, 5 })
-- Use type(item) to discriminate: "string" → stitch, "table" → repeat group.

local M = {}

local compressMemo = {}

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
-- stitches / repeatGroups with the fewest total leaf tokens (stitches).
-- Cost = number of leaf strings in the compressed tree; repeat group wrappers are free.
--
-- Period detection is done at the character level, so a pattern like
-- {sc,dc,sc, sc,dc,sc, sc,dc,sc} is correctly seen as [sc,dc,sc]×3.
--
-- Complexity: O(n³) time, O(n²) space where n = number of stitches in the row.
function M.compress(flat)
	local n = #flat
	if n == 0 then return {} end

	local memo = compressMemo

	local function solve(i, j)
		local key = table.concat(flat, "|", i, j)
		if memo[key] then return memo[key] end

		local result = { seq = {}, cost = j - i + 1 }
		for k = i, j do result.seq[#result.seq + 1] = flat[k] end
		local len = j - i + 1

		-- Try all splits.
		for k = i, j - 1 do
			local L = solve(i, k)
			local R = solve(k + 1, j)
			local c = L.cost + R.cost
			if c < result.cost then
				result.cost = c
				result.seq = {}
				for _, v in ipairs(L.seq) do result.seq[#result.seq + 1] = v end
				for _, v in ipairs(R.seq) do result.seq[#result.seq + 1] = v end
			end
		end

		-- Try all repeating periods at the character level.
		-- Cost = inner leaf count only; repeat group wrappers are free.
		for period = 1, math.floor(len / 2) do
			if len % period == 0 then
				local inner = solve(i, i + period - 1)
				if isRepeat(flat, i, period, math.floor(len / period)) and inner.cost < result.cost then
					result.cost = inner.cost
					result.seq = { { inner.seq, math.floor(len / period) } }
				end
			end
		end

		memo[key] = result
		return result
	end

	return solve(1, n).seq
end

-- Human-readable serialization for debugging / export preview.
-- Single-stitch repeats: "sc × 3". Multi-stitch groups: "[sc, dc] × 4".
-- Example: "sc, sc × 3, [dc, sc] × 4, dc"
function M.toString(seq)
	local parts = {}
	for _, item in ipairs(seq) do
		if type(item) == "string" then
			parts[#parts + 1] = item
		else
			local items, count = item[1], item[2]
			if #items == 1 and type(items[1]) == "string" then
				parts[#parts + 1] = items[1] .. " × " .. count
			else
				parts[#parts + 1] = "[" .. M.toString(items) .. "] × " .. count
			end
		end
	end
	return table.concat(parts, ", ")
end

return M
