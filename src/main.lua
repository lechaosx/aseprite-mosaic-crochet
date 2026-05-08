local common  = require("src.common")
local pattern = require("src.pattern")
local vec2    = require("src.vec2")
local walk    = require("src.walk")
-- Real-time highlights for overlay stitches and invalid overlay placements for inset mosaic crochet.

local filter = common.filter
local map    = common.map

local function getLayerByName(sprite, name)
	for _, l in ipairs(sprite.layers) do
		if l.name == name then
			return l
		end
	end
	return nil
end

local function normalizeImage(sprite, image)
	local palette = sprite.palettes[1]
	local colorA = palette:getColor(common.COLOR_A)
	local colorB = palette:getColor(common.COLOR_B)
	for y = 0, sprite.height - 1 do
		for x = 0, sprite.width - 1 do
			local pixelValue = image:getPixel(x, y)
			if pixelValue ~= common.COLOR_A and pixelValue ~= common.COLOR_B then
				image:drawPixel(x, y, common.nearestColorIndex(palette:getColor(pixelValue), colorA, colorB))
			end
		end
	end
	if sprite.properties.mosaicMode == common.MODE_ROUND then
		local vW, vH   = sprite.properties.virtualWidth, sprite.properties.virtualHeight
		local offX, offY = sprite.properties.virtualOffsetX, sprite.properties.virtualOffsetY
		local rounds   = sprite.properties.rounds
		for y = 0, sprite.height - 1 do
			for x = 0, sprite.width - 1 do
				if common.getRoundFromEdge(vW, vH, x + offX, y + offY) >= rounds then
					image:drawPixel(x, y, common.COLOR_TRANSPARENT)
				end
			end
		end
	end
end

local function updateRowHighlights(sprite, cel, highlightImage)
	common.computeRowHighlights(
		sprite.width, sprite.height,
		function(x, y) return cel.image:getPixel(x, y) end,
		function(x, y, c) highlightImage:drawPixel(x, y, c) end
	)
end

-- Physical pixel (x, y) maps to virtual pixel (x + virtualOffsetX, y + virtualOffsetY).
local function updateRoundHighlights(sprite, cel, highlightImage)
	local W, H = sprite.width, sprite.height
	common.computeRoundHighlights(
		W, H,
		sprite.properties.virtualWidth,
		sprite.properties.virtualHeight,
		sprite.properties.virtualOffsetX,
		sprite.properties.virtualOffsetY,
		sprite.properties.rounds,
		function(x, y) return cel.image:getPixel(x, y) end,
		function(x, y, c) highlightImage:drawPixel(x, y, c) end
	)
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
	if sprite.properties.mosaicMode == common.MODE_ROUND then
		updateRoundHighlights(sprite, cel, highlightImage)
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

