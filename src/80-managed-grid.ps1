# ==================================================
# Manager account table data
# ==================================================

function Get-ManagedAccountsFilterMode {
    if ($rdoManagedActive.Checked) { return "Active" }
    if ($rdoManagedInactive.Checked) { return "Inactive" }
    return "All"
}

function Get-ManagedAccountsFilterText {
    $mode = Get-ManagedAccountsFilterMode
    switch ($mode) {
        "Active"   { return (Get-UiText "Filter.Active") }
        "Inactive" { return (Get-UiText "Filter.Inactive") }
        default    { return (Get-UiText "Filter.All") }
    }
}

function Filter-ManagedAccountsRows {
    param([object[]]$Rows)

    if ($null -eq $Rows) { return @() }
    $mode = Get-ManagedAccountsFilterMode
    $query = ""
    try { $query = $txtManagedSearch.Text.Trim() } catch { }

    $filtered = @($Rows)
    switch ($mode) {
        "Active"   { $filtered = @($filtered | Where-Object { $_.Enabled -eq "True" }) }
        "Inactive" { $filtered = @($filtered | Where-Object { $_.Enabled -eq "False" }) }
    }

    if (-not (Is-Blank $query)) {
        $q = $query.ToLowerInvariant()
        $filtered = @($filtered | Where-Object {
            ([string]$_.SamAccountName).ToLowerInvariant().Contains($q) -or
            ([string]$_.DisplayName).ToLowerInvariant().Contains($q) -or
            ([string]$_.Name).ToLowerInvariant().Contains($q) -or
            ([string]$_.UserPrincipalName).ToLowerInvariant().Contains($q) -or
            ([string]$_.Description).ToLowerInvariant().Contains($q)
        })
    }

    return @($filtered)
}

function New-TextGridColumn {
    param([string]$Name, [string]$HeaderText, [int]$Width, [bool]$Visible = $true)

    $column = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $column.Name = $Name
    $column.HeaderText = $HeaderText
    $column.Width = $Width
    $column.ReadOnly = $true
    $column.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
    $column.Visible = $Visible
    return $column
}

function Set-ManagedAccountsGrid {
    param([object[]]$Rows)

    $gridManaged.SuspendLayout()
    try {
        $gridManaged.Rows.Clear()
        if ($null -ne $Rows) {
            foreach ($row in $Rows) {
                if ($null -eq $row) { continue }
                [void]$gridManaged.Rows.Add(
                    [string]$row.SamAccountName,
                    [string]$row.Name,
                    [string]$row.DisplayName,
                    [string]$row.Enabled,
                    [string]$row.UserPrincipalName,
                    [string]$row.Description,
                    [string]$row.PasswordLastSet,
                    [string]$row.DistinguishedName
                )
            }
        }
        $gridManaged.ClearSelection()
    }
    finally {
        $gridManaged.ResumeLayout()
    }

    $gridManaged.Refresh()
}

function Refresh-ManagedAccountsGrid {
    $filteredRows = @(Filter-ManagedAccountsRows -Rows $script:ManagedRowsAll)
    $totalCount = @($script:ManagedRowsAll).Count
    Set-ManagedAccountsGrid -Rows $filteredRows

    if ((Get-ManagedAccountsFilterMode) -eq "All" -and (Is-Blank $txtManagedSearch.Text)) {
        $lblManagedCount.Text = Get-UiText "ManagerAccounts.Count" @($filteredRows.Count)
    }
    else {
        $lblManagedCount.Text = Get-UiText "ManagerAccounts.CountFiltered" @($filteredRows.Count, $totalCount)
    }
    return $filteredRows.Count
}

function Update-ManagedAccountsFilterView {
    if (-not $script:ManagedRowsLoaded) { return }
    $visibleCount = Refresh-ManagedAccountsGrid
    $totalCount = @($script:ManagedRowsAll).Count
    Set-Status (Get-UiText "Status.Filter" @((Get-ManagedAccountsFilterText), $txtManagedSearch.Text, $visibleCount, $totalCount)) "Info"
}

function Get-CurrentVisibleManagedRows {
    if (-not $script:ManagedRowsLoaded) { return @() }
    return @(Filter-ManagedAccountsRows -Rows $script:ManagedRowsAll)
}

