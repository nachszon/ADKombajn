# ==================================================
# Events
# ==================================================

$btnExit.Add_Click({
    $form.Close()
})

$btnClearLogMain.Add_Click({
    try {
        if ($null -ne $txtLogMain) { $txtLogMain.Clear() }
    }
    catch { }
    Set-Status (Get-UiText "Status.LogCleared") "Info" $false
})

$btnCopyLogMain.Add_Click({
    try {
        if ($null -eq $txtLogMain -or (Is-Blank $txtLogMain.Text)) {
            Set-Status (Get-UiText "Status.LogEmpty") "Warn"
            return
        }

        [System.Windows.Forms.Clipboard]::SetText($txtLogMain.Text)
        Set-Status (Get-UiText "Status.LogCopied") "Ok"
    }
    catch {
        Set-Status (Get-UiText "Status.LogCopyFailed" @($_.Exception.Message)) "Error"
    }
})

$btnClearValidate.Add_Click({
    $txtValidatePassword.Clear()
    Set-Status (Get-UiText "Status.ValidationPasswordCleared") "Info"
})

$btnClearChange.Add_Click({
    $txtOldPassword.Clear()
    $txtNewPassword.Clear()
    $txtRepeatPassword.Clear()
    Set-Status (Get-UiText "Status.ChangeFieldsCleared") "Info"
})

$chkShowValidatePassword.Add_CheckedChanged({
    $txtValidatePassword.UseSystemPasswordChar = -not $chkShowValidatePassword.Checked
})

$chkShowPasswords.Add_CheckedChanged({
    $show = $chkShowPasswords.Checked
    $txtOldPassword.UseSystemPasswordChar = -not $show
    $txtNewPassword.UseSystemPasswordChar = -not $show
    $txtRepeatPassword.UseSystemPasswordChar = -not $show
})

$btnValidate.Add_Click({
    $domain = $txtDomain.Text.Trim()
    $login = $txtLogin.Text.Trim()
    $password = $txtValidatePassword.Text
    $useLdaps = $chkUseLdaps.Checked
    $port = Get-LdapPortFromUi

    if ((Is-Blank $domain) -or (Is-Blank $login) -or (Is-Blank $password)) {
        Set-Status (Get-UiText "Status.EnterValidationData") "Error"
        return
    }

    try {
        $btnValidate.Enabled = $false
        Set-Status (Get-UiText "Status.ValidatingPassword" @($domain, $login)) "Info"
        $result = Test-AdPasswordNoRsat -DomainOrDc $domain -Login $login -Password $password -UseLdaps $useLdaps -Port $port

        if ($result.Success) {
            Set-Status (Get-UiText "Status.PasswordValid" @($domain, $login)) "Ok"
        }
        else {
            Set-Status (Get-UiText "Status.PasswordInvalid") "Error"
            Show-ErrorBox $result.Message (Get-UiText "Tab.ValidatePassword")
        }
    }
    finally {
        $btnValidate.Enabled = $true
    }
})

$btnChange.Add_Click({
    $domain = $txtDomain.Text.Trim()
    $login = $txtLogin.Text.Trim()
    $oldPassword = $txtOldPassword.Text
    $newPassword = $txtNewPassword.Text
    $repeatPassword = $txtRepeatPassword.Text
    $useLdaps = $chkUseLdaps.Checked
    $port = Get-LdapPortFromUi

    if ((Is-Blank $domain) -or (Is-Blank $login)) {
        Set-Status (Get-UiText "Status.EnterDomainLogin") "Error"
        return
    }
    if ((Is-Blank $oldPassword) -or (Is-Blank $newPassword) -or (Is-Blank $repeatPassword)) {
        Set-Status (Get-UiText "Status.EnterPasswordChangeData") "Error"
        return
    }
    if ($newPassword -ne $repeatPassword) {
        Set-Status (Get-UiText "Status.PasswordsDiffer") "Error"
        return
    }
    if ($oldPassword -eq $newPassword) {
        Set-Status (Get-UiText "Status.PasswordUnchanged") "Error"
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        (Get-UiText "Status.ConfirmPasswordChange" @($domain, $login)),
        (Get-UiText "Status.ConfirmPasswordChangeTitle"),
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        Set-Status (Get-UiText "Status.PasswordChangeCancelled") "Info"
        return
    }

    try {
        $btnChange.Enabled = $false
        Set-Status (Get-UiText "Status.ChangingPassword" @($domain, $login)) "Info"
        $result = Change-AdAccountPasswordNoRsat -DomainOrDc $domain -Login $login -OldPassword $oldPassword -NewPassword $newPassword -UseLdaps $useLdaps -Port $port

        if ($result.Success) {
            Set-Status (Get-UiText "Status.PasswordChanged" @($domain, $login)) "Ok"
            $txtOldPassword.Clear()
            $txtNewPassword.Clear()
            $txtRepeatPassword.Clear()
        }
        else {
            Set-Status (Get-UiText "Status.PasswordChangeError" @($domain, $login)) "Error"
            Show-ErrorBox $result.Message (Get-UiText "Tab.ChangePassword")
        }
    }
    finally {
        $btnChange.Enabled = $true
    }
})


