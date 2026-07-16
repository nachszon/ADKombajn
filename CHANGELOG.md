# Changelog

All notable changes to this project will be documented in this file.

The project follows Semantic Versioning where practical:

```text
MAJOR.MINOR.PATCH
```

## [Unreleased]

### Planned

- English user interface
- configurable domain selection
- improved filtering and search
- additional export options
- modular code structure
- signed release packages

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
