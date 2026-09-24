# ==================================================
# AD / LDAP tools
# ==================================================

function Is-Blank {
    param($Value)
    if ($null -eq $Value) { return $true }
    return ([string]$Value).Trim().Length -eq 0
}

function Escape-LdapFilterValue {
    param([string]$Value)
    if ($null -eq $Value) { return "" }

    $escaped = $Value.Replace('\', '\5c')
    $escaped = $escaped.Replace('*', '\2a')
    $escaped = $escaped.Replace('(', '\28')
    $escaped = $escaped.Replace(')', '\29')
    $escaped = $escaped.Replace(([string][char]0), '\00')
    return $escaped
}

function Get-SearchPropertyValue {
    param(
        $Properties,
        [string]$Name
    )

    if ($null -eq $Properties -or (Is-Blank $Name)) { return "" }

    try {
        $matchingKey = $null
        foreach ($propertyName in $Properties.PropertyNames) {
            if ($propertyName -ieq $Name) {
                $matchingKey = $propertyName
                break
            }
        }

        if ($null -ne $matchingKey -and $Properties[$matchingKey].Count -gt 0 -and $null -ne $Properties[$matchingKey][0]) {
            return $Properties[$matchingKey][0]
        }
    }
    catch { }

    return ""
}

function Convert-ADFileTimeToText {
    param($Value)

    try {
        if ($null -eq $Value) { return "" }
        $raw = $Value

        if ($Value -is [System.Collections.ICollection]) {
            if ($Value.Count -gt 0) { $raw = $Value[0] } else { return "" }
        }

        if ($null -eq $raw) { return "" }
        $fileTime = [Int64]$raw
        if ($fileTime -le 0) { return "" }
        return [DateTime]::FromFileTime($fileTime).ToString("yyyy-MM-dd HH:mm:ss")
    }
    catch { return "" }
}

function Convert-UserAccountControlToEnabled {
    param($Value)

    try {
        if ($null -eq $Value -or (Is-Blank $Value)) { return "" }
        $uac = [int]$Value
        if (($uac -band 2) -eq 2) { return "False" }
        return "True"
    }
    catch { return "" }
}

function Get-LdapBasePath {
    param([string]$DomainOrDc)

    $rootDse = $null
    try {
        $rootDse = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainOrDc/RootDSE")
        $defaultNamingContext = [string]$rootDse.Properties["defaultNamingContext"].Value
        if (-not (Is-Blank $defaultNamingContext)) {
            return "LDAP://$DomainOrDc/$defaultNamingContext"
        }
    }
    finally {
        if ($null -ne $rootDse) { $rootDse.Dispose() }
    }

    return "LDAP://$DomainOrDc"
}

function Get-LdapPortFromUi {
    if ($chkUseLdaps.Checked) { return 636 }
    return 389
}

function New-LdapConnectionCurrentUser {
    param(
        [string]$Server,
        [bool]$UseLdaps = $false,
        [int]$Port = 389
    )

    $identifier = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier -ArgumentList $Server, $Port, $false, $false
    $connection = New-Object System.DirectoryServices.Protocols.LdapConnection -ArgumentList $identifier
    $connection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Negotiate
    $connection.Timeout = New-TimeSpan -Seconds 35
    $connection.SessionOptions.ProtocolVersion = 3

    if ($UseLdaps) {
        $connection.SessionOptions.SecureSocketLayer = $true
    }
    else {
        # Encrypted SASL channel over port 389, so unicodePwd changes do not require LDAPS.
        $connection.SessionOptions.Signing = $true
        $connection.SessionOptions.Sealing = $true
    }

    $connection.Bind()
    return $connection
}

function New-LdapConnectionWithCredentials {
    param(
        [string]$Server,
        [string]$Domain,
        [string]$Login,
        [string]$Password,
        [bool]$UseLdaps = $false,
        [int]$Port = 389
    )

    $identifier = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier -ArgumentList $Server, $Port, $false, $false
    $connection = New-Object System.DirectoryServices.Protocols.LdapConnection -ArgumentList $identifier
    $connection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Negotiate
    $connection.Timeout = New-TimeSpan -Seconds 20
    $connection.SessionOptions.ProtocolVersion = 3

    if ($UseLdaps) {
        $connection.SessionOptions.SecureSocketLayer = $true
    }
    else {
        $connection.SessionOptions.Signing = $true
        $connection.SessionOptions.Sealing = $true
    }

    if ($Login -match "^([^\\]+)\\(.+)$") {
        $cred = New-Object System.Net.NetworkCredential($Matches[2], $Password, $Matches[1])
    }
    elseif ($Login -match "@") {
        $cred = New-Object System.Net.NetworkCredential($Login, $Password)
    }
    else {
        $cred = New-Object System.Net.NetworkCredential($Login, $Password, $Domain)
    }

    $connection.Bind($cred)
    return $connection
}

function Convert-ToUnicodePwdBytes {
    param([Parameter(Mandatory = $true)][string]$Password)

    # AD expects the password in quotation marks and UTF-16LE.
    # The comma before $bytes is important: without it PowerShell may expand byte[]
    # to System.Object[], causing DirectoryAttributeModification.Add() to choose
    # an incorrect overload and fail with a System.Uri/System.Object[] error.
    [byte[]]$bytes = [System.Text.Encoding]::Unicode.GetBytes('"' + $Password + '"')
    return ,$bytes
}
function Get-FriendlyLdapError {
    param([System.Exception]$Exception)

    $message = $Exception.Message
    $code = ""

    if ($Exception -is [System.DirectoryServices.Protocols.DirectoryOperationException]) {
        $resp = $Exception.Response
        if ($null -ne $resp) {
            $code = [string]$resp.ResultCode
            if (-not (Is-Blank $resp.ErrorMessage)) { $message = $resp.ErrorMessage }
        }
    }
    elseif ($Exception -is [System.DirectoryServices.Protocols.LdapException]) {
        $code = [string]$Exception.ErrorCode
    }

    $hint = ""
    $lower = $message.ToLowerInvariant()

    if ($lower -match "constraint|unwilling|0000052d|52d") {
        $hint = Get-UiText "Ldap.HintPasswordPolicy"
    }
    elseif ($lower -match "invalid credentials|52e|775|data 52e") {
        $hint = Get-UiText "Ldap.HintCredentials"
    }
    elseif ($lower -match "server is unavailable|cannot contact|unavailable") {
        $hint = Get-UiText "Ldap.HintConnection"
    }
    elseif ($lower -match "confidentiality|required|stronger") {
        $hint = Get-UiText "Ldap.HintSecureChannel"
    }

    if (-not (Is-Blank $code)) {
        $codeText = Get-UiText "Ldap.Code" @($code)
        $message = "$message`r`n$codeText"
    }
    if (-not (Is-Blank $hint)) {
        $hintText = Get-UiText "Ldap.Hint" @($hint)
        $message = "$message`r`n`r`n$hintText"
    }

    return $message
}

function Find-AdUserBasic {
    param(
        [string]$DomainOrDc,
        [string]$Login
    )

    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc
    $root = $null
    $searcher = $null
    $result = $null

    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = 1000

        $escaped = Escape-LdapFilterValue -Value $Login
        if ($Login -match "@") {
            $searcher.Filter = "(&(objectCategory=person)(objectClass=user)(|(userPrincipalName=$escaped)(sAMAccountName=$escaped)))"
        }
        else {
            $searcher.Filter = "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$escaped))"
        }

        foreach ($p in @("sAMAccountName", "name", "displayName", "userPrincipalName", "distinguishedName", "description", "userAccountControl", "pwdLastSet")) {
            [void]$searcher.PropertiesToLoad.Add($p)
        }

        $result = $searcher.FindOne()
        if ($null -eq $result) { return $null }

        $props = $result.Properties
        $dn = [string](Get-SearchPropertyValue -Properties $props -Name "distinguishedName")
        $sam = [string](Get-SearchPropertyValue -Properties $props -Name "sAMAccountName")
        $uac = Get-SearchPropertyValue -Properties $props -Name "userAccountControl"
        $pwd = Get-SearchPropertyValue -Properties $props -Name "pwdLastSet"

        return [PSCustomObject]@{
            SamAccountName    = $sam
            Name              = [string](Get-SearchPropertyValue -Properties $props -Name "name")
            DisplayName       = [string](Get-SearchPropertyValue -Properties $props -Name "displayName")
            UserPrincipalName = [string](Get-SearchPropertyValue -Properties $props -Name "userPrincipalName")
            Description       = [string](Get-SearchPropertyValue -Properties $props -Name "description")
            Enabled           = Convert-UserAccountControlToEnabled -Value $uac
            PasswordLastSet   = Convert-ADFileTimeToText -Value $pwd
            DistinguishedName = $dn
        }
    }
    finally {
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}

function Test-AdPasswordNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$Login,
        [string]$Password,
        [bool]$UseLdaps = $false,
        [int]$Port = 389
    )

    # Password validation intentionally follows the simple validPassword.ps1 approach:
    # PrincipalContext.ValidateCredentials().
    # Password changes still use LDAP unicodePwd without UserPrincipal.ChangePassword().
    # UseLdaps/Port remain in the signature for GUI compatibility, while
    # ValidateCredentials selects the domain/controller connection mechanism itself.

    $context = $null

    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement

        $loginToValidate = $Login.Trim()

        # Strip the domain prefix from DOMAIN\login because ValidateCredentials
        # in a domain context normally expects a login name or UPN.
        if ($loginToValidate -match "^[^\\]+\\(.+)$") {
            $loginToValidate = $Matches[1]
        }

        $context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext(
            [System.DirectoryServices.AccountManagement.ContextType]::Domain,
            $DomainOrDc
        )

        $ok = $context.ValidateCredentials($loginToValidate, $Password)

        if ($ok) {
            return [PSCustomObject]@{ Success = $true; Message = (Get-UiText "Password.Valid") }
        }

        return [PSCustomObject]@{
            Success = $false
            Message = Get-UiText "Password.Invalid"
        }
    }
    catch {
        return [PSCustomObject]@{ Success = $false; Message = Get-FriendlyLdapError -Exception $_.Exception }
    }
    finally {
        if ($null -ne $context) { $context.Dispose() }
    }
}
function Change-AdAccountPasswordNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$Login,
        [string]$OldPassword,
        [string]$NewPassword,
        [bool]$UseLdaps = $false,
        [int]$Port = 389
    )

    $connection = $null
    $oldBytes = $null
    $newBytes = $null

    try {
        $target = Find-AdUserBasic -DomainOrDc $DomainOrDc -Login $Login
        if ($null -eq $target -or (Is-Blank $target.DistinguishedName)) {
            throw (Get-UiText "Error.AccountNotFound" @($DomainOrDc, $Login))
        }

        $connection = New-LdapConnectionCurrentUser -Server $DomainOrDc -UseLdaps $UseLdaps -Port $Port

        $oldBytes = Convert-ToUnicodePwdBytes -Password $OldPassword
        $newBytes = Convert-ToUnicodePwdBytes -Password $NewPassword

        $deleteOld = New-Object System.DirectoryServices.Protocols.DirectoryAttributeModification
        $deleteOld.Name = "unicodePwd"
        $deleteOld.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Delete
        [void]$deleteOld.Add([byte[]]$oldBytes)

        $addNew = New-Object System.DirectoryServices.Protocols.DirectoryAttributeModification
        $addNew.Name = "unicodePwd"
        $addNew.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Add
        [void]$addNew.Add([byte[]]$newBytes)

        $request = New-Object System.DirectoryServices.Protocols.ModifyRequest
        $request.DistinguishedName = $target.DistinguishedName
        [void]$request.Modifications.Add($deleteOld)
        [void]$request.Modifications.Add($addNew)

        $response = $connection.SendRequest($request)

        return [PSCustomObject]@{
            Success = $true
            Message = Get-UiText "Password.Changed"
            Result  = [string]$response.ResultCode
            Target  = $target
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Message = Get-FriendlyLdapError -Exception $_.Exception
            Result  = $_.Exception.GetType().FullName
            Target  = $null
        }
    }
    finally {
        if ($null -ne $connection) { $connection.Dispose() }
        if ($null -ne $oldBytes) { [Array]::Clear($oldBytes, 0, $oldBytes.Length) }
        if ($null -ne $newBytes) { [Array]::Clear($newBytes, 0, $newBytes.Length) }
        $oldBytes = $null
        $newBytes = $null
    }
}


