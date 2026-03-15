local export = require("src.export")
local testFramework = require("test.test_framework")

local test = testFramework.test

local function createMockImage(width, height, pixels)
	return {
		width = width,
		height = height,
		getPixel = function(self, x, y)
			if x < 0 or x >= width or y < 0 or y >= height then return 0 end
			return pixels[y * width + x + 1] or 0
		end
	}
end

local function createFilledPixels(width, height, value)
	local pixels = {}
	for i = 1, width * height do
		pixels[i] = value
	end
	return pixels
end

local function setPixel(pixels, width, x, y, value)
	pixels[y * width + x + 1] = value
end

local function assertRowsEqual(actual, expected, message)
	assert(#actual == #expected, (message or "Export row count mismatch") .. " (rows)")
	for i = 1, #expected do
		local itemMessage = (message or "Export row mismatch") .. " (item " .. i .. ")"
		assert(actual[i].index == expected[i].index, itemMessage .. " index")
		assert(#actual[i].stitches == #expected[i].stitches, itemMessage .. " stitches length")
		for j = 1, #expected[i].stitches do
			local function assertStitchEqual(actualStitch, expectedStitch, stitchMessage)
				assert(actualStitch.type == expectedStitch.type, stitchMessage .. " type")
				if expectedStitch.type == "stitch" then
					assert(actualStitch.stitch == expectedStitch.stitch, stitchMessage .. " value")
				elseif expectedStitch.type == "group" or expectedStitch.type == "repeat" then
					if expectedStitch.type == "repeat" then
						assert(actualStitch.repeats == expectedStitch.repeats, stitchMessage .. " repeat count")
					end
					assert(#actualStitch.stitches == #expectedStitch.stitches, stitchMessage .. " nested length")
					for k = 1, #expectedStitch.stitches do
						assertStitchEqual(actualStitch.stitches[k], expectedStitch.stitches[k], stitchMessage .. " nested " .. k)
					end
				end
			end

			assertStitchEqual(actual[i].stitches[j], expected[i].stitches[j], itemMessage .. " stitch " .. j)
		end
	end
end

test("Row Export (Simple)", function()
    -- 3x3 pattern. Color A=1, B=2. Row 1 is B, Row 2 is A.
    -- Row 1: y=1, colorIndex=2 (B)
    -- Row 2: y=0, colorIndex=1 (A)
    local pixels = {
        1, 1, 1, -- y=0, Row 2 (A)
        2, 2, 2, -- y=1, Row 1 (B)
        0, 0, 0  -- y=2, Row 0 (ignored)
    }
    local mock_sprite = { width = 3, height = 3, properties = { mosaicMode = "row" } }
    local mock_cel = { image = createMockImage(3, 3, pixels) }

    local params = {
        sprite = mock_sprite,
        cel = mock_cel,
        sameDirection = true
    }

   	local result = export.exportRow(params)
   	local expected = {
   		{ index = 1, stitches = { { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" } } },
   		{ index = 2, stitches = { { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" } } }
   	}
    assertRowsEqual(result, expected, "Simple row sc only")
end)

test("Repeat nodes include repeat count", function()
	local repeatGroup = export.makeRepeat({
		{ type = "stitch", stitch = "sc" },
		{ type = "group", stitches = {
			{ type = "stitch", stitch = "sc" },
			{ type = "stitch", stitch = "ch" },
			{ type = "stitch", stitch = "sc" }
		} }
	}, 4)

	assert(repeatGroup.type == "repeat", "Repeat node type")
	assert(repeatGroup.repeats == 4, "Repeat node count")
	assert(#repeatGroup.stitches == 2, "Repeat node stitches")
	assert(repeatGroup.stitches[1].type == "stitch" and repeatGroup.stitches[1].stitch == "sc", "Repeat node first stitch")
	assert(repeatGroup.stitches[2].type == "group", "Repeat node nested group")

	assertRowsEqual({
		{ index = 1, stitches = { repeatGroup } }
	}, {
		{ index = 1, stitches = {
			{ type = "repeat", repeats = 4, stitches = {
				{ type = "stitch", stitch = "sc" },
				{ type = "group", stitches = {
					{ type = "stitch", stitch = "sc" },
					{ type = "stitch", stitch = "ch" },
					{ type = "stitch", stitch = "sc" }
				} }
			} }
		} }
	}, "Repeat nodes compare with repeat count")
end)

test("Row Export (with DC)", function()
    -- 3x3 pattern.
    -- Row 1 (y=1): Color B (2). Pixels: [2, 1, 2] -> sc, oc, sc (if y+1 is 2)
    local pixels = {
        1, 1, 1, -- y=0, Row 2 (A)
        2, 1, 2, -- y=1, Row 1 (B)
        2, 2, 2  -- y=2, Row 0 (color index 0, but usually we look at y+1 which is y=2)
    }
    local mock_sprite = { width = 3, height = 3, properties = { mosaicMode = "row" } }
    local mock_cel = { image = createMockImage(3, 3, pixels) }

    local params = {
        sprite = mock_sprite,
        cel = mock_cel,
        sameDirection = true
    }

   	local result = export.exportRow(params)
   	local expected_fallback = {
   		{ index = 1, stitches = { { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" } } },
   		{ index = 2, stitches = { { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" } } }
   	}
    assertRowsEqual(result, expected_fallback, "Row fallback sc")

    -- Now with highlights
    local h_pixels = {
        0, 0, 0,
        0, 3, 0, -- Highlight at y=1, x=1
        0, 0, 0
    }
    local mock_h_cel = { image = createMockImage(3, 3, h_pixels) }
    params.highlightCel = mock_h_cel

   	result = export.exportRow(params)
   	local expected_highlights = {
   		{ index = 1, stitches = { { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "oc" }, { type = "stitch", stitch = "sc" } } },
   		{ index = 2, stitches = { { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" } } }
   	}
    assertRowsEqual(result, expected_highlights, "Row with highlights")
end)

test("Row Export (Altering Directions)", function()
    local pixels = {
        1, 2, 1, -- y=0, Row 2 (A)
        2, 2, 2, -- y=1, Row 1 (B)
        0, 0, 0
    }
    local h_pixels = {
        0, 3, 0, -- Highlight at y=0, x=1
        0, 0, 0,
        0, 0, 0
    }
    local mock_sprite = { width = 3, height = 3, properties = { mosaicMode = "row" } }
    local mock_cel = { image = createMockImage(3, 3, pixels) }
    local mock_h_cel = { image = createMockImage(3, 3, h_pixels) }

    local params = {
        sprite = mock_sprite,
        cel = mock_cel,
        highlightCel = mock_h_cel,
        sameDirection = false
    }

   	local result = export.exportRow(params)
   	local expected = {
   		{ index = 1, stitches = { { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" } } },
   		{ index = 2, stitches = { { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "oc" }, { type = "stitch", stitch = "sc" } } }
   	}
    assertRowsEqual(result, expected, "Altering directions")
end)

test("Center Export", function()
    local pixels = {}
    for i=1, 25 do pixels[i] = 2 end -- All B (colorIndex for Round 1 is B=2)
    
    local mock_sprite = { width = 5, height = 5, properties = { mosaicMode = "center", innerRadius = 0 } }
    local mock_cel = { image = createMockImage(5, 5, pixels) }

    local params = {
        sprite = mock_sprite,
        cel = mock_cel,
        sameDirection = true
    }

   	local result = export.exportCenter(params)
   	local expected = {
   		{ index = 1, stitches = {
   			{ type = "group", stitches = {
   				{ type = "stitch", stitch = "sc" },
   				{ type = "stitch", stitch = "ch" },
   				{ type = "stitch", stitch = "sc" },
   				{ type = "stitch", stitch = "ch" },
   				{ type = "stitch", stitch = "sc" },
   				{ type = "stitch", stitch = "ch" },
   				{ type = "stitch", stitch = "sc" }
   			} },
   			{ type = "stitch", stitch = "ss" }
   		}}
   	}
    assertRowsEqual(result, expected, "Simple center round")
end)

test("Center Export (Inner Radius)", function()
    local pixels = {}
    for i=1, 49 do pixels[i] = 2 end

    local mock_sprite = { width = 7, height = 7, properties = { mosaicMode = "center", innerRadius = 1 } }
    local mock_cel = { image = createMockImage(7, 7, pixels) }

    local params = {
        sprite = mock_sprite,
        cel = mock_cel,
        sameDirection = true
    }

   	local result = export.exportCenter(params)
   	local expected = {
   		{ index = 1, stitches = {
   			{ type = "stitch", stitch = "sc" },
   			{ type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" },
   			{ type = "group", stitches = { { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "ch" }, { type = "stitch", stitch = "sc" } } },
   			{ type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" },
   			{ type = "group", stitches = { { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "ch" }, { type = "stitch", stitch = "sc" } } },
   			{ type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" },
   			{ type = "group", stitches = { { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "ch" }, { type = "stitch", stitch = "sc" } } },
   			{ type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" }, { type = "stitch", stitch = "sc" },
   			{ type = "stitch", stitch = "ss" }
   		}}
   	}
    assertRowsEqual(result, expected, "Center round with inner radius uses normal round behavior")
end)

test("Center Export (Altering Directions)", function()
    local pixels = {}
    for i=1, 81 do pixels[i] = 2 end -- All 2 (Round 1 is B=2, Round 2 is A=1, but we use all 2 to test SC/DC)
    -- Round 2 (dist=3, r=2, colorIndex=1 (A))
    -- Round 3 (dist=4, r=3, colorIndex=2 (B))
    
    local mock_sprite = { width = 9, height = 9, properties = { mosaicMode = "center", innerRadius = 0 } }
    local mock_cel = { image = createMockImage(9, 9, pixels) }

    local params = {
        sprite = mock_sprite,
        cel = mock_cel,
        sameDirection = false
    }

   	local result = export.exportCenter(params)
   	-- Round 1 uses the special no-inner-radius foundation round.
   	assert(result[1].index == 1, "Round 1 index")
   	assert(result[1].stitches[1].type == "group", "Round 1 foundation type")
   	assert(result[1].stitches[1].stitches[1].stitch == "sc", "Round 1 foundation first stitch")
   	assert(result[1].stitches[2].type == "stitch" and result[1].stitches[2].stitch == "ss", "Round 1 join")

   	-- Round 2 (r=2) should be clockwise
   	assert(result[2].index == 2, "Round 2 index")
   	assert(result[2].stitches[1].type == "stitch" and result[2].stitches[1].stitch == "sc", "Round 2 start")
   	-- Side 1 (right) is from (centerX + dist, centerY + dist - 1) to (centerX + dist, centerY - dist + 1)
   	-- centerX=4, centerY=4, dist=3
   	-- (7, 6) to (7, 2) -> 5 stitches
   	assert(#result[2].stitches == 1 + 5 + 1 + 5 + 1 + 5 + 1 + 5 + 1, "Round 2 total stitches")

   	-- Round 3 (r=3) should be anti-clockwise
   	assert(result[3].index == 3, "Round 3 index")
   	assert(result[3].stitches[1].type == "stitch" and result[3].stitches[1].stitch == "sc", "Round 3 start")
   	-- Side 4 (bottom) is from (centerX + dist - 1, centerY + dist) to (centerX - dist + 1, centerY + dist)
   	-- centerX=4, centerY=4, dist=4
   	-- (7, 8) to (1, 8) -> 7 stitches
   	assert(result[3].stitches[2].type == "stitch" and result[3].stitches[2].stitch == "sc", "Round 3 side 4 - 1")
   	assert(result[3].stitches[8].type == "stitch" and result[3].stitches[8].stitch == "sc", "Round 3 side 4 - 7")
   	assert(result[3].stitches[9].type == "group", "Round 3 corner 3")
      end)

   test("Center Export walks 4 sides and glues corners clockwise", function()
   	local pixels = createFilledPixels(7, 7, 2)
   	local highlightPixels = createFilledPixels(7, 7, 0)
   	local width = 7

   	setPixel(pixels, width, 6, 5, 1)
   	setPixel(pixels, width, 5, 0, 1)
   	setPixel(pixels, width, 0, 1, 1)
   	setPixel(pixels, width, 1, 6, 1)

   	setPixel(highlightPixels, width, 6, 5, 3) -- side 1 first stitch
   	setPixel(highlightPixels, width, 5, 0, 3) -- side 2 first stitch
   	setPixel(highlightPixels, width, 0, 1, 3) -- side 3 first stitch
   	setPixel(highlightPixels, width, 1, 6, 3) -- side 4 first stitch

   	local mock_sprite = { width = 7, height = 7, properties = { mosaicMode = "center", innerRadius = 1 } }
   	local mock_cel = { image = createMockImage(7, 7, pixels) }
   	local mock_h_cel = { image = createMockImage(7, 7, highlightPixels) }

   	local result = export.exportCenter({
   		sprite = mock_sprite,
   		cel = mock_cel,
   		highlightCel = mock_h_cel,
   		sameDirection = true
   	})

   	local stitches = result[1].stitches
   	assert(stitches[1].type == "stitch" and stitches[1].stitch == "sc", "Clockwise round starts with glued corner start")
   	assert(stitches[2].stitch == "oc", "Clockwise starts with side 1")
   	assert(stitches[3].stitch == "sc", "Clockwise side 1 keeps walking")
   	assert(stitches[7].type == "group", "Clockwise glues corner after side 1")
   	assert(stitches[8].stitch == "oc", "Clockwise continues with side 2")
   	assert(stitches[13].type == "group", "Clockwise glues corner after side 2")
   	assert(stitches[14].stitch == "oc", "Clockwise continues with side 3")
   	assert(stitches[19].type == "group", "Clockwise glues corner after side 3")
   	assert(stitches[20].stitch == "oc", "Clockwise continues with side 4")
   	assert(stitches[#stitches].type == "stitch" and stitches[#stitches].stitch == "ss", "Clockwise ends with ss")
   end)

   test("Center Export reverses collected sides for alternating rounds", function()
   	local pixels = createFilledPixels(7, 7, 2)
   	local highlightPixels = createFilledPixels(7, 7, 0)
   	local width = 7

   	setPixel(pixels, width, 2, 6, 1)
   	setPixel(pixels, width, 0, 4, 1)
   	setPixel(pixels, width, 4, 0, 1)
   	setPixel(pixels, width, 6, 2, 1)

   	setPixel(highlightPixels, width, 2, 6, 3) -- side 4, second stitch in clockwise order
   	setPixel(highlightPixels, width, 0, 4, 3) -- side 3, fourth stitch in clockwise order
   	setPixel(highlightPixels, width, 4, 0, 3) -- side 2, second stitch in clockwise order
   	setPixel(highlightPixels, width, 6, 2, 3) -- side 1, fourth stitch in clockwise order

   	local mock_sprite = { width = 7, height = 7, properties = { mosaicMode = "center", innerRadius = 1 } }
   	local mock_cel = { image = createMockImage(7, 7, pixels) }
   	local mock_h_cel = { image = createMockImage(7, 7, highlightPixels) }

   	local result = export.exportCenter({
   		sprite = mock_sprite,
   		cel = mock_cel,
   		highlightCel = mock_h_cel,
   		sameDirection = false
   	})

   	local stitches = result[1].stitches
   	assert(stitches[1].type == "stitch" and stitches[1].stitch == "sc", "Reverse round starts with glued corner start")
   	assert(stitches[2].stitch == "sc", "Reverse round begins with reversed side 4")
   	assert(stitches[5].stitch == "oc", "Reverse round reverses stitch order within side 4")
   	assert(stitches[7].type == "group", "Reverse round glues corner 3 after side 4")
   	assert(stitches[9].stitch == "oc", "Reverse round continues with reversed side 3")
   	assert(stitches[13].type == "group", "Reverse round glues corner 2 after side 3")
   	assert(stitches[17].stitch == "oc", "Reverse round continues with reversed side 2")
   	assert(stitches[19].type == "group", "Reverse round glues corner 1 after side 2")
   	assert(stitches[21].stitch == "oc", "Reverse round finishes with reversed side 1")
   	assert(stitches[#stitches].type == "stitch" and stitches[#stitches].stitch == "ss", "Reverse round still ends with ss")
end)
