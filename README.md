# ADKombajn

A Windows GUI tool for browsing and managing Microsoft Active Directory accounts.

ADKombajn was created to simplify everyday Active Directory support tasks by collecting frequently used account, group and manager-related information in one place.

The application is written in PowerShell and uses a graphical Windows interface.

> The current user interface is available in Polish.

## Features

ADKombajn currently provides:

* Active Directory account lookup by login
* basic account information
* account status and expiration information
* group membership list
* accounts assigned to the selected user as manager
* groups managed by the selected user
* operation log displayed directly in the application
* tab-based interface for separating different types of information
* copy-friendly output for further analysis or reporting

## Screenshots

![ADKombajn main window](docs/images/adkombajn-main.png)

More screenshots will be added as the project develops.

## Requirements

* Windows 10, Windows 11 or Windows Server
* Windows PowerShell 5.1
* network access to an Active Directory domain
* permissions required to read the requested Active Directory objects


## Running the application

Clone the repository:

```powershell
git clone https://github.com/nachszon/ADKombajn.git
cd ADKombajn
```

Run the main PowerShell script:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\ADKombajn.ps1
```

Alternatively, start the script from an existing PowerShell session:

```powershell
.\ADKombajn.ps1
```

## Usage

1. Start ADKombajn.
2. Enter the account login in the **Login konta** field.
3. Start the search.
4. Review the information available in the application tabs:

   * account information
   * group memberships
   * manager accounts
   * managed groups
   * operation log

The amount of information returned depends on the user's Active Directory permissions.

## Project structure

```text
ADKombajn/
├── ADKombajn.ps1
├── README.md
├── LICENSE
├── CHANGELOG.md
├── docs/
│   └── images/
└── src/
```

The final structure may change as the application is split into separate modules.

## Versioning

The project uses Semantic Versioning:

```text
MAJOR.MINOR.PATCH
```

Example:

```text
2.12.0
```

* **MAJOR** — incompatible changes or a major application redesign
* **MINOR** — new functionality compatible with the current version
* **PATCH** — bug fixes and minor internal improvements

## Security

ADKombajn does not include credentials, passwords or organization-specific configuration.

Before using the application in a production environment:

* review the source code
* verify the configured Active Directory queries
* test the application in a non-production environment
* use an account with the minimum required permissions
* do not commit internal domain names, credentials or confidential data to the repository

Organization-specific modules and internal tools are not included in the public repository.

## Known limitations

* the user interface is currently available only in Polish
* the application currently targets Windows PowerShell 5.1
* functionality depends on the Active Directory PowerShell module
* Active Directory permissions may limit the returned results
* the application has currently been tested only in selected domain environments

## Roadmap

Planned improvements may include:

* English user interface
* configurable domain selection
* improved search and filtering
* exporting selected results
* modular PowerShell code structure
* configuration file support
* additional validation and error handling
* signed releases
* standalone executable packages

## Contributing

Bug reports, ideas and pull requests are welcome.

When reporting an issue, include:

* Windows version
* PowerShell version
* Active Directory module version
* application version
* steps required to reproduce the problem
* error message with confidential information removed

Do not include real usernames, domain names, distinguished names or other organization-specific data.

## Disclaimer

This project is not affiliated with or endorsed by Microsoft.

The software is provided as-is, without warranty. Always review and test the code before using it in a production Active Directory environment.

## License

This project is licensed under the GNU General Public License v3.0.

See the [LICENSE](LICENSE) file for details.