-- ============================================================
-- BACKWARD COMPAT: Delete this entire function before releasing next major version.
-- v1 -> v2: Upgrades any old round/center sprite to the current format in-place.
-- Handles: mosaicMode="center", innerRadius, roundSubMode string,
--          roundVirtualWidth/Height without offsets, roundOffsetX/Y naming.
local function upgradeSprite(sprite)
	if sprite.properties.mosaicMode ~= "center" and sprite.properties.mosaicMode ~= common.MODE_ROUND then
		return
	end

	if sprite.properties.innerRadius ~= nil and sprite.properties.rounds == nil then
		sprite.properties.rounds = (sprite.width - 1) / 2 - sprite.properties.innerRadius
		sprite.properties.innerRadius = nil
	end

	if sprite.properties.mosaicMode == "center" then
		sprite.properties.mosaicMode = common.MODE_ROUND
	end

	if sprite.properties.roundSubMode ~= nil then
		local sub = sprite.properties.roundSubMode
		local W, H = sprite.width, sprite.height
		if sub == "full" then
			sprite.properties.virtualWidth   = W;     sprite.properties.virtualHeight  = H
			sprite.properties.virtualOffsetX = 0;     sprite.properties.virtualOffsetY = 0
		elseif sub == "half" then
			sprite.properties.virtualWidth   = W;     sprite.properties.virtualHeight  = H * 2
			sprite.properties.virtualOffsetX = 0;     sprite.properties.virtualOffsetY = H
		elseif sub == "quarter" then
			sprite.properties.virtualWidth   = W * 2; sprite.properties.virtualHeight  = H * 2
			sprite.properties.virtualOffsetX = 0;     sprite.properties.virtualOffsetY = H
		end
		sprite.properties.roundSubMode = nil
	end

	if sprite.properties.roundVirtualWidth ~= nil then
		sprite.properties.virtualWidth   = sprite.properties.roundVirtualWidth
		sprite.properties.virtualHeight  = sprite.properties.roundVirtualHeight
		sprite.properties.virtualOffsetX = 0
		sprite.properties.virtualOffsetY = sprite.properties.roundVirtualHeight - sprite.height
		sprite.properties.roundVirtualWidth  = nil
		sprite.properties.roundVirtualHeight = nil
	end

	if sprite.properties.roundOffsetX ~= nil then
		sprite.properties.virtualOffsetX = sprite.properties.roundOffsetX
		sprite.properties.virtualOffsetY = sprite.properties.roundOffsetY
		sprite.properties.roundOffsetX   = nil
		sprite.properties.roundOffsetY   = nil
	end

	if sprite.properties.virtualWidth == nil then
		sprite.properties.virtualWidth   = sprite.width
		sprite.properties.virtualHeight  = sprite.height
		sprite.properties.virtualOffsetX = 0
		sprite.properties.virtualOffsetY = 0
	end
end
-- END BACKWARD COMPAT
-- ============================================================

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

	-- If new sprite doesn't have mosaicMode or is not in INDEXED color mode, we just finished detaching.
	if not sprite or not sprite.properties.mosaicMode or sprite.colorMode ~= ColorMode.INDEXED then
		return
	end

	upgradeSprite(sprite)

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
	-- Sub-mode options for the "New Mosaic Pattern" dialog.
	-- GUI helpers only; the file stores virtualWidth/virtualHeight/virtualOffsetX/Y.
	--   FULL:    origin at center; all four quadrants. Physical: (innerW+rounds*2)×(innerH+rounds*2)
	--   HALF:    origin at top edge center; bottom half only. Physical: (innerW+rounds*2)×(ceil(innerH/2)+rounds)
	--   QUARTER: origin at top-right corner; bottom-left quarter only. Physical: (ceil(innerW/2)+rounds)×(ceil(innerH/2)+rounds)
	local ROUND_SUBMODE_FULL    = "full"
	local ROUND_SUBMODE_HALF    = "half"
	local ROUND_SUBMODE_QUARTER = "quarter"

	local dlg = Dialog("New Mosaic Pattern")
	dlg:combobox{ id="mode", label="Mode:", options={ common.MODE_ROW, common.MODE_ROUND }, selected=common.MODE_ROW, onchange=function()
		local isRound = dlg.data.mode == common.MODE_ROUND
		dlg:modify{ id="width",        visible = not isRound }
		dlg:modify{ id="height",       visible = not isRound }
		dlg:modify{ id="roundSubMode", visible = isRound }
		dlg:modify{ id="innerWidth",   visible = isRound }
		dlg:modify{ id="innerHeight",  visible = isRound }
		dlg:modify{ id="rounds",       visible = isRound }
	end }
	   :number{   id="width",        label="Width:",       decimals=0, text="32", visible=true }
	   :number{   id="height",       label="Height:",      decimals=0, text="32", visible=true }
	   :combobox{ id="roundSubMode", label="Sub-mode:",    options={ ROUND_SUBMODE_FULL, ROUND_SUBMODE_HALF, ROUND_SUBMODE_QUARTER }, selected=ROUND_SUBMODE_FULL, visible=false }
	   :number{   id="innerWidth",   label="Inner Width:", decimals=0, text="3",  visible=false }
	   :number{   id="innerHeight",  label="Inner Height:",decimals=0, text="3",  visible=false }
	   :number{   id="rounds",       label="Rounds:",      decimals=0, text="5",  visible=false }
	   :button{ id="ok", text="OK" }
	   :button{ id="cancel", text="Cancel" }

	dlg:show()

	local data = dlg.data
	if not data.ok then return end

	local width, height, virtualWidth, virtualHeight, offsetX, offsetY
	if data.mode == common.MODE_ROUND then
		virtualWidth  = data.innerWidth  + data.rounds * 2
		virtualHeight = data.innerHeight + data.rounds * 2
		local sub = data.roundSubMode
		if sub == ROUND_SUBMODE_FULL then
			width  = virtualWidth;                   height  = virtualHeight
			offsetX = 0;                             offsetY = 0
		elseif sub == ROUND_SUBMODE_HALF then
			width   = virtualWidth
			offsetX = 0;  offsetY = data.rounds
			height  = virtualHeight - offsetY
		elseif sub == ROUND_SUBMODE_QUARTER then
			width   = virtualWidth - data.rounds
			offsetX = 0;  offsetY = data.rounds
			height  = virtualHeight - offsetY
		end
	else
		width  = data.width
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
	if data.mode == common.MODE_ROUND then
		sprite.properties.rounds          = data.rounds
		sprite.properties.virtualWidth    = virtualWidth
		sprite.properties.virtualHeight   = virtualHeight
		sprite.properties.virtualOffsetX  = offsetX
		sprite.properties.virtualOffsetY  = offsetY
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

			if sprite.properties.mosaicMode == common.MODE_ROUND then
				local roundIndex = sprite.properties.rounds - 1
					- common.getRoundFromEdge(virtualWidth, virtualHeight, x + offsetX, y + offsetY)
				colorIdx = (roundIndex < 0) and common.COLOR_TRANSPARENT or common.getColorIndex(roundIndex)
			else
				colorIdx = common.getColorIndex(common.getRowIndex(sprite.height, y))
			end

			cel.image:putPixel(x, y, colorIdx)
		end
	end

	app.fgColor = common.COLOR_A
	app.bgColor = common.COLOR_B

	reattachCrochetCallbacks()
