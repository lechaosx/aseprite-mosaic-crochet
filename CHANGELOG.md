# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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