function Convert-UserAccountControlToFlagsText {
    param($Value)

    try {
        if ($null -eq $Value -or (Is-Blank $Value)) { return "" }
        $uac = [int]$Value
        $flags = @()
        $map = @(
            @{ Bit = 0x0001; Name = "SCRIPT" },
            @{ Bit = 0x0002; Name = "ACCOUNTDISABLE" },
            @{ Bit = 0x0008; Name = "HOMEDIR_REQUIRED" },
            @{ Bit = 0x0010; Name = "LOCKOUT" },
            @{ Bit = 0x0020; Name = "PASSWD_NOTREQD" },
            @{ Bit = 0x0040; Name = "PASSWD_CANT_CHANGE" },
            @{ Bit = 0x0080; Name = "ENCRYPTED_TEXT_PWD_ALLOWED" },
            @{ Bit = 0x0100; Name = "TEMP_DUPLICATE_ACCOUNT" },
            @{ Bit = 0x0200; Name = "NORMAL_ACCOUNT" },
            @{ Bit = 0x0800; Name = "INTERDOMAIN_TRUST_ACCOUNT" },
            @{ Bit = 0x1000; Name = "WORKSTATION_TRUST_ACCOUNT" },
            @{ Bit = 0x2000; Name = "SERVER_TRUST_ACCOUNT" },
            @{ Bit = 0x10000; Name = "DONT_EXPIRE_PASSWORD" },
            @{ Bit = 0x20000; Name = "MNS_LOGON_ACCOUNT" },
            @{ Bit = 0x40000; Name = "SMARTCARD_REQUIRED" },
            @{ Bit = 0x80000; Name = "TRUSTED_FOR_DELEGATION" },
            @{ Bit = 0x100000; Name = "NOT_DELEGATED" },
            @{ Bit = 0x200000; Name = "USE_DES_KEY_ONLY" },
            @{ Bit = 0x400000; Name = "DONT_REQ_PREAUTH" },
            @{ Bit = 0x800000; Name = "PASSWORD_EXPIRED" },
            @{ Bit = 0x1000000; Name = "TRUSTED_TO_AUTH_FOR_DELEGATION" },
            @{ Bit = 0x04000000; Name = "PARTIAL_SECRETS_ACCOUNT" }
        )

        foreach ($item in $map) {
            if (($uac -band [int]$item.Bit) -ne 0) { $flags += [string]$item.Name }
        }

        if ($flags.Count -eq 0) { return [string]$uac }
        return ("{0} ({1})" -f $uac, ($flags -join ", "))
    }
    catch { return [string]$Value }
}

