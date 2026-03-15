local common = require("src.common")
local export = require("src.export")

-- Helper functions moved to common.lua
local function getLayerByName(sprite, name)
	for _, l in ipairs(sprite.layers) do
		if l.name == name then
			return l
		end
	end
	return nil
end

local function getColorDistance(c1, c2)
    return (c1.red - c2.red)^2 + (c1.green - c2.green)^2 + (c1.blue - c2.blue)^2
end

local function normalizeImage(sprite, image)
	local palette = sprite.palettes[1]
	local colorA = palette:getColor(common.COLOR_A)
	local colorB = palette:getColor(common.COLOR_B)

	for y = 0, sprite.height - 1 do
		for x = 0, sprite.width - 1 do
			local pixelValue = image:getPixel(x, y)
			if pixelValue ~= common.COLOR_A and pixelValue ~= common.COLOR_B then
                local color = palette:getColor(pixelValue)
                local distA = getColorDistance(color, colorA)
                local distB = getColorDistance(color, colorB)
				image:drawPixel(x, y, (distA <= distB) and common.COLOR_A or common.COLOR_B)
			end
		end
	end
end

local function updateRowHighlights(sprite, cel, highlightImage)
	for y = 0, sprite.height - 1 do
		local colorIndex = common.getColorIndex(common.getRowIndex(sprite, y))
		for x = 0, sprite.width - 1 do
			local pixelValue = cel.image:getPixel(x, y)
			local mainColorMatch = (colorIndex == pixelValue)

			if not mainColorMatch then
				if y <= 0 or y >= sprite.height - 1 then
					highlightImage:drawPixel(x, y, common.HIGHLIGHT_INVALID_PLACEMENT) -- Invalid
				else
					local innerPixel = cel.image:getPixel(x, y + 1)
					if colorIndex == innerPixel then
						highlightImage:drawPixel(x, y, common.HIGHLIGHT_INVALID_PLACEMENT) -- Invalid
					else
						highlightImage:drawPixel(x, y - 1, common.HIGHLIGHT_VALID_OVERLAY) -- Valid overlay, highlight row ABOVE
					end
				end
			end
		end
	end
end

local function updateCenterHighlights(sprite, cel, highlightImage)
	local centerX = math.floor(sprite.width / 2)
	local centerY = math.floor(sprite.height / 2)
	local innerRadius = sprite.properties.innerRadius or 0
	local maxRoundDist = centerX

	for y = centerY - innerRadius, centerY + innerRadius do
		for x = centerX - innerRadius, centerX + innerRadius do
			cel.image:drawPixel(x, y, common.COLOR_TRANSPARENT)
		end
	end

	for y = 0, sprite.height - 1 do
		local dy = math.abs(y - centerY)

		for x = 0, sprite.width - 1 do
			local dx = math.abs(x - centerX)

			local roundDist = math.max(dx, dy)

			if roundDist > innerRadius then
				local colorIndex = common.getColorIndex(common.roundDistanceToRoundIndex(sprite, roundDist))

				if colorIndex ~= cel.image:getPixel(x, y) then
					if dx == dy or roundDist == maxRoundDist then
						highlightImage:drawPixel(x, y, common.HIGHLIGHT_INVALID_PLACEMENT) -- Invalid
					else
						local stepX, stepY = 0, 0
						if dx > dy then
							stepX = (x > centerX) and -1 or 1
						else
							stepY = (y > centerY) and -1 or 1
						end

						if colorIndex == cel.image:getPixel(x + stepX, y + stepY) then
							highlightImage:drawPixel(x, y, common.HIGHLIGHT_INVALID_PLACEMENT) -- Invalid
						else
							highlightImage:drawPixel(x - stepX, y - stepY, common.HIGHLIGHT_VALID_OVERLAY) -- Valid overlay, highlight round ABOVE
						end
					end
				end
			end
		end
	end
end

local activeCrochetSprite = nil
local crochetChangeCallback = nil

local function updateHighlights(sprite)
    if sprite.colorMode ~= ColorMode.INDEXED then
        return
    end

	if app.activeLayer.name ~= common.LAYER_PATTERN and app.activeLayer.name ~= common.LAYER_HIGHLIGHTS then
		return
	end

	local patternLayer = getLayerByName(sprite, common.LAYER_PATTERN)
	if not patternLayer then return end

	local cel = patternLayer:cel(app.activeFrame)
	if not cel then return end

	normalizeImage(sprite, cel.image)

	local highlightLayer = getLayerByName(sprite, common.LAYER_HIGHLIGHTS)
	if not highlightLayer then
		highlightLayer = sprite:newLayer()
		highlightLayer.name = common.LAYER_HIGHLIGHTS
		highlightLayer.opacity = 127
		app.activeLayer = patternLayer
	end

	local highlightImage = Image(sprite.spec)
	if sprite.properties.mosaicMode == common.MODE_CENTER then
		updateCenterHighlights(sprite, cel, highlightImage)
	else
		updateRowHighlights(sprite, cel, highlightImage)
	end

	local highlightCel = highlightLayer:cel(app.activeFrame)
	if highlightCel then
		highlightCel.image = highlightImage
		highlightCel.position = Point(0, 0)
	else
		sprite:newCel(highlightLayer, app.activeFrame, highlightImage)
	end

	app.refresh()
