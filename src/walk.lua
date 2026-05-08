-- Coordinate walk generators.
--
-- rowWalk(size)                              → iterator of coordIterator
-- roundWalk(size, rounds)                    → iterator of pairIterator
-- window(coord, size)                        → bool
-- isCornerCoord(coord, offset, virtualSize)  → bool
--
-- rowWalk coordIterator yields vec2(x, y).
-- roundWalk pairIterator yields {vec2(x,y), vec2(px,py)}: position and its inward projection.
--   The projection clamps the coordinate one ring inward; coordinates adjacent to the
--   same corner project to the same point, so grouping by projection clusters them.
-- window is a bounds predicate: coord inside [0, size.x) × [0, size.y).
-- isCornerCoord returns true when physical coord maps to a ring corner in virtual space.

local vec2 = require("src.vec2")
local M = {}

-- Iterator of coordIterators, one per row round=1..size.y-1, walking left-to-right.
function M.rowWalk(size)
	return coroutine.wrap(function()
		for round = 1, size.y - 1 do
			local y = size.y - 1 - round
			coroutine.yield(coroutine.wrap(function()
				for x = 0, size.x - 1 do
					coroutine.yield(vec2(x, y))
				end
			end))
		end
	end)
end

-- Iterator of pairIterators, one per round=1..rounds, starting at top-left, anti-clockwise.
-- Yields full rounds with no awareness of any bounds cutout.
-- Sides: left↓, bottom→, right↑, top←. Each corner precedes its side.
function M.roundWalk(size, rounds)
	return coroutine.wrap(function()
		for round = 1, rounds do
			local edgeDistance    = rounds - round
			local leftRightLength = size.y - 2 * edgeDistance - 2
			local topBottomLength = size.x - 2 * edgeDistance - 2
			local innerEdge       = edgeDistance + 1
			local innerBoundCoord = vec2(innerEdge,           innerEdge)
			local outerBoundCoord = vec2(size.x - 1 - innerEdge, size.y - 1 - innerEdge)
			local function projectInward(coord)
				return vec2.clamp(coord, innerBoundCoord, outerBoundCoord)
			end
			-- Five segments, anti-clockwise from one right of TL corner.
			-- Corners are the first step of their segment; the round starts/ends
			-- one pixel right of TL so the full TL corner group stays together.
			local segments = {
				{ startCoord = vec2(edgeDistance + 1,            edgeDistance             ), stepVector = vec2(-1,  0), count = 1                    },  -- pre-start (one right of TL)
				{ startCoord = vec2(edgeDistance,                edgeDistance             ), stepVector = vec2( 0,  1), count = 1 + leftRightLength   },  -- TL corner + left↓
				{ startCoord = vec2(edgeDistance,                size.y - 1 - edgeDistance), stepVector = vec2( 1,  0), count = 1 + topBottomLength   },  -- BL corner + bottom→
				{ startCoord = vec2(size.x - 1 - edgeDistance,  size.y - 1 - edgeDistance), stepVector = vec2( 0, -1), count = 1 + leftRightLength   },  -- BR corner + right↑
				{ startCoord = vec2(size.x - 1 - edgeDistance,  edgeDistance             ), stepVector = vec2(-1,  0), count = topBottomLength        },  -- TR corner + top← (excl. pre-start)
			}
			coroutine.yield(coroutine.wrap(function()
				for _, segment in ipairs(segments) do
					for step = 0, segment.count - 1 do
						local coord = segment.startCoord + segment.stepVector * step
						coroutine.yield({ coord, projectInward(coord) })
					end
				end
			end))
		end
	end)
end

-- Returns true when coord falls inside [0, size.x) × [0, size.y).
function M.window(coord, size)
	return coord.x >= 0 and coord.x < size.x and coord.y >= 0 and coord.y < size.y
end

-- Returns true when physical coord maps to a ring corner in virtual space.
-- A corner is where distX == distY (equidistant from horizontal and vertical edges).
function M.isCornerCoord(physicalCoord, offset, virtualSize)
	local virtualCoord        = physicalCoord + offset
	local distanceFromNearEdge = vec2.min(virtualCoord, virtualSize - vec2(1, 1) - virtualCoord)
	return distanceFromNearEdge.x == distanceFromNearEdge.y
end

return M
