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

function M.getRowIndex(sprite, y)
	return sprite.height - 1 - y
end

function M.roundDistanceToRoundIndex(sprite, roundDistance)
	return roundDistance - (sprite.properties.innerRadius or 0) - 1
end

function M.getRoundIndex(sprite, x, y)
	local centerX = math.floor(sprite.width / 2)
	local centerY = math.floor(sprite.height / 2)
	local dx = math.abs(x - centerX)
	local dy = math.abs(y - centerY)
	local roundDistance = math.max(dx, dy)
	return M.roundDistanceToRoundIndex(sprite, roundDistance)
end

return M
