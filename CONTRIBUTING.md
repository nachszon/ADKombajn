# Contributing

Thank you for your interest in improving ADKombajn. Contributions should be focused, easy to review, and compatible with Windows PowerShell 5.1.

ADKombajn is intentionally lightweight. Changes must not introduce a dependency on RSAT or the ActiveDirectory PowerShell module unless this is discussed and agreed on in advance.

## Development environment

- Windows 10, Windows 11, or Windows Server
- Windows PowerShell 5.1
- .NET Framework
- Access to a non-production Active Directory environment for features that require LDAP or LDAPS testing
- PS2EXE with the `Invoke-PS2EXE` command available when building the executable

Run the script directly with:

```powershell
.\ADKombajn.ps1
```

or:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\ADKombajn.ps1
```

The `ADKombajn.ps1` file must remain encoded as UTF-8 with BOM. The build script checks this requirement before compilation.

Create the x64 executable with:

```powershell
.\build.ps1
```

An explicit four-part version can also be supplied when required:

```powershell
.\build.ps1 -Version "2.13.6.0"
```

Run and test ADKombajn with standard user permissions. Use an account with only the Active Directory permissions needed for the operation being tested.

## Pull request workflow

1. Fork and clone the repository.
2. Create a focused branch from `master`.
3. Make the smallest coherent change that resolves the issue or implements the feature.
4. Do not include credentials, passwords, internal domain names, real account data, confidential information, or unsanitized logs and screenshots.
5. Run the source script in Windows PowerShell 5.1 and test every affected function.
6. For user-interface changes, verify both Polish and English language modes and include updated screenshots when they help explain the change.
7. Run `.\build.ps1`, start the generated x64 executable, and confirm that the changed functionality also works in the compiled build.
8. Update documentation or the changelog when the change requires it. Do not change the application version unless the pull request scope explicitly includes a version bump.
9. Open a pull request against `master`. Summarize the change, describe how it was tested, and link the related issue when one exists.

Keep pull requests limited to one logical change. Larger proposals should be discussed in a GitHub issue before implementation.

## Reporting issues

Use GitHub Issues to report bugs or propose enhancements. Before opening a new issue, check whether a similar report already exists.

Please include:

- A clear description of the problem or proposed improvement
- Steps to reproduce the problem
- Expected and actual behavior
- The ADKombajn version and whether the script or executable was used
- Windows and Windows PowerShell versions
- Whether LDAP or LDAPS was used, when relevant
- Sanitized screenshots or log excerpts, when helpful

Never include passwords, credentials, internal domain names, real account names, or other confidential information in an issue.
