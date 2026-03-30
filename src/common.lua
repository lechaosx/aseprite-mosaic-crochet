local M = {}

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
M.MODE_CENTER = "center"

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

return M
