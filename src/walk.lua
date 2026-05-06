-- Coordinate walk generators for mosaic crochet traversal.
--
-- rowWalk(width, height)                                          → iterator of coordIter
-- roundWalk(width, height, virtualWidth, virtualHeight, offsetX, offsetY, rounds) → iterator of segIter
--
-- coordIter yields {x, y} tables.
-- segIter   yields coord iterators, one per segment (side of the round).

local M = {}

-- Iterator of coordIters, one per row round=1..height-1, walking left-to-right.
function M.rowWalk(width, height)
	local round = 0
	return function()
		round = round + 1
		if round <= height - 1 then
			local y = height - 1 - round
			local x = -1
			return function()
				x = x + 1
				if x < width then return { x, y } end
			end
		end
	end
end

-- Iterator of segIters, one per round=1..rounds, anti-clockwise from top-left.
-- Each segIter yields coord iterators, one per segment (side).
-- numSides (4=full, 2=half, 1=quarter) derived from physical vs virtual dimensions.
-- Sides: left↓, bottom→, right↑, top←
function M.roundWalk(width, height, virtualWidth, virtualHeight, offsetX, offsetY, rounds)
	local numSides = (width == virtualWidth and height == virtualHeight) and 4
	             or (width == virtualWidth)                              and 2
	             or 1
	local round = 0
	return function()
		round = round + 1
		if round <= rounds then
			local edgeDistance   = rounds - round
			local leftRightLength = virtualHeight - 2 * edgeDistance - 2
			local topBottomLength = virtualWidth  - 2 * edgeDistance - 2
			local sides = {
				{ x = edgeDistance,              y = edgeDistance + 1,              stepX =  0, stepY =  1, n = leftRightLength },
				{ x = edgeDistance + 1,          y = virtualHeight - 1 - edgeDistance, stepX =  1, stepY =  0, n = topBottomLength },
				{ x = virtualWidth - 1 - edgeDistance, y = virtualHeight - 2 - edgeDistance, stepX =  0, stepY = -1, n = leftRightLength },
				{ x = virtualWidth - 2 - edgeDistance, y = edgeDistance,              stepX = -1, stepY =  0, n = topBottomLength },
			}
			local sideIndex = 0
			return function()
				sideIndex = sideIndex + 1
				if sideIndex <= numSides then
					local side = sides[sideIndex]
					local step = -1
					return function()
						step = step + 1
						if step < side.n then
							return { side.x + step * side.stepX - offsetX,
							         side.y + step * side.stepY - offsetY }
						end
					end
				end
			end
		end
	end
end

return M