$btnGetAccountProps.Add_Click({
    $domain = $txtDomain.Text.Trim()
    $login = $txtLogin.Text.Trim()

    if ((Is-Blank $domain) -or (Is-Blank $login)) {
        Set-Status (Get-UiText "Status.EnterAccount") "Error"
        return
    }

    try {
        $btnGetAccountProps.Enabled = $false
        Set-Status (Get-UiText "Status.GettingAccountProperties" @($domain, $login)) "Info"
        $script:AccountPropertyRows = @(Get-AdUserAllPropertiesNoRsat -DomainOrDc $domain -Login $login)
        $script:AccountPropertyRowsLoaded = $true
        Refresh-AccountPropertiesGrid | Out-Null
        Set-Status (Get-UiText "Status.AccountPropertiesReceived" @(@($script:AccountPropertyRows).Count)) "Ok"
    }
    catch {
        $script:AccountPropertyRows = @()
        $script:AccountPropertyRowsLoaded = $false
        Set-AccountPropertiesGrid -Rows $script:AccountPropertyRows
        $lblAccountPropsCount.Text = Get-UiText "AccountProperties.CountEmpty"
        $msg = $_.Exception.Message
        Set-Status (Get-UiText "Status.AccountPropertiesError" @($msg)) "Error"
        Show-ErrorBox $msg (Get-UiText "Tab.AccountProperties")
    }
    finally {
        $btnGetAccountProps.Enabled = $true
    }
})

$btnClearAccountProps.Add_Click({
    $script:AccountPropertyRows = @()
    $script:AccountPropertyRowsLoaded = $false
    Set-AccountPropertiesGrid -Rows $script:AccountPropertyRows
    $txtAccountPropsSearch.Clear()
    $lblAccountPropsCount.Text = Get-UiText "AccountProperties.CountEmpty"
    Set-Status (Get-UiText "Status.AccountPropertiesCleared") "Info"
})

$btnExportAccountPropsCsv.Add_Click({ Export-AccountPropertiesWithDialog -Format "CSV" })
$btnExportAccountPropsXlsx.Add_Click({ Export-AccountPropertiesWithDialog -Format "XLSX" })
$btnCopyAccountPropertyValues.Add_Click({ Copy-SelectedAccountPropertyValues })
$txtAccountPropsSearch.Add_TextChanged({ Update-AccountPropertiesSearchView })

