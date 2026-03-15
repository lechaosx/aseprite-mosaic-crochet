local common = require("src.common")

local M = {}

local function makeStitch(kind)
	return { type = "stitch", stitch = kind }
end

local function makeGroup(stitches)
	return { type = "group", stitches = stitches }
end

local function makeRepeat(stitches, repeats)
	return { type = "repeat", stitches = stitches, repeats = repeats }
end

local function makeFoundationRound()
	return makeGroup({
		makeStitch("sc"),
		makeStitch("ch"),
		makeStitch("sc"),
		makeStitch("ch"),
		makeStitch("sc"),
		makeStitch("ch"),
		makeStitch("sc")
	})
end

local function appendAll(target, items)
	for _, item in ipairs(items) do
		table.insert(target, item)
	end
end

local function reversedCopy(items)
	local reversed = {}
	for i = #items, 1, -1 do
		table.insert(reversed, items[i])
	end
	return reversed
end

M.makeRepeat = makeRepeat

local function getCenterSideDescriptors(centerX, centerY, roundDistance)
	return {
		[1] = {
			startX = centerX + roundDistance,
			startY = centerY + roundDistance - 1,
			endX = centerX + roundDistance,
			endY = centerY - roundDistance + 1,
		},
		[2] = {
			startX = centerX + roundDistance - 1,
			startY = centerY - roundDistance,
			endX = centerX - roundDistance + 1,
			endY = centerY - roundDistance,
		},
		[3] = {
			startX = centerX - roundDistance,
			startY = centerY - roundDistance + 1,
			endX = centerX - roundDistance,
			endY = centerY + roundDistance - 1,
		},
		[4] = {
			startX = centerX - roundDistance + 1,
			startY = centerY + roundDistance,
			endX = centerX + roundDistance - 1,
			endY = centerY + roundDistance,
		},
	}
end

local function getTransitionCorner(currentSideId, nextSideId)
	if currentSideId == 1 and nextSideId == 2 then
		return 1
	elseif currentSideId == 2 and nextSideId == 3 then
		return 2
	elseif currentSideId == 3 and nextSideId == 4 then
		return 3
	elseif currentSideId == 4 and nextSideId == 1 then
		return 4
	elseif currentSideId == 4 and nextSideId == 3 then
		return 3
	elseif currentSideId == 3 and nextSideId == 2 then
		return 2
	elseif currentSideId == 2 and nextSideId == 1 then
		return 1
	elseif currentSideId == 1 and nextSideId == 4 then
		return 4
	end

	error("Unsupported side transition: " .. tostring(currentSideId) .. " -> " .. tostring(nextSideId))
end

function M.exportRow(params)
	local sprite = params.sprite
	local cel = params.cel
	local highlightCel = params.highlightCel
	local sameDirection = params.sameDirection
	
	local rows = {}
	local startRow = 1
	local height = sprite.height
	local endRow = height - 1

	for r = startRow, endRow do
		local y = height - 1 - r
		local colorIndex = common.getColorIndex(r)
		local stitches = {}

		local xStart, xEnd, xStep
		if not sameDirection and r % 2 == 1 then
			-- Backwards
			xStart = sprite.width - 1
			xEnd = 0
			xStep = -1
		else
			xStart = 0
			xEnd = sprite.width - 1
			xStep = 1
		end

		for x = xStart, xEnd, xStep do
			local pixelValue = cel.image:getPixel(x, y)
			if pixelValue == colorIndex then
				table.insert(stitches, makeStitch("sc"))
			else
				-- oc/overlay
				local isOverlay = false
				if highlightCel then
					local hPixel = highlightCel.image:getPixel(x, y)
					if hPixel == common.HIGHLIGHT_VALID_OVERLAY then
						isOverlay = true
					end
				else
					-- Fallback if highlights are not available
					local innerPixel = cel.image:getPixel(x, y + 1)
					if innerPixel ~= colorIndex then
						isOverlay = true
					end
				end

				if isOverlay then
					table.insert(stitches, makeStitch("oc"))
				else
					table.insert(stitches, makeStitch("sc"))
				end
			end
		end

		table.insert(rows, { index = r, stitches = stitches })
	end
	return rows
end

function M.exportCenter(params)
	local sprite = params.sprite
	local cel = params.cel
	local highlightCel = params.highlightCel
	local sameDirection = params.sameDirection
	
	local centerX = math.floor(sprite.width / 2)
	local centerY = math.floor(sprite.height / 2)
	local innerRadius = sprite.properties.innerRadius or 0
	local maxRoundDist = centerX
	
	local roundsCount = common.roundDistanceToRoundIndex(sprite, maxRoundDist)
	local rounds = {}

	for r = 1, roundsCount do
		if innerRadius == 0 and r == 1 then
			local stitches = {
				makeFoundationRound(),
				makeStitch("ss")
			}
			table.insert(rounds, { index = r, stitches = stitches })
			goto continue
		end

		local currentRoundDist = innerRadius + r + 1
		local colorIndex = common.getColorIndex(r)
		local reverse = (not sameDirection and r % 2 == 1)

		local function getStitch(x, y, dx, dy)
			local pixelValue = cel.image:getPixel(x, y)
			if pixelValue == colorIndex then
				return makeStitch("sc")
			else
				-- Overlay/oc
				local isOverlay = false
				if highlightCel then
					local hPixel = highlightCel.image:getPixel(x, y)
					if hPixel == common.HIGHLIGHT_VALID_OVERLAY then
						isOverlay = true
					end
				else
					-- Fallback
					local stepX, stepY = 0, 0
					if math.abs(dx) > math.abs(dy) then
						stepX = (x > centerX) and -1 or 1
					else
						stepY = (y > centerY) and -1 or 1
					end
					local innerPixel = cel.image:getPixel(x + stepX, y + stepY)
					if innerPixel ~= colorIndex then
						isOverlay = true
					end
				end
				
				return makeStitch(isOverlay and "oc" or "sc")
			end
		end

		local function collectSide(startX, startY, endX, endY)
			local side = {}
			local dx = (endX > startX) and 1 or (endX < startX and -1 or 0)
			local dy = (endY > startY) and 1 or (endY < startY and -1 or 0)
			local x, y = startX, startY
			while true do
				table.insert(side, getStitch(x, y, x - centerX, y - centerY))
				if x == endX and y == endY then break end
				x = x + dx
				y = y + dy
			end
			return side
		end

		local sideDescriptors = getCenterSideDescriptors(centerX, centerY, currentRoundDist)
		local sides = {}
		for sideId = 1, 4 do
			local descriptor = sideDescriptors[sideId]
			sides[sideId] = collectSide(descriptor.startX, descriptor.startY, descriptor.endX, descriptor.endY)
		end

		if reverse then
			for sideId = 1, 4 do
				sides[sideId] = reversedCopy(sides[sideId])
			end
		end

		local stitches = { makeStitch("sc") }
		local sideOrder = reverse and { 4, 3, 2, 1 } or { 1, 2, 3, 4 }
		for i, sideId in ipairs(sideOrder) do
			appendAll(stitches, sides[sideId])
			if i < #sideOrder then
				local nextSideId = sideOrder[i + 1]
				local cornerId = getTransitionCorner(sideId, nextSideId)
				if cornerId ~= 4 then
					table.insert(stitches, makeGroup({
						makeStitch("sc"),
						makeStitch("ch"),
						makeStitch("sc")
					}))
				end
			end
		end

		table.insert(stitches, makeStitch("ss"))

		table.insert(rounds, { index = r, stitches = stitches })
		::continue::
	end
	return rounds
end

return M