end

local function exportPattern()
	local sprite = app.sprite
	if not sprite or not sprite.properties.mosaicMode then
		app.alert("No active mosaic crochet sprite.")
		return
	end

	local highlightLayer = getLayerByName(sprite, common.LAYER_HIGHLIGHTS)
	local highlightCel   = highlightLayer and highlightLayer:cel(app.activeFrame)
	if not highlightCel then
		app.alert("No highlight layer found. Open the sprite and let highlights update first.")
		return
	end

	local defaultPath = sprite.filename:gsub("%.[^%.]+$", "_pattern.txt")
	local optionsDialog = Dialog("Export Crochet Pattern")
	optionsDialog:file{   id="path",      label="Save to:",           save=true, filename=defaultPath, filetypes={"txt"} }
	             :check{  id="alternate", label="Alternate direction:", selected=false }
	             :button{ id="ok",        text="Export" }
	             :button{ id="cancel",    text="Cancel" }
	optionsDialog:show()
	if not optionsDialog.data.ok then return end

	local alternate  = optionsDialog.data.alternate
	local outputPath = optionsDialog.data.path

	local function stitchAt(coord)
		return highlightCel.image:getPixel(coord.x, coord.y) == common.HIGHLIGHT_VALID_OVERLAY and "oc" or "sc"
	end

	local canvasSize = vec2(sprite.width, sprite.height)
	local allRows, label

	if sprite.properties.mosaicMode == common.MODE_ROW then
		label   = "Row "
		allRows = coroutine.wrap(function()
			for coordIter in walk.rowWalk(canvasSize) do
				coroutine.yield(coroutine.wrap(function()
					for coord in coordIter do
						coroutine.yield(stitchAt(coord))
					end
				end))
			end
		end)
	else
		local virtualSize    = vec2(sprite.properties.virtualWidth,   sprite.properties.virtualHeight)
		local physicalOffset = vec2(sprite.properties.virtualOffsetX, sprite.properties.virtualOffsetY)
		label   = "Round "
		allRows = coroutine.wrap(function()
			for virtualPairIterator in walk.roundWalk(virtualSize, sprite.properties.rounds) do
				coroutine.yield(coroutine.wrap(function()
					-- Step 1: Convert virtual coordinate pairs to physical coordinate pairs
					local physicalPairIterator = map(virtualPairIterator, function(virtualPair)
						local virtualCoord  = virtualPair[1]
						local virtualParent = virtualPair[2]
						return { virtualCoord - physicalOffset, virtualParent - physicalOffset }
					end)

					-- Step 2: Filter coordinates outside the physical canvas bounds
					local windowedPairIterator = filter(physicalPairIterator, function(physicalPair)
						return walk.window(physicalPair[1], canvasSize)
					end)

					-- Step 3: Convert physical coordinates to stitches, preserving parent coordinates
					local stitchWithParentIterator = map(windowedPairIterator, function(physicalPair)
						local physicalCoord       = physicalPair[1]
						local physicalParentCoord = physicalPair[2]
						local stitch
						if walk.isCornerCoord(physicalCoord, physicalOffset, virtualSize) then
							stitch = "ch"
						else
							stitch = stitchAt(physicalCoord)
						end
						return { stitch, physicalParentCoord }
					end)

					-- Step 4: Group consecutive stitches worked into the same parent stitch
					local groupsIterator = coroutine.wrap(function()
						local currentGroup       = {}
						local currentParentCoord = nil

						for stitchWithParent in stitchWithParentIterator do
							local stitch      = stitchWithParent[1]
							local parentCoord = stitchWithParent[2]

							if parentCoord ~= currentParentCoord then
								coroutine.yield(currentGroup)

								currentGroup       = {}
								currentParentCoord = parentCoord
							end

							currentGroup[#currentGroup + 1] = stitch
						end

						coroutine.yield(currentGroup)
					end)

					-- Step 5: Format groups, compressing repeated sequences within each group
					local function formatGroup(stitchGroup)
						if #stitchGroup == 1 then
							return stitchGroup[1]
						else
							return "(" .. pattern.toString(pattern.compress(stitchGroup)) .. ")"
						end
					end

					for currentGroup in groupsIterator do
						if #currentGroup > 0 then
							coroutine.yield(formatGroup(currentGroup))
						end
					end
				end))
			end
		end)
	end

	local lines = {}
	local rowIndex = 0
	for instructionIter in allRows do
		rowIndex = rowIndex + 1
		local flat = {}
		for instruction in instructionIter do flat[#flat + 1] = instruction end
		if alternate and rowIndex % 2 == 0 then
			local reversed = {}
			for i = #flat, 1, -1 do reversed[#reversed + 1] = flat[i] end
			flat = reversed
		end
		lines[#lines + 1] = label .. rowIndex .. ": " .. pattern.toString(pattern.compress(flat))
	end

	local file = io.open(outputPath, "w")
	if file then
		file:write(table.concat(lines, "\n"))
		file:close()
		app.alert("Pattern saved to:\n" .. outputPath)
	else
		app.alert("Failed to write file:\n" .. outputPath)
	end
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
		id="export_crochet_pattern",
		title="Export Crochet Pattern",
		group="file_export_2",
		onclick=exportPattern,
		onenabled=function()
			local sprite = app.sprite
			if not sprite
			or not sprite.properties.mosaicMode
			or sprite.colorMode ~= ColorMode.INDEXED then
				return false
			end
			local highlightLayer = getLayerByName(sprite, common.LAYER_HIGHLIGHTS)
			local highlightCel   = highlightLayer and highlightLayer:cel(app.activeFrame)
			if not highlightCel then return false end
			for y = 0, sprite.height - 1 do
				for x = 0, sprite.width - 1 do
					if highlightCel.image:getPixel(x, y) == common.HIGHLIGHT_INVALID_PLACEMENT then
						return false
					end
				end
			end
			return true
		end
	}

	-- Listen for site changes (switching between sprites or closing files).
	-- This keeps the real-time highlights synced with the currently focused sprite.
	app.events:on("sitechange", reattachCrochetCallbacks)

	-- If a mosaic crochet sprite is already open when the plugin is loaded or reloaded,
	-- ensure its highlights and callbacks are initialized immediately.
	reattachCrochetCallbacks()
end
