-- Inset Mosaic Crochet Helper
-- Real-time highlights for overlay stitches and invalid overlay placements for inset mosaic crochet.

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
	return index % 2 == 0 and 1 or 0
end

local function normalizeImage(sprite, image)
	local palette = sprite.palettes[1]
	local paletteSize = #palette
	for y = 0, sprite.height - 1 do
		for x = 0, sprite.width - 1 do
			local pixelValue = image:getPixel(x, y)
			if pixelValue > 1 then
				if pixelValue < paletteSize then
					local color = palette:getColor(pixelValue)
					local brightness = 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
					pixelValue = (brightness > 127) and 0 or 1
				else
					pixelValue = 1
				end
				image:drawPixel(x, y, pixelValue)
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
					highlightImage:drawPixel(x, y, 3) -- Invalid
				else
					local innerPixel = cel.image:getPixel(x, y + 1)
					if colorIndex == innerPixel then
						highlightImage:drawPixel(x, y, 3) -- Invalid
					else
						highlightImage:drawPixel(x, y - 1, 2) -- Valid overlay, highlight row ABOVE
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
			cel.image:drawPixel(x, y, -1)
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
						highlightImage:drawPixel(x, y, 3) -- Invalid
					else
						local stepX, stepY = 0, 0
						if dx > dy then
							stepX = (x > centerX) and -1 or 1
						else
							stepY = (y > centerY) and -1 or 1
						end

						if colorIndex == cel.image:getPixel(x + stepX, y + stepY) then
							highlightImage:drawPixel(x, y, 3) -- Invalid
						else
							highlightImage:drawPixel(x - stepX, y - stepY, 2) -- Valid overlay, highlight round ABOVE
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
	if app.activeLayer.name ~= "Crochet Pattern" and app.activeLayer.name ~= "Mosaic Highlights" then
		return
	end

	local patternLayer = getLayerByName(sprite, "Crochet Pattern")
	if not patternLayer then return end

	local cel = patternLayer:cel(app.activeFrame)
	if not cel then return end

	normalizeImage(sprite, cel.image)

	local highlightLayer = getLayerByName(sprite, "Mosaic Highlights")
	if not highlightLayer then
		highlightLayer = sprite:newLayer()
		highlightLayer.name = "Mosaic Highlights"
		highlightLayer.opacity = 127
		app.activeLayer = patternLayer
	end

	local highlightImage = Image(sprite.spec)
	if sprite.properties.mosaicMode == "center" then
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
	sprite.events:on('change', crochetChangeCallback)
	activeCrochetSprite = sprite

	-- Run an initial update immediately when the sprite is first attached.
	updateHighlights(sprite)
end

local function createMosaicSprite()
	local dlg = Dialog("New Mosaic Pattern")
	dlg:combobox{ id="mode", label="Mode:", options={ "row", "center" }, selected="row", onchange=function()
		dlg:modify{ id="width", visible = dlg.data.mode == "row" }
		dlg:modify{ id="height", visible = dlg.data.mode == "row" }
		dlg:modify{ id="innerRadius", visible = dlg.data.mode == "center" }
		dlg:modify{ id="rounds", visible = dlg.data.mode == "center" }
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
	if data.mode == "center" then
		width = (data.innerRadius + data.rounds) * 2 + 1
		height = width
	else
		width = data.width
		height = data.height
	end

	local white = Color(255, 255, 255, 255)
	local black = Color(0, 0, 0, 255)
	local blue = Color(0, 0, 255, 255)
	local red = Color(255, 0, 0, 255)

	local spec = ImageSpec{
		width=width,
		height=height,
		colorMode=ColorMode.INDEXED,
		transparentColor=-1
	}

	local sprite = Sprite(spec)
	sprite.properties.mosaicMode = data.mode
	if data.mode == "center" then
		sprite.properties.innerRadius = data.innerRadius
	end

	sprite.layers[1].name = "Crochet Pattern"

	sprite.palettes[1]:resize(4)
	sprite.palettes[1]:setColor(0, white)
	sprite.palettes[1]:setColor(1, black)
	sprite.palettes[1]:setColor(2, blue)
	sprite.palettes[1]:setColor(3, red)

	local patternLayer = sprite.layers[1]
	local cel = sprite:newCel(patternLayer, 1)

	for y = 0, sprite.height - 1 do
		for x = 0, sprite.width - 1 do
			local colorIdx

			if sprite.properties.mosaicMode == "center" then
				local roundIdx = getRoundIndex(sprite, x, y)
				if roundIdx < 0 then
					colorIdx = -1
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
	app.events:on('sitechange', reattachCrochetCallbacks)

	-- If a mosaic crochet sprite is already open when the plugin is loaded or reloaded,
	-- ensure its highlights and callbacks are initialized immediately.
	reattachCrochetCallbacks()
end