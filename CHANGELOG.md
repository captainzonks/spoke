# Changelog

<!--
==============================================================================
CHANGELOG.md - Release history
==============================================================================
Description: Notable changes in each release, newest first
Author: Matt Barham
Created: 2026-09-27
Modified: 2026-11-26
Version: 1.3.0
==============================================================================
Document Type: Changelog
Audience: Operator, Module Developer
Status: Active (living document)
==============================================================================
-->

All notable changes to this project are documented here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html). What
counts as a breaking change for a Spoke module is defined in the Spoke hub's
ADR-029.

## [1.3.0] - 2026-11-26

### Added

- Add a forward-auth chain that keeps the client Authorization header (#76)

## [1.2.1] - 2026-11-26

### Fixed

- Drop request headers whose names alias other headers (#74)

## [1.2.0] - 2026-11-26

### Added

- Show a page to visitors blocked by CrowdSec (#72)

## [1.1.6] - 2026-11-26

### Fixed

- Protect the Authentik login router with CrowdSec and drop the null CORS origin (#70)

## [1.1.5] - 2026-11-25

### Changed

- Maintenance only; no user-visible changes.

## [1.1.4] - 2026-11-21

### Changed

- Maintenance only; no user-visible changes.

## [1.1.3] - 2026-11-10

### Changed

- Maintenance only; no user-visible changes.

## [1.1.2] - 2026-10-26

### Changed

- Maintenance only; no user-visible changes.

## [1.1.1] - 2026-10-17

### Changed

- Maintenance only; no user-visible changes.

## [1.1.0] - 2026-10-15

### Added

- safe-shutdown: Run optional post-stop hooks (#55)

### Fixed

- backup: Include hub override and backup.conf files (#53)

## [1.0.1] - 2026-10-02

### Fixed

- boot: Run boot deploy and safe shutdown as system units ordered against docker (ADR-030) (#49)

## [1.0.0] - 2026-09-27

### Baseline

- First versioned release (hub ADR-029). Earlier history is in the git log.
