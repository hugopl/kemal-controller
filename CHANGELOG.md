# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Opt-in `{action}_on_cast_error` hook: define a sibling method (same parameter names and order, no type
  restrictions) to recover from a parameter that's missing or fails to cast, instead of letting the error
  propagate. Every parameter is now cast independently, so a single bad value no longer stops the rest from
  being cast too. Controllers that don't define the hook keep today's behaviour unchanged.
- Support parameters with a separate external/internal name, e.g. `def sign_in(next url : String)` reads the
  `next` request parameter into the local variable `url`. This allows request fields named after Crystal
  reserved words, which previously failed to compile.

### Changed

- **BREAKING CHANGE:** Controller actions no longer default to a 201 (Created) status for `POST` requests.
  Every verb now defaults to 200, and actions must opt in to a different status via the new `status`
  annotation parameter (e.g. `@[Post("/users", status: 201)]`) or by setting `response.status_code` directly.
- **BREAKING CHANGE:** Replaced `MissingParameterError` and `InvalidParameterError` with a single
  `Kemal::ParamError`, whose `reason` getter (`Kemal::ParamError::Reason::Missing` or `::CastError`) tells
  you which happened. `param_name` is always set; `expected_type` and `value` are only set for `CastError`.

### Fixed

- `Kemal.print_routes` no longer crashes with `Enumerable::EmptyError` when called before any routes are
  registered; it now prints a hint instead.
- A nilable parameter sent with an empty value (e.g. `?number=` for `number : Int32?`) is now `nil` instead
  of raising a `CastError`. `String?` still reads an empty value as `""`.

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