$btnGetAccountGroups.Add_Click({
    $domain = $txtDomain.Text.Trim()
    $login = $txtLogin.Text.Trim()

    if ((Is-Blank $domain) -or (Is-Blank $login)) {
        Set-Status (Get-UiText "Status.EnterAccount") "Error"
        return
    }

    $progressWindow = $null

    try {
        $btnGetAccountGroups.Enabled = $false
        Set-Status (Get-UiText "Status.GettingAccountGroups" @($domain, $login)) "Info"
        $progressWindow = Show-BusyProgressWindow `
            -Title (Get-UiText "Tab.AccountGroups") `
            -Message (Get-UiText "Status.GettingAccountGroups" @($domain, $login)) `
            -Detail "$domain\$login"

        $script:AccountGroupRows = @(Get-AdAccountGroupsNoRsat -DomainOrDc $domain -Login $login -ProgressWindow $progressWindow)
        $script:AccountGroupRowsLoaded = $true
        Refresh-AccountGroupsGrid | Out-Null

        if (@($script:AccountGroupRows).Count -eq 0) {
            Set-Status (Get-UiText "Status.NoAccountGroups" @($domain, $login)) "Warn"
        }
        else {
            Set-Status (Get-UiText "Status.AccountGroupsReceived" @(@($script:AccountGroupRows).Count)) "Ok"
        }
    }
    catch {
        $script:AccountGroupRows = @()
        $script:AccountGroupRowsLoaded = $false
        Set-AccountGroupsGrid -Rows $script:AccountGroupRows
        $lblAccountGroupsCount.Text = Get-UiText "Groups.CountEmpty"
        $msg = $_.Exception.Message
        Set-Status (Get-UiText "Status.AccountGroupsError" @($msg)) "Error"
        Close-BusyProgressWindow $progressWindow
        $progressWindow = $null
        Show-ErrorBox $msg (Get-UiText "Tab.AccountGroups")
    }
    finally {
        Close-BusyProgressWindow $progressWindow
        $btnGetAccountGroups.Enabled = $true
    }
})

$btnClearAccountGroups.Add_Click({
    $script:AccountGroupRows = @()
    $script:AccountGroupRowsLoaded = $false
    Set-AccountGroupsGrid -Rows $script:AccountGroupRows
    $txtAccountGroupsSearch.Clear()
    $lblAccountGroupsCount.Text = Get-UiText "Groups.CountEmpty"
    Set-Status (Get-UiText "Status.AccountGroupsCleared") "Info"
})

$btnExportAccountGroupsCsv.Add_Click({ Export-AccountGroupsWithDialog -Format "CSV" })
$btnExportAccountGroupsXlsx.Add_Click({ Export-AccountGroupsWithDialog -Format "XLSX" })
$btnCopyAccountGroupNames.Add_Click({ Copy-SelectedGroupNames -Grid $gridAccountGroups })
$txtAccountGroupsSearch.Add_TextChanged({ Update-AccountGroupsSearchView })



$btnGetGroupMembers.Add_Click({
    $domain = $txtDomain.Text.Trim()
    $groupIdentity = $txtLogin.Text.Trim()

    if (Is-Blank $domain) {
        Set-Status (Get-UiText "Status.EnterDomain") "Error"
        return
    }

    if (Is-Blank $groupIdentity) {
        Set-Status (Get-UiText "Status.EnterGroup") "Error"
        return
    }

    $progressWindow = $null

    try {
        $btnGetGroupMembers.Enabled = $false
        Set-Status (Get-UiText "Status.GettingGroupMembers" @($domain, $groupIdentity)) "Info"
        $progressWindow = Show-BusyProgressWindow `
            -Title (Get-UiText "Tab.GroupMembers") `
            -Message (Get-UiText "Status.GettingGroupMembers" @($domain, $groupIdentity)) `
            -Detail "$domain\$groupIdentity"

        $script:DomainGroupMemberRows = @(Get-AdDomainGroupMembersNoRsat -DomainOrDc $domain -GroupIdentity $groupIdentity -ProgressWindow $progressWindow)
        $script:DomainGroupMemberRowsLoaded = $true
        Refresh-GroupMembersGrid | Out-Null

        if (@($script:DomainGroupMemberRows).Count -eq 0) {
            Set-Status (Get-UiText "Status.NoGroupMembers" @($domain, $groupIdentity)) "Warn"
        }
        else {
            Set-Status (Get-UiText "Status.GroupMembersReceived" @(@($script:DomainGroupMemberRows).Count)) "Ok"
        }
    }
    catch {
        $script:DomainGroupMemberRows = @()
        $script:DomainGroupMemberRowsLoaded = $false
        Set-DomainGroupMembersGrid -Rows $script:DomainGroupMemberRows
        $lblGroupMembersCount.Text = Get-UiText "GroupMembers.CountEmpty"
        $msg = $_.Exception.Message
        Set-Status (Get-UiText "Status.GroupMembersError" @($msg)) "Error"
        Close-BusyProgressWindow $progressWindow
        $progressWindow = $null
        Show-ErrorBox $msg (Get-UiText "Tab.GroupMembers")
    }
    finally {
        Close-BusyProgressWindow $progressWindow
        $btnGetGroupMembers.Enabled = $true
    }
})