end

local function isCrochetable(sprite)
	local highlightLayer = getLayerByName(sprite, common.LAYER_HIGHLIGHTS)
	if not highlightLayer then
		return true -- If no highlight layer, assume it's okay (or maybe warn? but request said check if crochetable)
	end
	local highlightCel = highlightLayer:cel(app.activeFrame)
	if not highlightCel then
		return true
	end
	local image = highlightCel.image
	for it in image:pixels() do
		local pixelValue = it()
		if pixelValue == common.HIGHLIGHT_INVALID_PLACEMENT then
			return false
		end
	end
	return true
end

local function exportToTxt()
	local sprite = app.sprite
	if not sprite or not sprite.properties.mosaicMode or sprite.colorMode ~= ColorMode.INDEXED then
		app.alert("Not a mosaic crochet pattern sprite!")
		return
	end

	-- Before dialog, check if the pattern is crochetable at all.
	if not isCrochetable(sprite) then
		app.alert("Pattern is not crochetable! Please fix invalid placements (red highlights) before exporting.")
		return
	end

	local patternLayer = getLayerByName(sprite, common.LAYER_PATTERN)
	if not patternLayer then
		app.alert("Crochet Pattern layer not found!")
		return
	end

	local cel = patternLayer:cel(app.activeFrame)
	if not cel then
		app.alert("No pattern found in the active frame!")
		return
	end

	local dlg = Dialog("Export Mosaic Pattern")
	dlg:combobox{ id="direction", label="Direction:", options={ "Same Direction", "Altering Directions" }, selected="Same Direction" }
	dlg:file{ id="file", label="Save to:", filename="pattern.txt", save=true, filetypes={"txt"} }
	   :button{ id="ok", text="OK" }
	   :button{ id="cancel", text="Cancel" }

	dlg:show()

	local data = dlg.data
	if not data.ok or not data.file or data.file == "" then return end

	local highlightLayer = getLayerByName(sprite, common.LAYER_HIGHLIGHTS)
	local highlightCel = highlightLayer and highlightLayer:cel(app.activeFrame) or nil

	local sameDirection = (data.direction == "Same Direction")

	local params = {
		sprite = sprite,
		cel = cel,
		highlightCel = highlightCel,
		sameDirection = sameDirection
	}

	local resultData = {}
	if sprite.properties.mosaicMode == common.MODE_CENTER then
		resultData = export.exportCenter(params)
	else
		resultData = export.exportRow(params)
	end

	local function serializeStitch(item)
		if item.type == "stitch" then
			return item.stitch
		elseif item.type == "group" then
			local serializedStitches = {}
			for _, stitch in ipairs(item.stitches) do
				table.insert(serializedStitches, serializeStitch(stitch))
			end
			return "(" .. table.concat(serializedStitches, ", ") .. ")"
		elseif item.type == "repeat" then
			local serializedStitches = {}
			for _, stitch in ipairs(item.stitches) do
				table.insert(serializedStitches, serializeStitch(stitch))
			end
			return "[" .. table.concat(serializedStitches, ", ") .. "] x " .. tostring(item.repeats)
		end

		error("Unknown export item type: " .. tostring(item.type))
	end

	local label = (sprite.properties.mosaicMode == common.MODE_CENTER) and "Round " or "Row "
	local result = ""
	for _, item in ipairs(resultData) do
		local serializedStitches = {}
		for _, stitch in ipairs(item.stitches) do
			table.insert(serializedStitches, serializeStitch(stitch))
		end
		result = result .. label .. item.index .. ": " .. table.concat(serializedStitches, ", ") .. "\n"
	end

	local f = io.open(data.file, "w")
	if f then
		f:write(result)
		f:close()
	else
		app.alert("Failed to open file for writing!")
	end
end

