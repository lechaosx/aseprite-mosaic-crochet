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

local function isMainColorRow(sprite, y)
	return (sprite.height - 1 - y) % 2 == 1
end

local function isMainColor(color)
	return color == 0
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

	local highlightLayer = getLayerByName(sprite, "Mosaic Highlights")
	if not highlightLayer then
		highlightLayer = sprite:newLayer()
		highlightLayer.name = "Mosaic Highlights"
		highlightLayer.opacity = 127
		app.activeLayer = patternLayer
	end

	for y = sprite.height - 1, 0, -1 do
		for x = 0, sprite.width - 1 do
			local pixelValue = cel.image:getPixel(x, y)
			if pixelValue > 1 then
				local color = sprite.palettes[1]:getColor(pixelValue)
				local brightness = 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
				pixelValue = (brightness > 127) and 0 or 1
				cel.image:drawPixel(x, y, pixelValue)
			end
		end
	end

	local highlightImage = Image(sprite.spec)

	for y = 0, sprite.height - 1 do
		local mainColorRow = isMainColorRow(sprite, y)

		for x = 0, sprite.width - 1 do
			local pixelValue = cel.image:getPixel(x, y)

			if mainColorRow ~= isMainColor(pixelValue) then
				if y <= 0 or y >= sprite.height - 1 then
					highlightImage:drawPixel(x, y, invalidColorIndex)
				else
					if mainColorRow == isMainColor(cel.image:getPixel(x, y + 1)) then
						highlightImage:drawPixel(x, y, 3)
					else
						highlightImage:drawPixel(x, y, 2)
					end
				end
			end
		end
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
	dlg:number{ id="width", label="Width:", decimals=0, text="32" }
	   :number{ id="height", label="Height:", decimals=0, text="32" }
	   :button{ id="ok", text="OK" }
	   :button{ id="cancel", text="Cancel" }
	dlg:show()

	local data = dlg.data
	if not data.ok then return end

	local white = Color(255, 255, 255, 255)
	local black = Color(0, 0, 0, 255)
	local blue = Color(0, 0, 255, 255)
	local red = Color(255, 0, 0, 255)

	local spec = ImageSpec{
		width=data.width,
		height=data.height,
		colorMode=ColorMode.INDEXED,
		transparentColor=-1
	}

	local sprite = Sprite(spec)
	sprite.layers[1].name = "Crochet Pattern"

	sprite.palettes[1]:resize(4)
	sprite.palettes[1]:setColor(0, white)
	sprite.palettes[1]:setColor(1, black)
	sprite.palettes[1]:setColor(2, blue)
	sprite.palettes[1]:setColor(3, red)

	local patternLayer = sprite.layers[1]
	local cel = sprite:newCel(patternLayer, 1)

	for y = 0, sprite.height - 1 do
		local colorIndex = isMainColorRow(sprite, y) and 0 or 1
		for x = 0, sprite.width - 1 do
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