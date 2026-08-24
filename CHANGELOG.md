# Changelog

All notable changes to this project will be documented in this file.

The project follows Semantic Versioning where practical:

```text
MAJOR.MINOR.PATCH
```

## [Unreleased]

### Planned

- configurable domain selection
- improved filtering and search
- additional export options
- modular code structure
- signed release packages

## [2.13.5] - 2026-08-24

### Changed

- Replaced the previous magnifying-glass branding with a green combine harvester.
- Redesigned the splash screen and application header with a clean, consistent green theme.
- Updated the language selection and primary action buttons to use the new branding colors.
- Added a multi-resolution `kombajn.ico` file and updated the build script to use it.
- Updated the application and release version to 2.13.5.

## [2.13.4] - 2026-08-21

### Changed

* Banished visual “ghosts” that appeared in the application header when resizing the main window.
* Updated the application and release version to 2.13.4.

## [2.13.3] - 2026-08-20

### Changed

* Updated the build script to explicitly force the x64 architecture when compiling the executable with PS2EXE.
* Updated the application and release version to 2.13.3.


## [2.13.2] - 2026-08-04

### Changed

- Unified application branding from `AD Kombajn` and `AD KOMBAJN` to `ADKombajn`.
- Updated the application name across the user interface, splash screen, dialog titles, EXE metadata and XLSX export metadata.
- Updated the application and release version to 2.13.2.

## [2.13.1] - 2026-07-23

### Added

- Dedicated `Zamknij` / `Exit` button in the application header.
- Localized Exit button label for the Polish and English interfaces.

### Changed

- Updated the application and release version to 2.13.1.

## [2.13.0] - 2026-07-21

### Added

- Polish and English user interface in a single application.
- Language selection dialog displayed at startup.
- Optional `-Language pl` and `-Language en` command-line parameter.
- Centralized translation dictionaries for user-facing text.
- English translations for tabs, buttons, labels, table headers, status messages, logs and dialog boxes.
- Localized splash screen and export headers.

### Changed

- Updated the application version to 2.13.0.
- Updated the documentation for the bilingual interface and language selection.

### Fixed

- Closing the language selection dialog now exits the application instead of starting the Polish interface.
- The splash screen now displays `WERSJA` in Polish and `VERSION` in English.

## [2.12.1] - 2026-07-20

### Added

- Application version number on the splash screen.

### Changed

- Updated the application and release version to 2.12.1.

## [2.12.0] - 2026-07-16

### Added

- Initial public release of ADKombajn.
- Windows GUI for common Active Directory support tasks.
- Account lookup by login.
- Password validation.
- Password change using LDAP `unicodePwd` operation.
- Account properties view.
- Account group membership view.
- Domain group members view.
- Managed accounts view.
- Managed groups view.
- Application-wide operation log.
- Colored tab interface.
- Progress dialog for longer Active Directory operations.
- CSV/XLSX export for selected result tables.
- Build script for PS2EXE compilation.
- UTF-8 with BOM validation in the build script.

### Changed

- Prepared the project for public GitHub release.
- Removed organization-specific/internal functionality.
- Converted code comments to English.
- Converted log/status messages to English.
- Kept the current user interface in Polish.

### Security

- No credentials, passwords, internal domain names or organization-specific configuration are included.
- No RSAT or `ActiveDirectory` PowerShell module dependency.
- Active Directory access is handled through built-in .NET Directory Services / LDAP APIs.

### Notes

- The project targets Windows PowerShell 5.1.
- `ADKombajn.ps1` should be saved as UTF-8 with BOM.
- Test in a non-production environment before operational use.
