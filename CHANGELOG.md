# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.3.0 - 2026-08-02

### Added

- Support `@[WebSocket]` annotation for controller methods, taking advantage of Kemal's WebSocket support.

### Fixed

- Fixed alignment of routes on `Kemal.print_routes`.

## [0.2.0] - 2026-04-23

### Added

- Support default parameter values in controller methods.

### Changed

- Replaced `KeyError` with `MissingParameterError` and `InvalidParameterError` for clearer error handling.

## [0.1.2] - 2026-03-24

### Changed

- Removed monkey patch not needed by Kemal 1.10.0.
- Bump Kemal dependency to 1.10.1.

## [0.1.1] - 2026-02-02

### Fixed

- Added kemal 1.9.0 content length validation on our monkey patch.

## [0.1.0] - 2026-02-02

### Added

- Everything, the first version of the project.

