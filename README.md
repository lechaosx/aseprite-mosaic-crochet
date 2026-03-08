# Inset Mosaic Crochet Helper for Aseprite

This Aseprite plugin provides real-time highlights for overlay stitches and invalid overlay placements for inset mosaic crochet patterns.

## Features

- **Row Mode:** Supports standard row-by-row mosaic patterns.
- **Center Mode:** Supports circular/square patterns worked from the center out.
- **Real-time Highlighting:** Automatically updates a "Mosaic Highlights" layer as you draw on the "Crochet Pattern" layer.
- **Validation:** 
  - Highlights valid overlay stitch locations in blue.
  - Highlights invalid overlay placements (e.g., trying to place an overlay where the previous round's color doesn't allow it) in red.
- **Automatic Setup:** Creates a pre-configured sprite with the correct layers, palette, and properties.

## Installation

1. Open Aseprite.
2. Go to **Edit > Preferences > Extensions**.
3. Click **Add Extension** and select the folder containing this plugin, or drag and drop the `.aseprite-extension` file if available.
4. Alternatively, place the `aseprite-mosaic-crochet` folder into your Aseprite extensions directory.

## Usage

### Creating a New Pattern
1. Go to **File > New Mosaic Crochet Sprite**.
2. Choose a **Mode**: `row` or `center`.
   - For `row` mode, specify the width and height.
   - For `center` mode, specify the `Inner Radius` and the number of `Rounds`.
3. Click **OK**.

### Drawing
- Draw on the **Crochet Pattern** layer using the first two colors of the palette (usually black and white).
- The plugin will automatically manage the **Mosaic Highlights** layer:
  - **Blue pixels** indicate where an overlay stitch should be placed (one row/round below).
  - **Red pixels** indicate an invalid placement that doesn't follow inset mosaic crochet rules.
- The plugin will automatically normalize any other colors you use back to the base pattern colors.

## Technical Details

- **Layers:**
  - `Crochet Pattern`: The main layer where you design your pattern.
  - `Mosaic Highlights`: An overlay layer created and managed by the plugin.
- **Palette:**
  - Color 0 & 1: Base pattern colors (e.g., Color A and Color B).
  - Color 2: Blue (Valid overlay highlight).
  - Color 3: Red (Invalid placement highlight).
- **Metadata:** The plugin stores configuration in the sprite's custom properties (`mosaicMode`, `innerRadius`).

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENCE.md) for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a full history of changes.