function Export-ManagedAccountsWithDialog {
    param([ValidateSet("CSV", "XLSX")][string]$Format)

    if (-not $script:ManagedRowsLoaded -or (@($script:ManagedRowsAll).Count -eq 0)) {
        Show-InfoBox (Get-UiText "Status.GetManagerAccountsFirst") (Get-UiText "Dialog.NoData")
        return
    }

    $rowsToExport = @(Get-CurrentVisibleManagedRows)
    if ($rowsToExport.Count -eq 0) {
        Show-InfoBox (Get-UiText "Status.FilterHasNoAccounts") (Get-UiText "Dialog.NoData")
        return
    }

    $domainPart = Get-SafeFileNamePart -Text $txtDomain.Text
    $loginPart = Get-SafeFileNamePart -Text $txtLogin.Text
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $filterPart = Get-SafeFileNamePart -Text (Get-ManagedAccountsFilterText)
    $extension = $Format.ToLowerInvariant()
    $fileNameBase = Get-UiText "Export.FileNameBase"
    $defaultName = "${fileNameBase}_${domainPart}_${loginPart}_${filterPart}_${stamp}.${extension}"

    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = Get-UiText "Export.SaveTitle"
    $dialog.FileName = $defaultName
    $dialog.OverwritePrompt = $true

    if ($Format -eq "CSV") {
        $dialog.Filter = Get-UiText "Export.CsvFilter"
        $dialog.DefaultExt = "csv"
    }
    else {
        $dialog.Filter = Get-UiText "Export.XlsxFilter"
        $dialog.DefaultExt = "xlsx"
    }

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Set-Status (Get-UiText "Status.ExportCancelled") "Info"
        return
    }

    try {
        Set-Status (Get-UiText "Status.Exporting" @($rowsToExport.Count, $Format)) "Info"
        if ($Format -eq "CSV") { Export-ManagedAccountsToCsv -Rows $rowsToExport -Path $dialog.FileName }
        else { Export-ManagedAccountsToXlsx -Rows $rowsToExport -Path $dialog.FileName }
        Set-Status (Get-UiText "Status.ExportReady" @($dialog.FileName)) "Ok"
        Show-InfoBox (Get-UiText "Status.ExportCompleted" @($dialog.FileName)) (Get-UiText "Status.ExportCompletedTitle")
    }
    catch {
        $msg = $_.Exception.Message
        Set-Status (Get-UiText "Status.ExportError" @($msg)) "Error"
        Show-ErrorBox (Get-UiText "Status.ExportFailed" @($msg)) (Get-UiText "Status.ExportErrorTitle")
    }
}

function Export-VisibleRowsWithDialog {
    param(
        [ValidateSet("CSV", "XLSX")][string]$Format,
        [object[]]$ExportRows,
        [string]$FileNameBase,
        [string]$SheetName,
        [string]$SaveTitle,
        [int[]]$Widths
    )

    $domainPart = Get-SafeFileNamePart -Text $txtDomain.Text
    $loginPart = Get-SafeFileNamePart -Text $txtLogin.Text
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $extension = $Format.ToLowerInvariant()
    $defaultName = "${FileNameBase}_${domainPart}_${loginPart}_${stamp}.${extension}"

    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = $SaveTitle
    $dialog.FileName = $defaultName
    $dialog.OverwritePrompt = $true

    if ($Format -eq "CSV") {
        $dialog.Filter = Get-UiText "Export.CsvFilter"
        $dialog.DefaultExt = "csv"
    }
    else {
        $dialog.Filter = Get-UiText "Export.XlsxFilter"
        $dialog.DefaultExt = "xlsx"
    }

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Set-Status (Get-UiText "Status.ExportCancelled") "Info"
        return
    }

    try {
        Set-Status (Get-UiText "Status.ExportingRows" @(@($ExportRows).Count, $Format)) "Info"
        if ($Format -eq "CSV") {
            Export-TabularRowsToCsv -Rows $ExportRows -Path $dialog.FileName
        }
        else {
            Export-TabularRowsToXlsx -Rows $ExportRows -Path $dialog.FileName -SheetName $SheetName -Widths $Widths
        }
        Set-Status (Get-UiText "Status.ExportReady" @($dialog.FileName)) "Ok"
        Show-InfoBox (Get-UiText "Status.ExportCompleted" @($dialog.FileName)) (Get-UiText "Status.ExportCompletedTitle")
    }
    catch {
        $msg = $_.Exception.Message
        Set-Status (Get-UiText "Status.ExportError" @($msg)) "Error"
        Show-ErrorBox (Get-UiText "Status.ExportFailed" @($msg)) (Get-UiText "Status.ExportErrorTitle")
    }
}

function Copy-SelectedLoginsToClipboard {
    try {
        if ($gridManaged.SelectedRows.Count -eq 0) {
            Show-InfoBox (Get-UiText "Status.SelectRow") (Get-UiText "Dialog.NoSelection")
            return
        }

        $logins = @()
        foreach ($row in $gridManaged.SelectedRows) {
            if ($null -ne $row.Cells["SamAccountName"].Value) { $logins += [string]$row.Cells["SamAccountName"].Value }
        }
        $text = ($logins | Sort-Object) -join [Environment]::NewLine
        if (-not (Is-Blank $text)) {
            [System.Windows.Forms.Clipboard]::SetText($text)
            Set-Status (Get-UiText "Status.LoginsCopied" @($logins.Count)) "Ok"
        }
    }
    catch {
        Set-Status (Get-UiText "Status.ClipboardFailed" @($_.Exception.Message)) "Error"
    }
}