function Convert-ComputedUserAccountControlToFlagsText {
    param($Value)

    try {
        if ($null -eq $Value -or (Is-Blank $Value)) { return "" }
        $uac = [int]$Value
        $flags = @()
        $map = @(
            @{ Bit = 0x00000010; Name = "LOCKOUT" },
            @{ Bit = 0x00800000; Name = "PASSWORD_EXPIRED" }
        )

        foreach ($item in $map) {
            if (($uac -band [int]$item.Bit) -ne 0) { $flags += [string]$item.Name }
        }

        if ($flags.Count -eq 0) { return [string]$uac }
        return ("{0} ({1})" -f $uac, ($flags -join ", "))
    }
    catch { return [string]$Value }
}

function Convert-ADFileTimeToReadableText {
    param(
        $Value,
        [string]$ZeroText = ""
    )

    try {
        if ($null -eq $Value) { return "" }
        $raw = $Value

        if ($Value -is [System.Collections.ICollection]) {
            if ($Value.Count -gt 0) { $raw = $Value[0] } else { return "" }
        }

        if ($null -eq $raw) { return "" }
        $fileTime = [Int64]$raw
        if ($fileTime -le 0) {
            if (-not (Is-Blank $ZeroText)) { return $ZeroText }
            return [string]$fileTime
        }

        return [DateTime]::FromFileTime($fileTime).ToString("yyyy-MM-dd HH:mm:ss")
    }
    catch { return [string]$Value }
}

function Convert-ADAccountExpiresToText {
    param($Value)

    try {
        if ($null -eq $Value -or (Is-Blank $Value)) { return "" }
        $raw = [Int64]$Value
        if ($raw -eq 0 -or $raw -eq 9223372036854775807) { return (Get-UiText "Value.Never") }
        return (Convert-ADFileTimeToReadableText -Value $raw)
    }
    catch { return [string]$Value }
}

function Convert-BooleanText {
    param([bool]$Value)
    if ($Value) { return "True" }
    return "False"
}

