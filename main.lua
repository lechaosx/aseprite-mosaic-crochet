-- Inset Mosaic Crochet Helper
-- Real-time highlights for DC stitches and invalid DC placements for inset mosaic crochet.

local function getLayerByName(sprite, name)
	for _, l in ipairs(sprite.layers) do
		if l.name == name then
			return l
		end
	end
	return nil
end

local function isMainColorRound(sprite, x, y)
	local centerX = math.floor(sprite.width / 2)
	local centerY = math.floor(sprite.height / 2)
	local dx = math.abs(x - centerX)
	local dy = math.abs(y - centerY)
	local round = math.max(dx, dy)
	if round == 0 then return nil end -- Center pixel is transparent/special

	local innerRadius = sprite.properties.innerRadius or 0
	return (round - innerRadius) % 2 == 1, round
end

local function isMainColorRow(sprite, y)
	return (sprite.height - 1 - y) % 2 == 1
end

local function isMainColor(color)
	return color == 0
end

local function normalizeImage(sprite, image)
	for y = 0, sprite.height - 1 do
		for x = 0, sprite.width - 1 do
			local pixelValue = image:getPixel(x, y)
			if pixelValue > 1 then
				local color = sprite.palettes[1]:getColor(pixelValue)
				local brightness = 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
				pixelValue = (brightness > 127) and 0 or 1
				image:drawPixel(x, y, pixelValue)
			end
		end
	end
end

local function updateRowHighlights(sprite, cel, highlightImage)
	for y = 0, sprite.height - 1 do
		for x = 0, sprite.width - 1 do
			local pixelValue = cel.image:getPixel(x, y)
			local isMainRow = isMainColorRow(sprite, y)
			local mainColorMatch = (isMainRow == isMainColor(pixelValue))

			if not mainColorMatch then
				if y <= 0 or y >= sprite.height - 1 then
					highlightImage:drawPixel(x, y, 3) -- Invalid
				else
					local innerPixel = cel.image:getPixel(x, y + 1)
					if isMainRow == isMainColor(innerPixel) then
						highlightImage:drawPixel(x, y, 3)
					else
						highlightImage:drawPixel(x, y, 2)
					end
				end
			end
		end
	end
end

local function updateCenterHighlights(sprite, cel, highlightImage)
	local centerX = math.floor(sprite.width / 2)
	local centerY = math.floor(sprite.height / 2)

	cel.image:drawPixel(centerX, centerY, -1) -- Keep center pixel transparent

	for y = 0, sprite.height - 1 do
		for x = 0, sprite.width - 1 do
			if x == centerX and y == centerY then
				goto continue
			end

			local pixelValue = cel.image:getPixel(x, y)
			local isMain, round = isMainColorRound(sprite, x, y)
			local mainColorMatch = (isMain == isMainColor(pixelValue))

			local dx = math.abs(x - centerX)
			local dy = math.abs(y - centerY)
			local isCorner = (dx == round and dy == round)

			if not mainColorMatch then
				if isCorner then
					highlightImage:drawPixel(x, y, 3) -- Invalid
				else
					-- Find inner round coordinates for checking DC
					local innerX, innerY
					if dx > dy then
						innerX = (x > centerX) and (x - 1) or (x + 1)
						innerY = y
					elseif dy > dx then
						innerX = x
						innerY = (y > centerY) and (y - 1) or (y + 1)
					else -- Corner (already handled by isCorner, but kept for completeness if logic changes)
						innerX = (x > centerX) and (x - 1) or (x + 1)
						innerY = (y > centerY) and (y - 1) or (y + 1)
					end

					local innerPixel = cel.image:getPixel(innerX, innerY)
					-- In center mode, DC checks the same pixel's color in the inner round.
					-- The rule is "checks more inner round", which for a DC means it must be different from current round's color.
					if isMain == isMainColor(innerPixel) then
						highlightImage:drawPixel(x, y, 3) -- Invalid
					else
						highlightImage:drawPixel(x, y, 2) -- Valid DC
					end
				end
			end
			::continue::
		end
	end
end

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

local function createMosaicSprite()
	local dlg = Dialog("New Mosaic Pattern")
	dlg:combobox{ id="mode", label="Mode:", options={ "row", "center" }, selected="row" }
	   :number{ id="width", label="Width:", decimals=0, text="32", visible=true }
	   :number{ id="height", label="Height:", decimals=0, text="32", visible=true }
	   :number{ id="innerRadius", label="Inner Radius:", decimals=0, text="0", visible=false }
	   :number{ id="rounds", label="Rounds:", decimals=0, text="5", visible=false }
	   :button{ id="ok", text="OK" }
	   :button{ id="cancel", text="Cancel" }

	dlg:modify{ id="mode", onchange=function()
		local isCenter = (dlg.data.mode == "center")
		dlg:modify{ id="width", visible = not isCenter }
		dlg:modify{ id="height", visible = not isCenter }
		dlg:modify{ id="innerRadius", visible = isCenter }
		dlg:modify{ id="rounds", visible = isCenter }
	end }

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
			local colorIndex
			if data.mode == "center" then
				local isMain, round = isMainColorRound(sprite, x, y)
				if round == 0 then
					colorIndex = -1 -- Transparent
				else
					colorIndex = isMain and 0 or 1
				end
			else
				colorIndex = isMainColorRow(sprite, y) and 0 or 1
			end
			cel.image:putPixel(x, y, colorIndex)
		end
	end

	app.fgColor = white
	app.bgColor = black

	sprite.events:on('change', function(ev)
		updateHighlights(sprite)
	end)
end

function init(plugin)
	plugin:newCommand{
		id="new_mosaic_sprite",
		title="New Mosaic Crochet Sprite",
		group="file_new",
		onclick=createMosaicSprite
	}
end