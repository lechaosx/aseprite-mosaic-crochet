-- Coordinate walk generators for mosaic crochet traversal.
--
-- rowWalk(width, height)          → iterator of coordIter (physical)
-- roundWalk(width, height, rounds) → iterator of coordIter
-- window(coordIter, width, height) → coordIter (drops coords outside [0,width)×[0,height))
--
-- coordIter yields {x, y} tables.
-- roundWalk yields full rounds: side coords interleaved with corner coords.
-- window is a pure bounds filter; offset translation is the caller's responsibility.
-- isCornerCoord(x, y, offsetX, offsetY, virtualWidth, virtualHeight) → bool

local M = {}

-- Iterator of coordIters, one per row round=1..height-1, walking left-to-right.
function M.rowWalk(width, height)
	return coroutine.wrap(function()
		for round = 1, height - 1 do
			local y = height - 1 - round
			coroutine.yield(coroutine.wrap(function()
				for x = 0, width - 1 do
					coroutine.yield({ x, y })
				end
			end))
		end
	end)
end

-- Iterator of coordIters, one per round=1..rounds, anti-clockwise from top-left.
-- Yields full rounds with no awareness of any physical canvas cutout.
-- Sides: left↓, bottom→, right↑, top←
-- Corners: BL, BR, TR, TL (one after each side).
function M.roundWalk(width, height, rounds)
	return coroutine.wrap(function()
		for round = 1, rounds do
			local edgeDistance    = rounds - round
			local leftRightLength = height - 2 * edgeDistance - 2
			local topBottomLength = width  - 2 * edgeDistance - 2
			local sides = {
				{ x = edgeDistance,          y = edgeDistance + 1,        stepX =  0, stepY =  1, n = leftRightLength },
				{ x = edgeDistance + 1,      y = height - 1 - edgeDistance, stepX =  1, stepY =  0, n = topBottomLength },
				{ x = width - 1 - edgeDistance, y = height - 2 - edgeDistance, stepX =  0, stepY = -1, n = leftRightLength },
				{ x = width - 2 - edgeDistance, y = edgeDistance,              stepX = -1, stepY =  0, n = topBottomLength },
			}
			local corners = {
				{ x = edgeDistance,             y = edgeDistance             },  -- TL (before left↓)
				{ x = edgeDistance,             y = height - 1 - edgeDistance },  -- BL (before bottom→)
				{ x = width - 1 - edgeDistance, y = height - 1 - edgeDistance },  -- BR (before right↑)
				{ x = width - 1 - edgeDistance, y = edgeDistance             },  -- TR (before top←)
			}
			coroutine.yield(coroutine.wrap(function()
				for sideIndex = 1, 4 do
					local c = corners[sideIndex]
					coroutine.yield({ c.x, c.y })
					local side = sides[sideIndex]
					for step = 0, side.n - 1 do
						coroutine.yield({ side.x + step * side.stepX,
						                 side.y + step * side.stepY })
					end
				end
			end))
		end
	end)
end

-- Drops any coords that fall outside [0, width) × [0, height).
function M.window(coordIter, width, height)
	return coroutine.wrap(function()
		for coord in coordIter do
			if coord[1] >= 0 and coord[1] < width and coord[2] >= 0 and coord[2] < height then
				coroutine.yield(coord)
			end
		end
	end)
end

-- Returns true when physical (x, y) maps to a ring corner in virtual space.
-- A corner is where minDistX == minDistY (equidistant from horizontal and vertical edges).
function M.isCornerCoord(x, y, offsetX, offsetY, virtualWidth, virtualHeight)
	local vx = x + offsetX
	local vy = y + offsetY
	return math.min(vx, virtualWidth - 1 - vx) == math.min(vy, virtualHeight - 1 - vy)
end

return M
