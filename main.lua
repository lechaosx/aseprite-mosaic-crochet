-- Inset Mosaic Crochet Helper
-- Real-time highlights for overlay stitches and invalid overlay placements for inset mosaic crochet.

-- Colors
local COLOR_TRANSPARENT = 0
local COLOR_A = 1
local COLOR_B = 2
local HIGHLIGHT_VALID_OVERLAY = 3
local HIGHLIGHT_INVALID_PLACEMENT = 4

-- Layer names
local LAYER_PATTERN = "Crochet Pattern"
local LAYER_HIGHLIGHTS = "Mosaic Highlights"

-- Mosaic modes
local MODE_ROW = "row"
local MODE_CENTER = "center"

local function getLayerByName(sprite, name)
	for _, l in ipairs(sprite.layers) do
		if l.name == name then
			return l
		end
	end
	return nil
end

local function getRowIndex(sprite, y)
	return sprite.height - 1 - y
end

local function roundDistanceToRoundIndex(sprite, roundDistance)
	return roundDistance - sprite.properties.innerRadius - 1
end

local function getRoundIndex(sprite, x, y)
	local centerX = math.floor(sprite.width / 2)
	local centerY = math.floor(sprite.height / 2)
	local dx = math.abs(x - centerX)
	local dy = math.abs(y - centerY)
	local roundDistance = math.max(dx, dy)
	return roundDistanceToRoundIndex(sprite, roundDistance)
end

local function getColorIndex(index)
	return index % 2 == 0 and COLOR_A or COLOR_B
end

local function getColorDistance(c1, c2)
    return (c1.red - c2.red)^2 + (c1.green - c2.green)^2 + (c1.blue - c2.blue)^2
end

local function normalizeImage(sprite, image)
	local palette = sprite.palettes[1]
	local paletteSize = #palette
	local colorA = palette:getColor(COLOR_A)
	local colorB = palette:getColor(COLOR_B)

	for y = 0, sprite.height - 1 do
		for x = 0, sprite.width - 1 do
			local pixelValue = image:getPixel(x, y)
			if pixelValue ~= COLOR_A and pixelValue ~= COLOR_B then
                local color = palette:getColor(pixelValue)
                local distA = getColorDistance(color, colorA)
                local distB = getColorDistance(color, colorB)
				image:drawPixel(x, y, (distA <= distB) and COLOR_A or COLOR_B)
			end
		end
	end
end

local function updateRowHighlights(sprite, cel, highlightImage)
	for y = 0, sprite.height - 1 do
		local colorIndex = getColorIndex(getRowIndex(sprite, y))
		for x = 0, sprite.width - 1 do
			local pixelValue = cel.image:getPixel(x, y)
			local mainColorMatch = (colorIndex == pixelValue)

			if not mainColorMatch then
				if y <= 0 or y >= sprite.height - 1 then
					highlightImage:drawPixel(x, y, HIGHLIGHT_INVALID_PLACEMENT) -- Invalid
				else
					local innerPixel = cel.image:getPixel(x, y + 1)
					if colorIndex == innerPixel then
						highlightImage:drawPixel(x, y, HIGHLIGHT_INVALID_PLACEMENT) -- Invalid
					else
						highlightImage:drawPixel(x, y - 1, HIGHLIGHT_VALID_OVERLAY) -- Valid overlay, highlight row ABOVE
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
	local maxRoundDist = math.max(centerX, centerY)

	for y = centerY - innerRadius, centerY + innerRadius do
		for x = centerX - innerRadius, centerX + innerRadius do
			cel.image:drawPixel(x, y, COLOR_TRANSPARENT)
		end
	end

	for y = 0, sprite.height - 1 do
		local dy = math.abs(y - centerY)

		for x = 0, sprite.width - 1 do
			local dx = math.abs(x - centerX)

			local roundDist = math.max(dx, dy)

			if roundDist > innerRadius then
				local colorIndex = getColorIndex(roundDistanceToRoundIndex(sprite, roundDist))

				if colorIndex ~= cel.image:getPixel(x, y) then
					if dx == dy or roundDist == maxRoundDist then
						highlightImage:drawPixel(x, y, HIGHLIGHT_INVALID_PLACEMENT) -- Invalid
					else
						local stepX, stepY = 0, 0
						if dx > dy then
							stepX = (x > centerX) and -1 or 1
						else
							stepY = (y > centerY) and -1 or 1
						end

						if colorIndex == cel.image:getPixel(x + stepX, y + stepY) then
							highlightImage:drawPixel(x, y, HIGHLIGHT_INVALID_PLACEMENT) -- Invalid
						else
							highlightImage:drawPixel(x - stepX, y - stepY, HIGHLIGHT_VALID_OVERLAY) -- Valid overlay, highlight round ABOVE
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
	-- Recompute when user tries to draw on mosaic highlight
	if app.activeLayer.name ~= LAYER_PATTERN and app.activeLayer.name ~= LAYER_HIGHLIGHTS then
		return
	end

	local patternLayer = getLayerByName(sprite, LAYER_PATTERN)
	if not patternLayer then return end

	local cel = patternLayer:cel(app.activeFrame)
	if not cel then return end

	normalizeImage(sprite, cel.image)

	local highlightLayer = getLayerByName(sprite, LAYER_HIGHLIGHTS)
	if not highlightLayer then
		highlightLayer = sprite:newLayer()
		highlightLayer.name = LAYER_HIGHLIGHTS
		highlightLayer.opacity = 127
		app.activeLayer = patternLayer
	end

	local highlightImage = Image(sprite.spec)
	if sprite.properties.mosaicMode == MODE_CENTER then
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

