# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.1] - 2026-05-08

### Fixed
- Repeated stitches inside increase groups are now compressed by the pattern optimizer (e.g. `(sc sc sc)` → `(sc × 3)`, `(sc oc sc oc)` → `([sc, oc] × 2)`).

## [1.2.0] - 2026-05-08

### Added
- **Export Crochet Pattern** (File → Export → Export Crochet Pattern): exports the active pattern to a `.txt` file as human-readable stitch notation.
  - Supports an **Alternate Direction** option that reverses every even row/round for back-and-forth working.
  - Stitches worked into the same parent stitch are grouped with `()` notation (e.g. `(sc sc)` for a 2-in-1 increase).
  - Corner stitches in round mode are emitted as `ch`.
  - Repeated sequences are compressed (e.g. `sc × 6`, `[sc, ch] × 4`).
- **Round mode sub-modes:** when creating a round pattern, choose between Full, Half, and Quarter to work only a symmetric portion of the design.
  - **Full:** all four sides, the complete virtual space.
  - **Half:** bottom half only — fold at the inner hole boundary.
  - **Quarter:** bottom-left quarter only — fold at both inner hole boundaries.

### Changed
- **Center mode renamed to Round mode** throughout the UI and file format. Existing sprites are upgraded automatically on open.
- Round walk now starts one pixel to the right of the top-left corner so the full 3-stitch TL corner group (pre-corner stitch, corner chain, post-corner stitch) is kept together within a single round.
- Half and Quarter modes now fold exactly at the inner hole boundary, preserving the full specified inner hole dimensions. Previously the inner hole was cut in half.
- Export Crochet Pattern is now placed in **File → Export** submenu, next to Export Tileset.

### Fixed
- Backward compatibility: sprites created with the old Center mode, `innerRadius` property, and legacy sub-mode or offset naming are automatically upgraded to the current format when opened.

## [1.1.2] - 2026-03-14

### Fixed
- Fixed issue where highlights could still be updated for non-indexed sprites if their color mode changed after the plugin was attached.
- Fixed undefined variables `white` and `black` when creating a new mosaic sprite.

## [1.1.1] - 2026-03-09

### Added
- Added indexed color mode check to prevent breaking the image when color modes are changed.

## [1.1.0] - 2026-03-09

### Added
- Named constants for color indices, layer names, and event names to improve maintainability.

### Changed
- Shifted palette to use index 0 as transparent, fixing export issues.
- Improved `normalizeImage` logic using color distance instead of a brightness threshold.

## [1.0.1] - 2026-03-08

### Fixed
- Improved center mosaic highlighting logic and fixed potential issues with round indexing.

## [1.0.0] - 2026-03-08

### Added
- Initial release of the Inset Mosaic Crochet Helper plugin.
- Support for **Row Mode** (standard row-by-row patterns).
- Support for **Center Mode** (circular/square patterns worked from the center out).
- Real-time highlighting of valid overlay stitch locations (blue).
- Real-time highlighting of invalid overlay placements (red).
- Automatic setup of sprites with correct layers, palette, and properties.
- Comprehensive `README.md` with usage instructions.
