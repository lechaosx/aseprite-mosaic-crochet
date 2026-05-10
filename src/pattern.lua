-- Pattern data structures and compression algorithm for mosaic crochet export.
-- Run tests with: lua tests/test_pattern.lua (from extension root)
--
-- A sequence is a list where each element is either:
--   a string         → stitch  (e.g. "sc")
--   { items, count } → repeat group  (e.g. { {"sc", "dc"}, 5 })
-- Use type(item) to discriminate: "string" → stitch, "table" → repeat group.

local M = {}

-- Build LCE table: lce[i][j] is the length of the longest common prefix of
-- flat[i..] and flat[j..], for 1 <= i < j <= n.
-- Filled bottom-up: lce(i,j) = flat[i]==flat[j] ? 1 + lce(i+1,j+1) : 0.
-- With this table a periodicity check becomes one O(1) read:
--   flat[s..s+len-1] is `period`-periodic iff
--   len % period == 0  and  lce[s][s+period] >= len - period.
local function buildLCE(flat, n)
	local lce = {}
	for i = 1, n do lce[i] = {} end
	for i = n, 1, -1 do
		for j = n, i + 1, -1 do
			if flat[i] == flat[j] then
				local nxt = (i < n and j < n) and (lce[i + 1][j + 1] or 0) or 0
				lce[i][j] = nxt + 1
			else
				lce[i][j] = 0
			end
		end
	end
	return lce
end

-- Iterative bottom-up DP over all (start, len) sub-slices.
-- Returns (dec_type, dec_val):
--   dec_type[s][len] = 0 → literal
--                      1 → split at k   (dec_val = k)
--                      2 → repeat       (dec_val = period)
--
-- Optimisations that match the Rust implementation:
--   • Periods are checked with a single LCE read instead of O(n) isRepeat scan.
--   • After the first valid period (the fundamental period q), we break:
--     by Fine-Wilf every other valid period is a multiple of q, and
--     repeating with kq gives the same inner leaf count as repeating with q.
--   • Splits are skipped entirely when best_cost <= 2 (a split has two
--     non-empty children each costing >= 1, so total >= 2; it can't improve).
--   • Within the split loop, branch-and-bound prunes when left+1 >= best_cost.
local function solve(flat, n, lce)
	local cost     = {}
	local dec_type = {}
	local dec_val  = {}

	-- Initialise length-1 cells.
	for s = 1, n do
		cost[s]     = {}
		dec_type[s] = {}
		dec_val[s]  = {}
		cost[s][1]     = 1
		dec_type[s][1] = 0
		dec_val[s][1]  = 0
	end

	for len = 2, n do
		for s = 1, n - len + 1 do
			local best_cost = len  -- start with literal cost
			local bt, bv    = 0, 0

			-- Periods
			for period = 1, math.floor(len / 2) do
				if len % period == 0 then
					local lv = lce[s][s + period] or 0
					if lv >= len - period then
						local ic = cost[s][period]
						if ic < best_cost then
							best_cost = ic
							bt = 2
							bv = period
						end
						break  -- fundamental period found; larger multiples can't improve
					end
				end
			end

			-- Splits
			if best_cost > 2 then
				for k = 1, len - 1 do
					local left = cost[s][k]
					if left + 1 < best_cost then
						local right = cost[s + k][len - k]
						local total = left + right
						if total < best_cost then
							best_cost = total
							bt = 1
							bv = k
						end
					end
				end
			end

			cost[s][len]     = best_cost
			dec_type[s][len] = bt
			dec_val[s][len]  = bv
		end
	end

	return dec_type, dec_val
end

-- Reconstruct compressed sequence by following back-pointers.
local function reconstruct(flat, s, len, dec_type, dec_val)
	if len == 0 then return {} end
	local t = dec_type[s][len]
	if t == 0 then
		local r = {}
		for i = s, s + len - 1 do r[#r + 1] = flat[i] end
		return r
	elseif t == 1 then
		local k = dec_val[s][len]
		local r = reconstruct(flat, s, k, dec_type, dec_val)
		for _, v in ipairs(reconstruct(flat, s + k, len - k, dec_type, dec_val)) do
			r[#r + 1] = v
		end
		return r
	else
		local period = dec_val[s][len]
		local count  = math.floor(len / period)
		return { { reconstruct(flat, s, period, dec_type, dec_val), count } }
	end
end

-- Maximum-compression DP.
--
-- Takes a flat array of stitch-type strings and returns a nested sequence of
-- stitches / repeatGroups with the fewest total leaf tokens (stitches).
-- Cost = number of leaf strings in the compressed tree; repeat group wrappers are free.
--
-- Uses an LCE (longest-common-extension) table for O(1) periodicity checks,
-- iterative bottom-up DP (no recursion, no string-key memoisation table),
-- period-first ordering with Fine-Wilf break, and branch-and-bound split
-- pruning. O(n³) worst case with tight constants.
function M.compress(flat)
	local n = #flat
	if n == 0 then return {} end
	local lce = buildLCE(flat, n)
	local dec_type, dec_val = solve(flat, n, lce)
	return reconstruct(flat, 1, n, dec_type, dec_val)
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