-- Reattaches the crochet pattern's change callback to the current active sprite.
-- If app.sprite is nil or not a mosaic crochet pattern, it just detaches current listener.
-- This automatically detaches from any previous sprite.
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

	-- If new sprite doesn't have mosaicMode, we just finished detaching.
	if not sprite or not sprite.properties.mosaicMode then
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
	dlg:combobox{ id="mode", label="Mode:", options={ MODE_ROW, MODE_CENTER }, selected=MODE_ROW, onchange=function()
		dlg:modify{ id="width", visible = dlg.data.mode == MODE_ROW }
		dlg:modify{ id="height", visible = dlg.data.mode == MODE_ROW }
		dlg:modify{ id="innerRadius", visible = dlg.data.mode == MODE_CENTER }
		dlg:modify{ id="rounds", visible = dlg.data.mode == MODE_CENTER }
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
	if data.mode == MODE_CENTER then
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
		transparentColor=COLOR_TRANSPARENT
	}

	local sprite = Sprite(spec)
	sprite.properties.mosaicMode = data.mode
	if data.mode == MODE_CENTER then
		sprite.properties.innerRadius = data.innerRadius
	end

	sprite.layers[1].name = LAYER_PATTERN

	sprite.palettes[1]:resize(5)
	sprite.palettes[1]:setColor(COLOR_TRANSPARENT, Color(0, 0, 0, 0))
	sprite.palettes[1]:setColor(COLOR_A, Color(0, 0, 0, 255))
	sprite.palettes[1]:setColor(COLOR_B, Color(255, 255, 255, 255))
	sprite.palettes[1]:setColor(HIGHLIGHT_VALID_OVERLAY, Color(0, 0, 255, 255))
	sprite.palettes[1]:setColor(HIGHLIGHT_INVALID_PLACEMENT, Color(255, 0, 0, 255))

	local patternLayer = sprite.layers[1]
	local cel = sprite:newCel(patternLayer, 1)

	for y = 0, sprite.height - 1 do
		for x = 0, sprite.width - 1 do
			local colorIdx

			if sprite.properties.mosaicMode == MODE_CENTER then
				local roundIdx = getRoundIndex(sprite, x, y)
				if roundIdx < 0 then
					colorIdx = COLOR_TRANSPARENT
				else
					colorIdx = getColorIndex(roundIdx)
				end
			else
				local index = getRowIndex(sprite, y)
				colorIdx = getColorIndex(index)
			end

			cel.image:putPixel(x, y, colorIdx)
		end
	end

	app.fgColor = white
	app.bgColor = black

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

	-- Listen for site changes (switching between sprites or closing files).
	-- This keeps the real-time highlights synced with the currently focused sprite.
	app.events:on("sitechange", reattachCrochetCallbacks)

	-- If a mosaic crochet sprite is already open when the plugin is loaded or reloaded,
	-- ensure its highlights and callbacks are initialized immediately.
	reattachCrochetCallbacks()
end