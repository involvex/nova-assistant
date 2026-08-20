# Changelog

All notable changes to Nova Assistant are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Keyword-triggered image generation: ask "generate an image of a sunset over mountains" and Nova will use an on-device diffusion model (Z-Image-Turbo or FLUX.2-klein) to create and display the result inline in the chat. Image generation is now reachable from the Flutter chat layer — the tool wires through `_wantsGenerateImage`, `_toolsForQuery`, `generate_image` aliases, and the `imageData` rendering path.

### Fixed

- Image generation tool (`generate_image`) was implemented end-to-end on the native side but disconnected from the chat UI; it is now exposed to the model and its output is rendered in the chat bubble.






## [0.4.6] - 2026-08-11

### Changed

- v0.4.6
## [0.4.5] - 2026-07-28

### Changed

- v0.4.5
## [0.4.4] - 2026-07-27

### Changed

- v0.4.4
## [0.4.3] - 2026-07-24

### Changed

- v0.4.3
## [0.4.2] - 2026-07-19

### Changed

- v0.4.2