function Get-LockedOutTextFromAdValues {
    param(
        $ComputedUac,
        $LockoutTime
    )

    try {
        if ($null -ne $ComputedUac -and -not (Is-Blank $ComputedUac)) {
            $computed = [int]$ComputedUac
            return (Convert-BooleanText -Value (($computed -band 0x00000010) -ne 0))
        }
    }
    catch { }

    # Fallback used only when the domain controller does not return
    # msDS-User-Account-Control-Computed. A non-zero lockoutTime does not always
    # indicate a current lockout after automatic unlock, but is better than no data.
    try {
        if ($null -ne $LockoutTime -and -not (Is-Blank $LockoutTime)) {
            return (Convert-BooleanText -Value ([Int64]$LockoutTime -gt 0))
        }
    }
    catch { }

    return ""
}

function New-AccountPropertyRow {
    param(
        [string]$Attribute,
        [string]$Value,
        [int]$Count = 1
    )

    return [PSCustomObject]@{
        Attribute = $Attribute
        Value     = $Value
        Count     = $Count
    }
}

function Convert-AdByteArrayValueToText {
    param(
        [string]$Name,
        [byte[]]$Bytes
    )

    if ($null -eq $Bytes) { return "" }

    try {
        if ($Name -ieq "objectGuid") {
            $guid = New-Object System.Guid -ArgumentList (,$Bytes)
            return $guid.ToString()
        }
    }
    catch { }

    try {
        if (($Name -ieq "objectSid") -or ($Name -ieq "sIDHistory")) {
            $sid = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList @($Bytes, 0)
            return $sid.Value
        }
    }
    catch { }

    try {
        return "0x" + ([System.BitConverter]::ToString($Bytes).Replace("-", ""))
    }
    catch {
        return "<byte[]>"
    }
}

function Convert-AdPropertySingleValueToText {
    param(
        [string]$Name,
        $Value
    )

    if ($null -eq $Value) { return "" }

    try {
        if ($Value -is [byte[]]) {
            return Convert-AdByteArrayValueToText -Name $Name -Bytes ([byte[]]$Value)
        }
    }
    catch { }

    try {
        $fileTimeNames = @("pwdLastSet", "lastLogon", "lastLogonTimestamp", "lockoutTime", "badPasswordTime", "msDS-UserPasswordExpiryTimeComputed")
        if ($fileTimeNames -contains $Name) {
            $txt = Convert-ADFileTimeToText -Value $Value
            if (-not (Is-Blank $txt)) { return $txt }
            return [string]$Value
        }

        if ($Name -ieq "accountExpires") {
            $raw = [Int64]$Value
            if ($raw -eq 0 -or $raw -eq 9223372036854775807) {
                $neverText = Get-UiText "Value.Never"
                return "$neverText ($raw)"
            }
            $txt = Convert-ADFileTimeToText -Value $Value
            if (-not (Is-Blank $txt)) { return $txt }
            return [string]$Value
        }

        if ($Name -ieq "userAccountControl") {
            return Convert-UserAccountControlToFlagsText -Value $Value
        }

        if ($Name -ieq "msDS-User-Account-Control-Computed") {
            return Convert-ComputedUserAccountControlToFlagsText -Value $Value
        }
    }
    catch { }

    return [string]$Value
}

function Convert-AdPropertyValueToText {
    param(
        [string]$Name,
        $Value
    )

    if ($null -eq $Value) { return "" }

    try {
        if ($Value -is [byte[]]) {
            return Convert-AdByteArrayValueToText -Name $Name -Bytes ([byte[]]$Value)
        }
    }
    catch { }

    $values = @()
    try {
        if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
            foreach ($v in $Value) { $values += ,$v }
        }
        else {
            $values += ,$Value
        }
    }
    catch {
        $values += ,$Value
    }

    $texts = @()
    foreach ($v in $values) {
        $texts += (Convert-AdPropertySingleValueToText -Name $Name -Value $v)
    }

    return ($texts -join "; ")
}