$btnClearGroupMembers.Add_Click({
    $script:DomainGroupMemberRows = @()
    $script:DomainGroupMemberRowsLoaded = $false
    Set-DomainGroupMembersGrid -Rows $script:DomainGroupMemberRows
    $txtGroupMembersSearch.Clear()
    $lblGroupMembersCount.Text = Get-UiText "GroupMembers.CountEmpty"
    Set-Status (Get-UiText "Status.GroupMembersCleared") "Info"
})

$btnExportGroupMembersCsv.Add_Click({ Export-GroupMembersWithDialog -Format "CSV" })
$btnExportGroupMembersXlsx.Add_Click({ Export-GroupMembersWithDialog -Format "XLSX" })
$btnCopyGroupMemberNames.Add_Click({ Copy-SelectedGroupNames -Grid $gridGroupMembers })
$txtGroupMembersSearch.Add_TextChanged({ Update-GroupMembersSearchView })



$btnGetManagedGroups.Add_Click({
    $domain = $txtDomain.Text.Trim()
    $login = $txtLogin.Text.Trim()

    if ((Is-Blank $domain) -or (Is-Blank $login)) {
        Set-Status (Get-UiText "Status.EnterManager") "Error"
        return
    }

    $progressWindow = $null

    try {
        $btnGetManagedGroups.Enabled = $false
        Set-Status (Get-UiText "Status.GettingManagedGroups" @($domain, $login)) "Info"
        $progressWindow = Show-BusyProgressWindow `
            -Title (Get-UiText "Tab.ManagedGroups") `
            -Message (Get-UiText "Status.GettingManagedGroups" @($domain, $login)) `
            -Detail "$domain\$login"

        $script:ManagedGroupRows = @(Get-ManagedGroups -DomainOrDc $domain -ManagerLogin $login -ProgressWindow $progressWindow)
        $script:ManagedGroupRowsLoaded = $true
        Refresh-ManagedGroupsGrid | Out-Null

        if (@($script:ManagedGroupRows).Count -eq 0) {
            Set-Status (Get-UiText "Status.NoManagedGroups" @($domain, $login)) "Warn"
        }
        else {
            Set-Status (Get-UiText "Status.ManagedGroupsReceived" @(@($script:ManagedGroupRows).Count)) "Ok"
        }
    }
    catch {
        $script:ManagedGroupRows = @()
        $script:ManagedGroupRowsLoaded = $false
        Set-ManagedGroupsGrid -Rows $script:ManagedGroupRows
        $lblManagedGroupsCount.Text = Get-UiText "Groups.CountEmpty"
        $msg = $_.Exception.Message
        Set-Status (Get-UiText "Status.ManagedGroupsError" @($msg)) "Error"
        Close-BusyProgressWindow $progressWindow
        $progressWindow = $null
        Show-ErrorBox $msg (Get-UiText "Tab.ManagedGroups")
    }
    finally {
        Close-BusyProgressWindow $progressWindow
        $btnGetManagedGroups.Enabled = $true
    }
})

$btnClearManagedGroups.Add_Click({
    $script:ManagedGroupRows = @()
    $script:ManagedGroupRowsLoaded = $false
    Set-ManagedGroupsGrid -Rows $script:ManagedGroupRows
    $txtManagedGroupsSearch.Clear()
    $lblManagedGroupsCount.Text = Get-UiText "Groups.CountEmpty"
    Set-Status (Get-UiText "Status.ManagedGroupsCleared") "Info"
})

$btnExportManagedGroupsCsv.Add_Click({ Export-ManagedGroupsWithDialog -Format "CSV" })
$btnExportManagedGroupsXlsx.Add_Click({ Export-ManagedGroupsWithDialog -Format "XLSX" })
$btnCopyManagedGroupNames.Add_Click({ Copy-SelectedGroupNames -Grid $gridManagedGroups })
$txtManagedGroupsSearch.Add_TextChanged({ Update-ManagedGroupsSearchView })


$btnManaged.Add_Click({
    $domain = $txtDomain.Text.Trim()
    $login = $txtLogin.Text.Trim()

    if ((Is-Blank $domain) -or (Is-Blank $login)) {
        Set-Status (Get-UiText "Status.EnterManager") "Error"
        return
    }

    try {
        $btnManaged.Enabled = $false
        Set-Status (Get-UiText "Status.FindingManagerAccounts" @($domain, $login)) "Info"
        $script:ManagedRowsAll = @(Get-ManagedAccounts -DomainOrDc $domain -ManagerLogin $login)
        $script:ManagedRowsLoaded = $true

        $visibleCount = Refresh-ManagedAccountsGrid
        $totalCount = @($script:ManagedRowsAll).Count
        $filterText = Get-ManagedAccountsFilterText

        if ($totalCount -eq 0) {
            Set-Status (Get-UiText "Status.NoManagerAccounts" @($domain, $login)) "Warn"
        }
        else {
            Set-Status (Get-UiText "Status.ManagerAccountsReceived" @($totalCount, $visibleCount, $filterText)) "Ok"
        }
    }
    catch {
        $script:ManagedRowsAll = @()
        $script:ManagedRowsLoaded = $false
        $gridManaged.Rows.Clear()
        $lblManagedCount.Text = Get-UiText "ManagerAccounts.CountEmpty"
        $msg = $_.Exception.Message
        Set-Status (Get-UiText "Status.ManagerAccountsError" @($msg)) "Error"
        Show-ErrorBox $msg (Get-UiText "Tab.ManagerAccounts")
    }
    finally {
        $btnManaged.Enabled = $true
    }
})

$btnClearManaged.Add_Click({
    $script:ManagedRowsAll = @()
    $script:ManagedRowsLoaded = $false
    $gridManaged.Rows.Clear()
    $gridManaged.ClearSelection()
    $txtManagedSearch.Clear()
    $rdoManagedAll.Checked = $true
    $lblManagedCount.Text = Get-UiText "ManagerAccounts.CountEmpty"
    Set-Status (Get-UiText "Status.ManagerAccountsCleared") "Info"
})

$btnExportCsv.Add_Click({ Export-ManagedAccountsWithDialog -Format "CSV" })
$btnExportXlsx.Add_Click({ Export-ManagedAccountsWithDialog -Format "XLSX" })
$btnCopyLogins.Add_Click({ Copy-SelectedLoginsToClipboard })

$rdoManagedAll.Add_CheckedChanged({ if ($rdoManagedAll.Checked) { Update-ManagedAccountsFilterView } })
$rdoManagedActive.Add_CheckedChanged({ if ($rdoManagedActive.Checked) { Update-ManagedAccountsFilterView } })
$rdoManagedInactive.Add_CheckedChanged({ if ($rdoManagedInactive.Checked) { Update-ManagedAccountsFilterView } })
$txtManagedSearch.Add_TextChanged({ Update-ManagedAccountsFilterView })

$form.Add_KeyDown({
    param($sender, $e)
    if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::L) {
        try { if ($null -ne $txtLogMain) { $txtLogMain.Clear() } } catch { }
        $e.Handled = $true
    }
})

$form.Add_Shown({
    Set-Status (Get-UiText "Status.Ready") "Info"
    try { $txtLogin.Focus() } catch { }
})

$form.Add_FormClosed({
    try {
        foreach ($ctrl in @($form, $header, $contextPanel, $tabs, $txtLogMain, $gridManaged, $gridAccountProps, $gridAccountGroups)) {
            if ($null -ne $ctrl) { $ctrl.Dispose() }
        }
        if ($null -ne $script:BrandImage) {
            $script:BrandImage.Dispose()
            $script:BrandImage = $null
        }
        if ($null -ne $script:BrandImageStream) {
            $script:BrandImageStream.Dispose()
            $script:BrandImageStream = $null
        }
    }
    catch { }
})

[void]$form.ShowDialog()
