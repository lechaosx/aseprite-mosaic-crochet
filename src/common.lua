local M = {}

-- Iterator utilities

function M.filter(sourceIterator, predicate)
	return coroutine.wrap(function()
		for currentItem in sourceIterator do
			if predicate(currentItem) then
				coroutine.yield(currentItem)
			end
		end
	end)
end

function M.map(sourceIterator, transformFunction)
	return coroutine.wrap(function()
		for currentItem in sourceIterator do
			coroutine.yield(transformFunction(currentItem))
		end
	end)
end

-- Colors
M.COLOR_TRANSPARENT = 0
M.COLOR_A = 1
M.COLOR_B = 2
M.HIGHLIGHT_VALID_OVERLAY = 3
M.HIGHLIGHT_INVALID_PLACEMENT = 4

-- Layer names
M.LAYER_PATTERN = "Crochet Pattern"
M.LAYER_HIGHLIGHTS = "Mosaic Highlights"

-- Mosaic modes
M.MODE_ROW = "row"
M.MODE_ROUND = "round"

-- Squared Euclidean distance in RGB space (alpha ignored).
function M.getColorDistance(c1, c2)
	return (c1.red - c2.red)^2 + (c1.green - c2.green)^2 + (c1.blue - c2.blue)^2
end

-- Returns COLOR_A or COLOR_B, whichever is closer to `color` in RGB space.
-- Ties resolve to COLOR_A.
function M.nearestColorIndex(color, colorA, colorB)
	return M.getColorDistance(color, colorA) <= M.getColorDistance(color, colorB)
		and M.COLOR_A or M.COLOR_B
end

-- Pure row-highlight computation. No Aseprite API dependencies.
-- W, H           = image dimensions
-- getPixel(x, y) → current color index
-- setHighlight(x, y, c) → called to write a highlight color
-- highlights is a flat table indexed as highlights[y * W + x], initialised to 0.
function M.computeRowHighlights(W, H, getPixel, highlights)
	for y = 0, H - 1 do
		local colorIndex = M.getColorIndex(M.getRowIndex(H, y))
		for x = 0, W - 1 do
			if colorIndex ~= getPixel(x, y) then
				if y == 0 then
					-- Top row: always INVALID (no row above to host an
					-- overlay). Marker stays at the wrong cell.
					highlights[y * W + x] = M.HIGHLIGHT_INVALID_PLACEMENT
				elseif y == H - 1 then
					-- Foundation: always VALID (no inner row to clash with).
					-- Marker lives on the overlay row above. Precedence
					-- defers to a mid-pattern INVALID already at that row.
					local overlayIndex = (y - 1) * W + x
					if highlights[overlayIndex] ~= M.HIGHLIGHT_INVALID_PLACEMENT then
						highlights[overlayIndex] = M.HIGHLIGHT_VALID_OVERLAY
					end
				else
					-- Mid-pattern: clash → INVALID at the wrong cell; no clash
					-- → VALID at the overlay row above (precedence defers to
					-- a top-row INVALID already at row 0).
					local innerPixel = getPixel(x, y + 1)
					if colorIndex == innerPixel then
						highlights[y * W + x] = M.HIGHLIGHT_INVALID_PLACEMENT
					elseif highlights[(y - 1) * W + x] ~= M.HIGHLIGHT_INVALID_PLACEMENT then
						highlights[(y - 1) * W + x] = M.HIGHLIGHT_VALID_OVERLAY
					end
				end
			end
		end
	end
end

function M.getColorIndex(index)
	return index % 2 == 0 and M.COLOR_A or M.COLOR_B
end

function M.getRowIndex(height, y)
	return height - 1 - y
end

function M.getRoundFromEdge(width, height, x, y)
	local minDistX = math.min(x, width - 1 - x)
	local minDistY = math.min(y, height - 1 - y)
	return math.min(minDistX, minDistY)
end

function M.getRoundIndex(width, height, rounds, x, y)
	local roundFromEdge = M.getRoundFromEdge(width, height, x, y)
	return rounds - 1 - roundFromEdge
end

-- Pure highlight computation for round mode. No Aseprite API dependencies.
-- Assumes inner-hole pixels have already been cleared (see clearRoundInnerHole).
-- W, H        = physical image dimensions
-- vW, vH      = virtual image dimensions
-- offX, offY  = virtual offset (vx = x + offX, vy = y + offY)
-- rounds      = number of rounds
-- getPixel(x, y)        → current color index at physical pixel
-- setHighlight(x, y, c) → called to write a highlight color
function M.computeRoundHighlights(W, H, vW, vH, offX, offY, rounds, getPixel, highlights)
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local vx = x + offX
			local vy = y + offY
			local minDistX = math.min(vx, vW - 1 - vx)
			local minDistY = math.min(vy, vH - 1 - vy)
			local roundFromEdge = math.min(minDistX, minDistY)

			if roundFromEdge < rounds then
				local colorIndex = M.getColorIndex(rounds - 1 - roundFromEdge)

				if colorIndex ~= getPixel(x, y) then
					-- Outermost ring or corner (diagonal cell): INVALID at
					-- the wrong cell. Aseprite renders the highlights layer
					-- directly with no shift transform, so storing INVALID at
					-- the outward target would either fall outside the canvas
					-- (outermost) or split awkwardly across two cells
					-- (corner). The wrong cell is always inside the canvas
					-- and reads cleanly.
					if minDistX == minDistY or roundFromEdge == 0 then
						highlights[y * W + x] = M.HIGHLIGHT_INVALID_PLACEMENT
					else
						local stepX, stepY = 0, 0
						if minDistX < minDistY then
							stepX = (vx * 2 >= vW) and -1 or 1
						else
							stepY = (vy * 2 >= vH) and -1 or 1
						end

						local nx, ny = x + stepX, y + stepY

						local isSeam
						if nx < 0 or nx >= W or ny < 0 or ny >= H then
							isSeam = true
						else
							local neighborRFE = M.getRoundFromEdge(vW, vH, nx + offX, ny + offY)
							isSeam = neighborRFE <= roundFromEdge
						end

						-- VALID marker lives on the overlay ring above
						-- (overlay_target = (x - stepX, y - stepY)); INVALID
						-- stays at the wrong cell (same reasoning as the
						-- outermost/corner case).
						local overlayIndex = (y - stepY) * W + (x - stepX)
						if isSeam then
							if highlights[overlayIndex] ~= M.HIGHLIGHT_INVALID_PLACEMENT then
								highlights[overlayIndex] = M.HIGHLIGHT_VALID_OVERLAY
							end
						elseif colorIndex == getPixel(nx, ny) then
							highlights[y * W + x] = M.HIGHLIGHT_INVALID_PLACEMENT
						elseif highlights[overlayIndex] ~= M.HIGHLIGHT_INVALID_PLACEMENT then
							highlights[overlayIndex] = M.HIGHLIGHT_VALID_OVERLAY
						end
					end
				end
			end
		end
	end
end

return M