function Get-AdUserAllPropertiesNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$Login
    )

    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc
    $root = $null
    $searcher = $null
    $result = $null

    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = 1000

        $loginToSearch = $Login.Trim()
        if ($loginToSearch -match "^[^\\]+\\(.+)$") {
            $loginToSearch = $Matches[1]
        }

        $escaped = Escape-LdapFilterValue -Value $loginToSearch
        if ($loginToSearch -match "@") {
            $searcher.Filter = "(&(objectCategory=person)(objectClass=user)(|(userPrincipalName=$escaped)(sAMAccountName=$escaped)))"
        }
        else {
            $searcher.Filter = "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$escaped))"
        }

        # "*" retrieves regular LDAP attributes. The attributes below are added
        # explicitly to provide values similar to Get-ADUser -Properties *.
        foreach ($p in @(
            "*",
            "pwdLastSet",
            "lockoutTime",
            "msDS-User-Account-Control-Computed",
            "lastLogonTimestamp",
            "lastLogon",
            "accountExpires",
            "userAccountControl",
            "badPwdCount",
            "badPasswordTime"
        )) {
            try { [void]$searcher.PropertiesToLoad.Add($p) } catch { }
        }

        $result = $searcher.FindOne()
        if ($null -eq $result) {
            throw (Get-UiText "Error.AccountNotFound" @($DomainOrDc, $Login))
        }

        $props = $result.Properties
        $rows = @()

        foreach ($name in @($props.PropertyNames | Sort-Object)) {
            $values = $props[$name]
            $count = 0
            try { $count = $values.Count } catch { $count = 1 }
            $text = Convert-AdPropertyValueToText -Name $name -Value $values

            $rows += [PSCustomObject]@{
                Attribute = [string]$name
                Value     = [string]$text
                Count     = [int]$count
            }
        }

        # Computed/helper values corresponding to fields conveniently exposed by Get-ADUser.
        $computedRows = @()

        $uac = Get-SearchPropertyValue -Properties $props -Name "userAccountControl"
        $computedUac = Get-SearchPropertyValue -Properties $props -Name "msDS-User-Account-Control-Computed"
        $pwd = Get-SearchPropertyValue -Properties $props -Name "pwdLastSet"
        $lockoutTime = Get-SearchPropertyValue -Properties $props -Name "lockoutTime"
        $lastLogonTimestamp = Get-SearchPropertyValue -Properties $props -Name "lastLogonTimestamp"
        $accountExpires = Get-SearchPropertyValue -Properties $props -Name "accountExpires"

        if (-not (Is-Blank $uac)) {
            $uacInt = [int]$uac
            $computedRows += (New-AccountPropertyRow -Attribute "Enabled" -Value (Convert-UserAccountControlToEnabled -Value $uac))
            $computedRows += (New-AccountPropertyRow -Attribute "PasswordNeverExpires" -Value (Convert-BooleanText -Value (($uacInt -band 0x00010000) -ne 0)))
            $computedRows += (New-AccountPropertyRow -Attribute "PasswordNotRequired" -Value (Convert-BooleanText -Value (($uacInt -band 0x00000020) -ne 0)))
            $computedRows += (New-AccountPropertyRow -Attribute "SmartcardLogonRequired" -Value (Convert-BooleanText -Value (($uacInt -band 0x00040000) -ne 0)))
            $computedRows += (New-AccountPropertyRow -Attribute "TrustedForDelegation" -Value (Convert-BooleanText -Value (($uacInt -band 0x00080000) -ne 0)))
            $computedRows += (New-AccountPropertyRow -Attribute "userAccountControlFlags" -Value (Convert-UserAccountControlToFlagsText -Value $uac))
        }

        $lockedOut = Get-LockedOutTextFromAdValues -ComputedUac $computedUac -LockoutTime $lockoutTime
        if (-not (Is-Blank $lockedOut)) {
            $computedRows += (New-AccountPropertyRow -Attribute "LockedOut" -Value $lockedOut)
        }

        if (-not (Is-Blank $computedUac)) {
            $computedInt = [int]$computedUac
            $computedRows += (New-AccountPropertyRow -Attribute "PasswordExpired" -Value (Convert-BooleanText -Value (($computedInt -band 0x00800000) -ne 0)))
            $computedRows += (New-AccountPropertyRow -Attribute "msDS-User-Account-Control-ComputedFlags" -Value (Convert-ComputedUserAccountControlToFlagsText -Value $computedUac))
        }

        if (-not (Is-Blank $pwd)) {
            $computedRows += (New-AccountPropertyRow -Attribute "PasswordLastSet" -Value (Convert-ADFileTimeToReadableText -Value $pwd -ZeroText "") )
        }

        if (-not (Is-Blank $lastLogonTimestamp)) {
            $computedRows += (New-AccountPropertyRow -Attribute "LastLogonDate" -Value (Convert-ADFileTimeToReadableText -Value $lastLogonTimestamp))
        }

        if (-not (Is-Blank $accountExpires)) {
            $computedRows += (New-AccountPropertyRow -Attribute "AccountExpirationDate" -Value (Convert-ADAccountExpiresToText -Value $accountExpires))
        }

        if ($computedRows.Count -gt 0) {
            $rows = @($computedRows) + $rows
        }

        return @($rows)
    }
    finally {
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}

function Get-DirectoryEntryPropertyValue {
    param(
        [System.DirectoryServices.DirectoryEntry]$Entry,
        [string]$Name
    )

    try {
        if ($null -ne $Entry -and -not (Is-Blank $Name) -and $Entry.Properties.Contains($Name) -and $Entry.Properties[$Name].Count -gt 0) {
            return $Entry.Properties[$Name].Value
        }
    }
    catch { }

    return ""
}

function Convert-GroupTypeToKindText {
    param($Value)

    try {
        if ($null -eq $Value -or (Is-Blank $Value)) { return "" }
        $groupType = [Int64]$Value
        if (($groupType -band 2147483648) -ne 0) { return "Security" }
        return "Distribution"
    }
    catch { return "" }
}

function Convert-GroupTypeToScopeText {
    param($Value)

    try {
        if ($null -eq $Value -or (Is-Blank $Value)) { return "" }
        $groupType = [Int64]$Value
        if (($groupType -band 0x00000008) -ne 0) { return "Universal" }
        if (($groupType -band 0x00000004) -ne 0) { return "Domain local" }
        if (($groupType -band 0x00000002) -ne 0) { return "Global" }
        if (($groupType -band 0x00000001) -ne 0) { return "Builtin local" }
        return ""
    }
    catch { return "" }
}

function New-AccountGroupRowFromSearchProperties {
    param(
        $Properties,
        [string]$Source
    )

    $groupType = Get-SearchPropertyValue -Properties $Properties -Name "groupType"
    return [PSCustomObject]@{
        Name              = [string](Get-SearchPropertyValue -Properties $Properties -Name "name")
        SamAccountName    = [string](Get-SearchPropertyValue -Properties $Properties -Name "sAMAccountName")
        DisplayName       = [string](Get-SearchPropertyValue -Properties $Properties -Name "displayName")
        Type              = Convert-GroupTypeToKindText -Value $groupType
        Scope             = Convert-GroupTypeToScopeText -Value $groupType
        Source            = [string]$Source
        Description       = [string](Get-SearchPropertyValue -Properties $Properties -Name "description")
        DistinguishedName = [string](Get-SearchPropertyValue -Properties $Properties -Name "distinguishedName")
    }
}

function Convert-SidStringToLdapFilterValue {
    param([string]$Sid)

    if (Is-Blank $Sid) { return "" }

    $securityIdentifier = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $Sid
    $bytes = New-Object byte[] ($securityIdentifier.BinaryLength)
    $securityIdentifier.GetBinaryForm($bytes, 0)

    $parts = @()
    foreach ($b in $bytes) {
        $parts += ("\{0:X2}" -f [int]$b)
    }
    return ($parts -join "")
}

function Find-AdGroupByDistinguishedNameNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$DistinguishedName,
        [string]$Source = "memberOf"
    )

    if (Is-Blank $DistinguishedName) { return $null }

    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc
    $root = $null
    $searcher = $null
    $result = $null

    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = 1000
        $escapedDn = Escape-LdapFilterValue -Value $DistinguishedName
        $searcher.Filter = "(&(objectClass=group)(distinguishedName=$escapedDn))"

        foreach ($p in @("sAMAccountName", "name", "displayName", "groupType", "description", "distinguishedName")) {
            [void]$searcher.PropertiesToLoad.Add($p)
        }

        $result = $searcher.FindOne()
        if ($null -eq $result) { return $null }
        return (New-AccountGroupRowFromSearchProperties -Properties $result.Properties -Source $Source)
    }
    finally {
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}

function Find-AdGroupBySidNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$Sid,
        [string]$Source = "primaryGroupID"
    )

    if (Is-Blank $Sid) { return $null }

    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc
    $root = $null
    $searcher = $null
    $result = $null

    try {
        $sidFilter = Convert-SidStringToLdapFilterValue -Sid $Sid
        if (Is-Blank $sidFilter) { return $null }

        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = 1000
        $searcher.Filter = "(&(objectClass=group)(objectSid=$sidFilter))"

        foreach ($p in @("sAMAccountName", "name", "displayName", "groupType", "description", "distinguishedName")) {
            [void]$searcher.PropertiesToLoad.Add($p)
        }

        $result = $searcher.FindOne()
        if ($null -eq $result) { return $null }
        return (New-AccountGroupRowFromSearchProperties -Properties $result.Properties -Source $Source)
    }
    finally {
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}

function Get-AdAccountGroupsNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$Login,
        $ProgressWindow = $null
    )

    Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.FindAccount") -Detail "$DomainOrDc\$Login" -Marquee $true
    $target = Find-AdUserBasic -DomainOrDc $DomainOrDc -Login $Login
    if ($null -eq $target -or (Is-Blank $target.DistinguishedName)) {
        throw (Get-UiText "Error.AccountNotFound" @($DomainOrDc, $Login))
    }

    $entry = $null
    $rows = @()

    try {
        $entry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainOrDc/$($target.DistinguishedName)")
        Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.ReadAccount") -Detail $target.DistinguishedName -Marquee $true
        try { $entry.RefreshCache(@("memberOf", "primaryGroupID", "objectSid")) } catch { }

        $memberOf = @()
        try {
            foreach ($dn in $entry.Properties["memberOf"]) {
                if (-not (Is-Blank $dn)) { $memberOf += [string]$dn }
            }
        }
        catch { }

        $memberOfUnique = @($memberOf | Sort-Object -Unique)
        $groupIndex = 0
        $groupTotal = $memberOfUnique.Count
        if ($groupTotal -gt 0) {
            Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.ReadMemberOf") -Detail "0 / $groupTotal" -Value 0 -Maximum $groupTotal
        }

        foreach ($groupDn in $memberOfUnique) {
            $groupIndex++
            Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.ReadMemberOf") -Detail "$groupIndex / $groupTotal" -Value $groupIndex -Maximum $groupTotal
            $groupRow = Find-AdGroupByDistinguishedNameNoRsat -DomainOrDc $DomainOrDc -DistinguishedName $groupDn -Source "memberOf"
            if ($null -ne $groupRow) { $rows += $groupRow }
        }

        # primaryGroupID usually represents a group such as Domain Users and is absent
        # from memberOf, so it is added separately to provide a more complete list.
        try {
            $primaryGroupId = Get-DirectoryEntryPropertyValue -Entry $entry -Name "primaryGroupID"
            $objectSid = Get-DirectoryEntryPropertyValue -Entry $entry -Name "objectSid"

            if ($null -ne $primaryGroupId -and -not (Is-Blank $primaryGroupId) -and $null -ne $objectSid) {
                $sidObj = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList @([byte[]]$objectSid, 0)
                $userSid = $sidObj.Value
                $lastDash = $userSid.LastIndexOf("-")
                if ($lastDash -gt 0) {
                    $domainSid = $userSid.Substring(0, $lastDash)
                    $primaryGroupSid = "$domainSid-$([int]$primaryGroupId)"
                    Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.CheckPrimaryGroup") -Detail $primaryGroupSid -Marquee $true
                    $primaryRow = Find-AdGroupBySidNoRsat -DomainOrDc $DomainOrDc -Sid $primaryGroupSid -Source "primaryGroupID"
                    if ($null -ne $primaryRow) { $rows += $primaryRow }
                }
            }
        }
        catch { }

        $unique = @{}
        $deduped = @()
        foreach ($row in $rows) {
            if ($null -eq $row) { continue }
            $key = [string]$row.DistinguishedName
            if (Is-Blank $key) { $key = [string]$row.SamAccountName }
            if (Is-Blank $key) { $key = [string]$row.Name }
            if (Is-Blank $key) { continue }
            $lowerKey = $key.ToLowerInvariant()
            if (-not $unique.ContainsKey($lowerKey)) {
                $unique[$lowerKey] = $true
                $deduped += $row
            }
        }

        Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.OrganizeResult") -Detail (Get-UiText "Progress.DeduplicateGroups") -Marquee $true
        return @($deduped | Sort-Object -Property @("Name", "SamAccountName"))
    }
    finally {
        if ($null -ne $entry) { $entry.Dispose() }
    }
}



function Get-SearchPropertyValues {
    param(
        $Properties,
        [string]$Name
    )

    $values = @()
    if ($null -eq $Properties -or (Is-Blank $Name)) { return @() }

    try {
        $matchingKey = $null
        foreach ($propertyName in $Properties.PropertyNames) {
            if ($propertyName -ieq $Name) {
                $matchingKey = $propertyName
                break
            }
        }

        if ($null -ne $matchingKey -and $Properties[$matchingKey].Count -gt 0) {
            foreach ($v in $Properties[$matchingKey]) {
                if ($null -ne $v) { $values += $v }
            }
        }
    }
    catch { }

    return @($values)
}