local function reattachCrochetCallbacks()
	local sprite = app.sprite
	-- No-op if the sprite is already active and same as before.
	if activeCrochetSprite == sprite and sprite ~= nil then
		return
	end

	-- Detach current crochet pattern's change callback if it exists.
	-- This ensures that only the active sprite has an active listener, preventing "zombie" listeners.
	if activeCrochetSprite and crochetChangeCallback then
		-- Aseprite's Events:off() requires the exact function reference to remove it.
		activeCrochetSprite.events:off(crochetChangeCallback)
	end
	activeCrochetSprite = nil
	crochetChangeCallback = nil

	-- If new sprite doesn't have mosaicMode or is not in INDEXED color mode, we just finished detaching.
	if not sprite or not sprite.properties.mosaicMode or sprite.colorMode ~= ColorMode.INDEXED then
		return
	end

	-- Store the callback function reference for future detachment.
	crochetChangeCallback = function(ev)
		updateHighlights(sprite)
	end

	-- Start listening to changes on the new sprite.
	sprite.events:on("change", crochetChangeCallback)
	activeCrochetSprite = sprite

	-- Run an initial update immediately when the sprite is first attached.
	updateHighlights(sprite)
end

local function createMosaicSprite()
	local dlg = Dialog("New Mosaic Pattern")
	dlg:combobox{ id="mode", label="Mode:", options={ common.MODE_ROW, common.MODE_CENTER }, selected=common.MODE_ROW, onchange=function()
		dlg:modify{ id="width", visible = dlg.data.mode == common.MODE_ROW }
		dlg:modify{ id="height", visible = dlg.data.mode == common.MODE_ROW }
		dlg:modify{ id="innerRadius", visible = dlg.data.mode == common.MODE_CENTER }
		dlg:modify{ id="rounds", visible = dlg.data.mode == common.MODE_CENTER }
	end }
	   :number{ id="width", label="Width:", decimals=0, text="32", visible=true }
	   :number{ id="height", label="Height:", decimals=0, text="32", visible=true }
	   :number{ id="innerRadius", label="Inner Radius:", decimals=0, text="0", visible=false }
	   :number{ id="rounds", label="Rounds:", decimals=0, text="5", visible=false }
	   :button{ id="ok", text="OK" }
	   :button{ id="cancel", text="Cancel" }

	dlg:show()

	local data = dlg.data
	if not data.ok then return end

	local width, height
	if data.mode == common.MODE_CENTER then
		width = (data.innerRadius + data.rounds) * 2 + 1
		height = width
	else
		width = data.width
		height = data.height
	end

	local spec = ImageSpec{
		width=width,
		height=height,
		colorMode=ColorMode.INDEXED,
		transparentColor=common.COLOR_TRANSPARENT
	}

	local sprite = Sprite(spec)
	sprite.properties.mosaicMode = data.mode
	if data.mode == common.MODE_CENTER then
		sprite.properties.innerRadius = data.innerRadius
	end

	sprite.layers[1].name = common.LAYER_PATTERN

	sprite.palettes[1]:resize(5)
	sprite.palettes[1]:setColor(common.COLOR_TRANSPARENT, Color(0, 0, 0, 0))
	sprite.palettes[1]:setColor(common.COLOR_A, Color(0, 0, 0, 255))
	sprite.palettes[1]:setColor(common.COLOR_B, Color(255, 255, 255, 255))
	sprite.palettes[1]:setColor(common.HIGHLIGHT_VALID_OVERLAY, Color(0, 0, 255, 255))
	sprite.palettes[1]:setColor(common.HIGHLIGHT_INVALID_PLACEMENT, Color(255, 0, 0, 255))

	local patternLayer = sprite.layers[1]
	local cel = sprite:newCel(patternLayer, 1)

	for y = 0, sprite.height - 1 do
		for x = 0, sprite.width - 1 do
			local colorIdx

			if sprite.properties.mosaicMode == common.MODE_CENTER then
				local roundIdx = common.getRoundIndex(sprite, x, y)
				if roundIdx < 0 then
					colorIdx = common.COLOR_TRANSPARENT
				else
					colorIdx = common.getColorIndex(roundIdx)
				end
			else
				local index = common.getRowIndex(sprite, y)
				colorIdx = common.getColorIndex(index)
			end

			cel.image:putPixel(x, y, colorIdx)
		end
	end

	app.fgColor = common.COLOR_A
	app.bgColor = common.COLOR_B

	reattachCrochetCallbacks()
end

function init(plugin)
	-- Register the command to create a new mosaic crochet sprite.
	plugin:newCommand{
		id="new_mosaic_sprite",
		title="New Mosaic Crochet Sprite",
		group="file_new",
		onclick=createMosaicSprite
	}

	plugin:newCommand{
		id="export_mosaic_to_txt",
		title="Export Mosaic to TXT",
		group="file_export",
		onclick=exportToTxt
	}

	-- Listen for site changes (switching between sprites or closing files).
	-- This keeps the real-time highlights synced with the currently focused sprite.
	app.events:on("sitechange", reattachCrochetCallbacks)

	-- If a mosaic crochet sprite is already open when the plugin is loaded or reloaded,
	-- ensure its highlights and callbacks are initialized immediately.
	reattachCrochetCallbacks()
end