function Get-AdObjectTypeFromProperties {
    param($Properties)

    try {
        $classes = @(Get-SearchPropertyValues -Properties $Properties -Name "objectClass")
        if ($classes.Count -gt 0) {
            return [string]$classes[$classes.Count - 1]
        }
    }
    catch { }

    return [string](Get-SearchPropertyValue -Properties $Properties -Name "objectClass")
}

function Find-AdGroupBasicNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$GroupIdentity
    )

    if (Is-Blank $GroupIdentity) { return $null }

    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc
    $root = $null
    $searcher = $null
    $result = $null

    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = 1000

        $escaped = Escape-LdapFilterValue -Value $GroupIdentity
        if ($GroupIdentity -match "^CN=.*?,.*DC=.*") {
            $searcher.Filter = "(&(objectClass=group)(distinguishedName=$escaped))"
        }
        else {
            $searcher.Filter = "(&(objectClass=group)(|(sAMAccountName=$escaped)(name=$escaped)(cn=$escaped)))"
        }

        foreach ($p in @("sAMAccountName", "name", "displayName", "description", "distinguishedName", "groupType", "objectSid")) {
            [void]$searcher.PropertiesToLoad.Add($p)
        }

        $result = $searcher.FindOne()
        if ($null -eq $result) { return $null }

        return (New-AccountGroupRowFromSearchProperties -Properties $result.Properties -Source "group")
    }
    finally {
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}

function Get-AdGroupMemberDistinguishedNamesNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$GroupDistinguishedName,
        $ProgressWindow = $null
    )

    $memberDns = @()
    if (Is-Blank $GroupDistinguishedName) { return @() }

    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc
    $root = $null
    $searcher = $null

    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = 1000
        $escapedDn = Escape-LdapFilterValue -Value $GroupDistinguishedName
        $searcher.Filter = "(&(objectClass=group)(distinguishedName=$escapedDn))"

        $rangeStart = 0
        $rangeStep = 1500
        $done = $false

        while (-not $done) {
            try { $searcher.PropertiesToLoad.Clear() } catch { }
            $rangeEnd = $rangeStart + $rangeStep - 1
            $rangeProp = "member;range=$rangeStart-$rangeEnd"
            [void]$searcher.PropertiesToLoad.Add($rangeProp)

            Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.ReadMemberList") -Detail (Get-UiText "Progress.Range" @($rangeStart, $rangeEnd)) -Marquee $true
            $result = $searcher.FindOne()
            if ($null -eq $result) { break }

            $foundRangeProperty = $null
            foreach ($propertyName in $result.Properties.PropertyNames) {
                if ($propertyName -like "member;range=*") {
                    $foundRangeProperty = [string]$propertyName
                    break
                }
            }

            if (-not (Is-Blank $foundRangeProperty)) {
                foreach ($dn in $result.Properties[$foundRangeProperty]) {
                    if (-not (Is-Blank $dn)) { $memberDns += [string]$dn }
                }

                if ($foundRangeProperty.EndsWith("-*")) {
                    $done = $true
                }
                else {
                    $rangeStart += $rangeStep
                }
            }
            else {
                # Fallback for small groups or other domain controller behavior.
                try { $searcher.PropertiesToLoad.Clear() } catch { }
                [void]$searcher.PropertiesToLoad.Add("member")
                $result = $searcher.FindOne()
                if ($null -ne $result -and $result.Properties.Contains("member")) {
                    foreach ($dn in $result.Properties["member"]) {
                        if (-not (Is-Blank $dn)) { $memberDns += [string]$dn }
                    }
                }
                $done = $true
            }
        }
    }
    finally {
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }

    return @($memberDns | Sort-Object -Unique)
}

function New-DomainGroupMemberRowFromSearchProperties {
    param($Properties)

    $uac = Get-SearchPropertyValue -Properties $Properties -Name "userAccountControl"
    $objectType = Get-AdObjectTypeFromProperties -Properties $Properties

    return [PSCustomObject]@{
        Name              = [string](Get-SearchPropertyValue -Properties $Properties -Name "name")
        SamAccountName    = [string](Get-SearchPropertyValue -Properties $Properties -Name "sAMAccountName")
        DisplayName       = [string](Get-SearchPropertyValue -Properties $Properties -Name "displayName")
        ObjectType        = [string]$objectType
        Enabled           = if ($objectType -in @("user", "computer")) { Convert-UserAccountControlToEnabled -Value $uac } else { "" }
        UserPrincipalName = [string](Get-SearchPropertyValue -Properties $Properties -Name "userPrincipalName")
        Description       = [string](Get-SearchPropertyValue -Properties $Properties -Name "description")
        DistinguishedName = [string](Get-SearchPropertyValue -Properties $Properties -Name "distinguishedName")
    }
}

function Find-AdObjectByDistinguishedNameNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$DistinguishedName
    )

    if (Is-Blank $DistinguishedName) { return $null }

    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc
    $root = $null
    $searcher = $null
    $result = $null

    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = 1000
        $escapedDn = Escape-LdapFilterValue -Value $DistinguishedName
        $searcher.Filter = "(distinguishedName=$escapedDn)"

        foreach ($p in @("sAMAccountName", "name", "displayName", "userPrincipalName", "distinguishedName", "description", "userAccountControl", "objectClass", "mail")) {
            [void]$searcher.PropertiesToLoad.Add($p)
        }

        $result = $searcher.FindOne()
        if ($null -eq $result) {
            return [PSCustomObject]@{
                Name              = ""
                SamAccountName    = ""
                DisplayName       = ""
                ObjectType        = "nieznany"
                Enabled           = ""
                UserPrincipalName = ""
                Description       = Get-UiText "Value.UnknownObject"
                DistinguishedName = [string]$DistinguishedName
            }
        }

        return (New-DomainGroupMemberRowFromSearchProperties -Properties $result.Properties)
    }
    finally {
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}

function Get-AdDomainGroupMembersNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$GroupIdentity,
        $ProgressWindow = $null
    )

    Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.FindGroup") -Detail "$DomainOrDc\$GroupIdentity" -Marquee $true
    $group = Find-AdGroupBasicNoRsat -DomainOrDc $DomainOrDc -GroupIdentity $GroupIdentity
    if ($null -eq $group -or (Is-Blank $group.DistinguishedName)) {
        throw (Get-UiText "Error.GroupNotFound" @($DomainOrDc, $GroupIdentity))
    }

    Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.GetMemberList") -Detail $group.DistinguishedName -Marquee $true
    $memberDns = @(Get-AdGroupMemberDistinguishedNamesNoRsat -DomainOrDc $DomainOrDc -GroupDistinguishedName $group.DistinguishedName -ProgressWindow $ProgressWindow)

    $rows = @()
    $total = $memberDns.Count

    if ($total -gt 0) {
        Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.GetMemberObjects") -Detail "0 / $total" -Value 0 -Maximum $total
    }

    $index = 0
    foreach ($dn in $memberDns) {
        $index++
        Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.GetMemberObjects") -Detail "$index / $total" -Value $index -Maximum $total
        $row = Find-AdObjectByDistinguishedNameNoRsat -DomainOrDc $DomainOrDc -DistinguishedName $dn
        if ($null -ne $row) { $rows += $row }
    }

    Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.OrganizeResult") -Detail (Get-UiText "Progress.SortGroupMembers") -Marquee $true
    return @($rows | Sort-Object -Property @("ObjectType", "SamAccountName", "Name", "DistinguishedName"))
}

function Get-ManagedAccounts {
    param(
        [string]$DomainOrDc,
        [string]$ManagerLogin
    )

    $manager = Find-AdUserBasic -DomainOrDc $DomainOrDc -Login $ManagerLogin
    if ($null -eq $manager -or (Is-Blank $manager.DistinguishedName)) {
        throw (Get-UiText "Error.ManagerNotFound" @($DomainOrDc, $ManagerLogin))
    }

    $escapedManagerDn = Escape-LdapFilterValue -Value $manager.DistinguishedName
    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc

    $root = $null
    $searcher = $null
    $results = $null

    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.PageSize = 1000
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.Filter = "(&(objectCategory=person)(objectClass=user)(manager=$escapedManagerDn))"

        foreach ($p in @("sAMAccountName", "name", "displayName", "userPrincipalName", "distinguishedName", "description", "userAccountControl", "pwdLastSet")) {
            [void]$searcher.PropertiesToLoad.Add($p)
        }

        $results = $searcher.FindAll()
        $rows = @()

        foreach ($result in $results) {
            $props = $result.Properties
            $uac = Get-SearchPropertyValue -Properties $props -Name "userAccountControl"
            $pwd = Get-SearchPropertyValue -Properties $props -Name "pwdLastSet"

            $rows += [PSCustomObject]@{
                SamAccountName    = [string](Get-SearchPropertyValue -Properties $props -Name "sAMAccountName")
                Name              = [string](Get-SearchPropertyValue -Properties $props -Name "name")
                DisplayName       = [string](Get-SearchPropertyValue -Properties $props -Name "displayName")
                Enabled           = Convert-UserAccountControlToEnabled -Value $uac
                UserPrincipalName = [string](Get-SearchPropertyValue -Properties $props -Name "userPrincipalName")
                Description       = [string](Get-SearchPropertyValue -Properties $props -Name "description")
                PasswordLastSet   = Convert-ADFileTimeToText -Value $pwd
                DistinguishedName = [string](Get-SearchPropertyValue -Properties $props -Name "distinguishedName")
            }
        }

        return @($rows | Sort-Object SamAccountName)
    }
    finally {
        if ($null -ne $results) { $results.Dispose() }
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}


function Get-ManagedGroups {
    param(
        [string]$DomainOrDc,
        [string]$ManagerLogin,
        $ProgressWindow = $null
    )

    Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.FindManager") -Detail "$DomainOrDc\$ManagerLogin" -Marquee $true
    $manager = Find-AdUserBasic -DomainOrDc $DomainOrDc -Login $ManagerLogin
    if ($null -eq $manager -or (Is-Blank $manager.DistinguishedName)) {
        throw (Get-UiText "Error.ManagerNotFound" @($DomainOrDc, $ManagerLogin))
    }

    $escapedManagerDn = Escape-LdapFilterValue -Value $manager.DistinguishedName
    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc

    $root = $null
    $searcher = $null
    $results = $null

    try {
        Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.FindManagedGroups") -Detail $manager.DistinguishedName -Marquee $true
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.PageSize = 1000
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.Filter = "(&(objectClass=group)(managedBy=$escapedManagerDn))"

        foreach ($p in @("sAMAccountName", "name", "displayName", "groupType", "description", "distinguishedName", "managedBy")) {
            [void]$searcher.PropertiesToLoad.Add($p)
        }

        $results = $searcher.FindAll()
        $rows = @()
        $total = $results.Count
        $index = 0

        if ($total -gt 0) {
            Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.OrganizeManagedGroups") -Detail "0 / $total" -Value 0 -Maximum $total
        }

        foreach ($result in $results) {
            $index++
            Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.OrganizeManagedGroups") -Detail "$index / $total" -Value $index -Maximum $total
            $rows += (New-AccountGroupRowFromSearchProperties -Properties $result.Properties -Source "managedBy")
        }

        return @($rows | Sort-Object -Property @("Name", "SamAccountName", "DistinguishedName"))
    }
    finally {
        if ($null -ne $results) { $results.Dispose() }
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}


