# ==================================================
# GUI
# ==================================================

if (-not (Select-UiLanguage)) { return }
Show-WinSplash -Milliseconds 3000 -Title "ADKombajn" -Subtitle (Get-UiText "Splash.Subtitle") -Version $script:AppVersion -Author (Get-UiText "Splash.Author" @($script:AppAuthor))

$form = New-Object System.Windows.Forms.Form
$script:MainForm = $form
$form.Text = Get-UiText "App.WindowTitle" @($script:AppName, $script:AppVersion)
$form.StartPosition = "CenterScreen"
$form.Size = New-Size 1240 780
$form.MinimumSize = New-Size 1120 700
$form.BackColor = $script:Theme.Back
$form.Font = New-UiFont 9
$form.KeyPreview = $true
Set-DoubleBuffered $form
Apply-AppWindowIcon $form

# Global GUI exception handler to avoid displaying the raw .NET error dialog.
try {
    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        $msg = Get-UiText "Error.GuiUnhandled" @($e.Exception.Message)
        Set-Status $msg "Error"
        Show-ErrorBox $msg (Get-UiText "Error.AppTitle")
    })
}
catch { }

$header = New-Object System.Windows.Forms.Panel
$header.Dock = [System.Windows.Forms.DockStyle]::Top
$header.Height = 94
$header.BackColor = [System.Drawing.Color]::FromArgb(18, 66, 55)
Set-DoubleBuffered $header
$header.Add_Paint({
    param($sender, $e)

    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $rect = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(18, 66, 55), [System.Drawing.Color]::FromArgb(38, 145, 94), 0.0)
    $g.FillRectangle($bg, $rect)
    $bg.Dispose()

    if ($null -ne $script:BrandImage) {
        $g.DrawImage($script:BrandImage, (New-Object System.Drawing.Rectangle(22, 9, 124, 76)))
    }

    $titleFont = New-Object System.Drawing.Font("Segoe UI Semibold", 22, [System.Drawing.FontStyle]::Regular)
    $subFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
    $authorFont = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Regular)
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $soft = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(222, 245, 232))
    $muted = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(196, 231, 212))
    $g.DrawString("ADKombajn", $titleFont, $white, 160, 15)
    $g.DrawString((Get-UiText "Header.Subtitle"), $subFont, $soft, 163, 58)
    $authorText = Get-UiText "Header.Author" @($script:AppAuthor)
    $size = $g.MeasureString($authorText, $authorFont)
    $g.DrawString($authorText, $authorFont, $muted, ($sender.Width - $size.Width - 22), 64)
    $titleFont.Dispose(); $subFont.Dispose(); $authorFont.Dispose(); $white.Dispose(); $soft.Dispose(); $muted.Dispose()
})

$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Name = "btnExit"
$btnExit.Text = "$([char]0x23FB)  $(Get-UiText "Common.Exit")"
$btnExit.Size = New-Size 118 34
$btnExit.Location = New-Point 0 16
$btnExit.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnExit.Font = New-UiFont 9.5 ([System.Drawing.FontStyle]::Bold)
$btnExit.ForeColor = [System.Drawing.Color]::White
$btnExit.BackColor = [System.Drawing.Color]::FromArgb(21, 91, 64)
$btnExit.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnExit.FlatAppearance.BorderSize = 1
$btnExit.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(174, 229, 199)
$btnExit.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(35, 125, 84)
$btnExit.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(12, 68, 48)
$btnExit.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnExit.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$btnExit.UseVisualStyleBackColor = $false
$btnExit.TabStop = $false
$btnExit.AccessibleName = Get-UiText "Common.Exit"

$positionExitButton = {
    $x = [Math]::Max(0, $header.ClientSize.Width - $btnExit.Width - 22)
    $btnExit.Location = New-Point $x 16
    # The header is custom-painted, so resize must repaint its entire surface.
    $header.Invalidate($true)
}
$header.Add_Resize($positionExitButton)
[void]$header.Controls.Add($btnExit)
& $positionExitButton

$contextPanel = New-Object System.Windows.Forms.Panel
$contextPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$contextPanel.Height = 92
$contextPanel.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 8)
$contextPanel.BackColor = $script:Theme.Back

$grpContext = New-CardGroup (Get-UiText "Context.Title") 14 8 1072 74
$grpContext.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblDomain = New-Label (Get-UiText "Context.Domain") 18 31 90 22 9 ([System.Drawing.FontStyle]::Regular)
$txtDomain = New-TextBoxEx 112 28 245 $false
if (-not (Is-Blank $env:USERDNSDOMAIN)) { $txtDomain.Text = $env:USERDNSDOMAIN } else { $txtDomain.Text = $env:USERDOMAIN }

$lblLogin = New-Label (Get-UiText "Context.AccountLogin") 382 31 90 22 9 ([System.Drawing.FontStyle]::Regular)
$txtLogin = New-TextBoxEx 470 28 220 $false

$chkUseLdaps = New-Object System.Windows.Forms.CheckBox
$chkUseLdaps.Text = "LDAPS 636"
$chkUseLdaps.Location = New-Point 720 30
$chkUseLdaps.AutoSize = $true
$chkUseLdaps.Font = New-UiFont 9
$chkUseLdaps.ForeColor = $script:Theme.Text

$lblMode = New-Label (Get-UiText "Context.Mode") 808 31 245 22 8.5 ([System.Drawing.FontStyle]::Italic)
$lblMode.ForeColor = $script:Theme.Muted
$lblMode.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

$grpContext.Controls.AddRange(@($lblDomain, $txtDomain, $lblLogin, $txtLogin, $chkUseLdaps, $lblMode))
$contextPanel.Controls.Add($grpContext)

try {
    $tabs = New-Object KombajnColorTabControlV21
}
catch {
    $tabs = New-Object System.Windows.Forms.TabControl
}
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabs.Font = New-UiFont 9.5 ([System.Drawing.FontStyle]::Regular)
$tabs.Padding = New-Point 14 5
try {
    $tabs.ItemSize = New-Size 136 34
    $tabs.SizeMode = [System.Windows.Forms.TabSizeMode]::Normal
}
catch { }

$tabValidate = New-Object System.Windows.Forms.TabPage
$tabValidate.Text = Get-UiText "Tab.ValidatePassword"
$tabValidate.BackColor = $script:Theme.Back

$tabChange = New-Object System.Windows.Forms.TabPage
$tabChange.Text = Get-UiText "Tab.ChangePassword"
$tabChange.BackColor = $script:Theme.Back

$tabManager = New-Object System.Windows.Forms.TabPage
$tabManager.Text = Get-UiText "Tab.ManagerAccounts"
$tabManager.BackColor = $script:Theme.Back

$tabAccountProps = New-Object System.Windows.Forms.TabPage
$tabAccountProps.Text = Get-UiText "Tab.AccountProperties"
$tabAccountProps.BackColor = $script:Theme.Back

$tabAccountGroups = New-Object System.Windows.Forms.TabPage
$tabAccountGroups.Text = Get-UiText "Tab.AccountGroups"
$tabAccountGroups.BackColor = $script:Theme.Back

$tabGroupMembers = New-Object System.Windows.Forms.TabPage
$tabGroupMembers.Text = Get-UiText "Tab.GroupMembers"
$tabGroupMembers.BackColor = $script:Theme.Back

$tabManagedGroups = New-Object System.Windows.Forms.TabPage
$tabManagedGroups.Text = Get-UiText "Tab.ManagedGroups"
$tabManagedGroups.BackColor = $script:Theme.Back

$tabLog = New-Object System.Windows.Forms.TabPage
$tabLog.Text = Get-UiText "Tab.Log"
$tabLog.BackColor = $script:Theme.Back

[void]$tabs.TabPages.Add($tabValidate)
[void]$tabs.TabPages.Add($tabChange)
[void]$tabs.TabPages.Add($tabAccountProps)
[void]$tabs.TabPages.Add($tabAccountGroups)
[void]$tabs.TabPages.Add($tabGroupMembers)
[void]$tabs.TabPages.Add($tabManagedGroups)
[void]$tabs.TabPages.Add($tabManager)
[void]$tabs.TabPages.Add($tabLog)

$script:PreservedAccountLogin = ""
$script:PreservedGroupName = ""
$script:IsGroupContextActive = $false

$tabs.Add_SelectedIndexChanged({
    $isGroupMembersTab = ($tabs.SelectedTab -eq $tabGroupMembers)

    if ($isGroupMembersTab -and -not $script:IsGroupContextActive) {
        $script:PreservedAccountLogin = $txtLogin.Text
        $txtLogin.Text = $script:PreservedGroupName
        $lblLogin.Text = Get-UiText "Context.GroupName"
        $script:IsGroupContextActive = $true
        return
    }

    if (-not $isGroupMembersTab -and $script:IsGroupContextActive) {
        $script:PreservedGroupName = $txtLogin.Text
        $txtLogin.Text = $script:PreservedAccountLogin
        $lblLogin.Text = Get-UiText "Context.AccountLogin"
        $script:IsGroupContextActive = $false
    }
})

# ---- Password validation tab ----
$grpValidate = New-CardGroup (Get-UiText "Validation.Title") 18 18 1042 145
$grpValidate.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblValidatePassword = New-Label (Get-UiText "Validation.Password") 18 40 100 22
$txtValidatePassword = New-TextBoxEx 130 37 310 $true

$chkShowValidatePassword = New-Object System.Windows.Forms.CheckBox
$chkShowValidatePassword.Text = Get-UiText "Validation.ShowPassword"
$chkShowValidatePassword.Location = New-Point 460 40
$chkShowValidatePassword.AutoSize = $true
$chkShowValidatePassword.Font = New-UiFont 9
$chkShowValidatePassword.ForeColor = $script:Theme.Text

$btnValidate = New-FlatButton (Get-UiText "Validation.Check") 130 82 118 34
$btnClearValidate = New-SoftButton (Get-UiText "Common.Clear") 258 82 118 34
$lblValidateHint = New-Label (Get-UiText "Validation.Hint") 460 85 535 22 8.5 ([System.Drawing.FontStyle]::Italic)
$lblValidateHint.ForeColor = $script:Theme.Muted
$lblValidateHint.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$grpValidate.Controls.AddRange(@($lblValidatePassword, $txtValidatePassword, $chkShowValidatePassword, $btnValidate, $btnClearValidate, $lblValidateHint))

$grpLogValidate = New-CardGroup (Get-UiText "Common.Log") 18 185 1042 415
$grpLogValidate.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom

$txtLogValidate = New-Object System.Windows.Forms.TextBox
$txtLogValidate.Location = New-Point 16 26
$txtLogValidate.Size = New-Size 1010 360
$txtLogValidate.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$txtLogValidate.Multiline = $true
$txtLogValidate.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtLogValidate.ReadOnly = $true
$txtLogValidate.BackColor = [System.Drawing.Color]::FromArgb(250, 252, 255)
$txtLogValidate.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLogValidate.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$btnClearLogValidate = New-SoftButton (Get-UiText "Common.ClearLog") 906 386 120 28
$btnClearLogValidate.Anchor = [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$grpLogValidate.Controls.AddRange(@($txtLogValidate, $btnClearLogValidate))

# ---- Password change tab ----
$grpChange = New-CardGroup (Get-UiText "Change.Title") 18 18 1042 210
$grpChange.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblOldPassword = New-Label (Get-UiText "Change.OldPassword") 18 38 105 22
$txtOldPassword = New-TextBoxEx 135 35 310 $true
$lblNewPassword = New-Label (Get-UiText "Change.NewPassword") 18 75 105 22
$txtNewPassword = New-TextBoxEx 135 72 310 $true
$lblRepeatPassword = New-Label (Get-UiText "Change.RepeatPassword") 18 112 105 22
$txtRepeatPassword = New-TextBoxEx 135 109 310 $true

$chkShowPasswords = New-Object System.Windows.Forms.CheckBox
$chkShowPasswords.Text = Get-UiText "Change.ShowPasswords"
$chkShowPasswords.Location = New-Point 470 37
$chkShowPasswords.AutoSize = $true
$chkShowPasswords.Font = New-UiFont 9
$chkShowPasswords.ForeColor = $script:Theme.Text

$btnChange = New-FlatButton (Get-UiText "Change.Button") 135 153 140 36 $script:Theme.Accent ([System.Drawing.Color]::White)
$btnClearChange = New-SoftButton (Get-UiText "Common.Clear") 285 153 110 36
$lblChangeHint = New-Label (Get-UiText "Change.Hint") 470 75 535 22 8.5 ([System.Drawing.FontStyle]::Italic)
$lblChangeHint.ForeColor = $script:Theme.Muted
$lblChangeHint.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$grpChange.Controls.AddRange(@($lblOldPassword, $txtOldPassword, $lblNewPassword, $txtNewPassword, $lblRepeatPassword, $txtRepeatPassword, $chkShowPasswords, $btnChange, $btnClearChange, $lblChangeHint))

$grpLogChange = New-CardGroup (Get-UiText "Common.Log") 18 245 1042 355
$grpLogChange.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom

$txtLogChange = New-Object System.Windows.Forms.TextBox
$txtLogChange.Location = New-Point 16 26
$txtLogChange.Size = New-Size 1010 300
$txtLogChange.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$txtLogChange.Multiline = $true
$txtLogChange.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtLogChange.ReadOnly = $true
$txtLogChange.BackColor = [System.Drawing.Color]::FromArgb(250, 252, 255)
$txtLogChange.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLogChange.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$btnClearLogChange = New-SoftButton (Get-UiText "Common.ClearLog") 906 326 120 28
$btnClearLogChange.Anchor = [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$grpLogChange.Controls.AddRange(@($txtLogChange, $btnClearLogChange))

# ---- Log tab ----
$grpLogGlobal = New-CardGroup (Get-UiText "Log.Events") 18 18 1042 582
$grpLogGlobal.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom

$txtLogMain = New-Object System.Windows.Forms.TextBox
$txtLogMain.Location = New-Point 16 26
$txtLogMain.Size = New-Size 1010 505
$txtLogMain.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$txtLogMain.Multiline = $true
$txtLogMain.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtLogMain.ReadOnly = $true
$txtLogMain.BackColor = [System.Drawing.Color]::FromArgb(250, 252, 255)
$txtLogMain.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLogMain.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

$btnCopyLogMain = New-SoftButton (Get-UiText "Common.CopyLog") 770 540 120 28
$btnCopyLogMain.Anchor = [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom

$btnClearLogMain = New-SoftButton (Get-UiText "Common.ClearLog") 906 540 120 28
$btnClearLogMain.Anchor = [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom

$grpLogGlobal.Controls.AddRange(@($txtLogMain, $btnCopyLogMain, $btnClearLogMain))

$script:txtLog = $txtLogMain
$script:txtLogs = @($txtLogMain)

$tabValidate.Controls.AddRange(@($grpValidate))
$tabChange.Controls.AddRange(@($grpChange))
$tabLog.Controls.Add($grpLogGlobal)

# ---- Account properties tab ----
$accountPropsTop = New-Object System.Windows.Forms.Panel
$accountPropsTop.Dock = [System.Windows.Forms.DockStyle]::Top
$accountPropsTop.Height = 92
$accountPropsTop.BackColor = $script:Theme.Back

$btnGetAccountProps = New-FlatButton (Get-UiText "AccountProperties.Get") 18 16 160 34
$btnClearAccountProps = New-SoftButton (Get-UiText "Common.Clear") 188 16 95 34
$btnExportAccountPropsCsv = New-SoftButton (Get-UiText "Common.ExportCsv") 293 16 112 34
$btnExportAccountPropsXlsx = New-SoftButton (Get-UiText "Common.ExportXlsx") 415 16 118 34
$btnCopyAccountPropertyValues = New-SoftButton (Get-UiText "AccountProperties.CopyValues") 543 16 130 34

$lblAccountPropsSearch = New-Label (Get-UiText "Common.Search") 18 60 55 22
$txtAccountPropsSearch = New-TextBoxEx 73 57 250 $false

$lblAccountPropsInfo = New-Label (Get-UiText "Common.ExportVisibleInfo") 340 58 490 22 8.5 ([System.Drawing.FontStyle]::Italic)
$lblAccountPropsInfo.ForeColor = $script:Theme.Muted

$lblAccountPropsCount = New-Label (Get-UiText "AccountProperties.CountEmpty") 850 22 230 24 10 ([System.Drawing.FontStyle]::Bold)
$lblAccountPropsCount.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblAccountPropsCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight

$accountPropsTop.Controls.AddRange(@($btnGetAccountProps, $btnClearAccountProps, $btnExportAccountPropsCsv, $btnExportAccountPropsXlsx, $btnCopyAccountPropertyValues, $lblAccountPropsSearch, $txtAccountPropsSearch, $lblAccountPropsInfo, $lblAccountPropsCount))

$gridAccountProps = New-Object System.Windows.Forms.DataGridView
$gridAccountProps.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridAccountProps.AutoGenerateColumns = $false
$gridAccountProps.ColumnHeadersVisible = $true
$gridAccountProps.BackgroundColor = [System.Drawing.Color]::White
$gridAccountProps.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$gridAccountProps.ReadOnly = $true
$gridAccountProps.AllowUserToAddRows = $false
$gridAccountProps.AllowUserToDeleteRows = $false
$gridAccountProps.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$gridAccountProps.MultiSelect = $true
$gridAccountProps.RowHeadersVisible = $false
$gridAccountProps.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$gridAccountProps.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$gridAccountProps.Font = New-UiFont 9
$gridAccountProps.ColumnHeadersDefaultCellStyle.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Bold)
$gridAccountProps.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(0, 100, 96)
$gridAccountProps.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$gridAccountProps.ColumnHeadersDefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0, 100, 96)
$gridAccountProps.EnableHeadersVisualStyles = $false
$gridAccountProps.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(245, 249, 253)
$gridAccountProps.GridColor = $script:Theme.Border
$gridAccountProps.RowTemplate.Height = 25
$gridAccountProps.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::False
Set-DoubleBuffered $gridAccountProps

[void]$gridAccountProps.Columns.Add((New-TextGridColumn "Attribute" (Get-UiText "Column.Attribute") 230 $true))
[void]$gridAccountProps.Columns.Add((New-TextGridColumn "Value" (Get-UiText "Column.Value") 720 $true))
[void]$gridAccountProps.Columns.Add((New-TextGridColumn "Count" (Get-UiText "Column.Count") 60 $true))
$gridAccountProps.Columns[0].FillWeight = 24
$gridAccountProps.Columns[1].FillWeight = 70
$gridAccountProps.Columns[2].FillWeight = 6

$tabAccountProps.Controls.Add($gridAccountProps)
$tabAccountProps.Controls.Add($accountPropsTop)

# ---- Account groups tab ----
$accountGroupsTop = New-Object System.Windows.Forms.Panel
$accountGroupsTop.Dock = [System.Windows.Forms.DockStyle]::Top
$accountGroupsTop.Height = 92
$accountGroupsTop.BackColor = $script:Theme.Back

$btnGetAccountGroups = New-FlatButton (Get-UiText "AccountGroups.Get") 18 16 135 34
$btnClearAccountGroups = New-SoftButton (Get-UiText "Common.Clear") 163 16 95 34
$btnExportAccountGroupsCsv = New-SoftButton (Get-UiText "Common.ExportCsv") 268 16 112 34
$btnExportAccountGroupsXlsx = New-SoftButton (Get-UiText "Common.ExportXlsx") 390 16 118 34
$btnCopyAccountGroupNames = New-SoftButton (Get-UiText "Common.CopyNames") 518 16 130 34

$lblAccountGroupsSearch = New-Label (Get-UiText "Common.Search") 18 60 55 22
$txtAccountGroupsSearch = New-TextBoxEx 73 57 250 $false

$lblAccountGroupsInfo = New-Label (Get-UiText "Common.ExportVisibleInfo") 340 58 490 22 8.5 ([System.Drawing.FontStyle]::Italic)
$lblAccountGroupsInfo.ForeColor = $script:Theme.Muted

$lblAccountGroupsCount = New-Label (Get-UiText "Groups.CountEmpty") 850 22 230 24 10 ([System.Drawing.FontStyle]::Bold)
$lblAccountGroupsCount.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblAccountGroupsCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight

$accountGroupsTop.Controls.AddRange(@($btnGetAccountGroups, $btnClearAccountGroups, $btnExportAccountGroupsCsv, $btnExportAccountGroupsXlsx, $btnCopyAccountGroupNames, $lblAccountGroupsSearch, $txtAccountGroupsSearch, $lblAccountGroupsInfo, $lblAccountGroupsCount))

$gridAccountGroups = New-Object System.Windows.Forms.DataGridView
$gridAccountGroups.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridAccountGroups.AutoGenerateColumns = $false
$gridAccountGroups.ColumnHeadersVisible = $true
$gridAccountGroups.BackgroundColor = [System.Drawing.Color]::White
$gridAccountGroups.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$gridAccountGroups.ReadOnly = $true
$gridAccountGroups.AllowUserToAddRows = $false
$gridAccountGroups.AllowUserToDeleteRows = $false
$gridAccountGroups.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$gridAccountGroups.MultiSelect = $true
$gridAccountGroups.RowHeadersVisible = $false
$gridAccountGroups.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$gridAccountGroups.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$gridAccountGroups.Font = New-UiFont 9
$gridAccountGroups.ColumnHeadersDefaultCellStyle.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Bold)
$gridAccountGroups.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(92, 118, 28)
$gridAccountGroups.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$gridAccountGroups.ColumnHeadersDefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(92, 118, 28)
$gridAccountGroups.EnableHeadersVisualStyles = $false
$gridAccountGroups.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(246, 250, 240)
$gridAccountGroups.GridColor = $script:Theme.Border
$gridAccountGroups.RowTemplate.Height = 25
Set-DoubleBuffered $gridAccountGroups

[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "Name" (Get-UiText "Column.Name") 190 $true))
[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "SamAccountName" (Get-UiText "Column.GroupLogin") 150 $true))
[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "DisplayName" (Get-UiText "Column.DisplayName") 190 $true))
[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "Type" (Get-UiText "Column.Type") 95 $true))
[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "Scope" (Get-UiText "Column.Scope") 95 $true))
[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "Source" (Get-UiText "Column.Source") 115 $true))
[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "Description" (Get-UiText "Column.Description") 260 $true))
[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "DistinguishedName" "DN" 300 $false))

$tabAccountGroups.Controls.Add($gridAccountGroups)
$tabAccountGroups.Controls.Add($accountGroupsTop)



# ---- Group members tab ----
$groupMembersTop = New-Object System.Windows.Forms.Panel
$groupMembersTop.Dock = [System.Windows.Forms.DockStyle]::Top
$groupMembersTop.Height = 92
$groupMembersTop.BackColor = $script:Theme.Back

$btnGetGroupMembers = New-FlatButton (Get-UiText "GroupMembers.Get") 18 16 150 34
$btnClearGroupMembers = New-SoftButton (Get-UiText "Common.Clear") 178 16 95 34
$btnExportGroupMembersCsv = New-SoftButton (Get-UiText "Common.ExportCsv") 283 16 112 34
$btnExportGroupMembersXlsx = New-SoftButton (Get-UiText "Common.ExportXlsx") 405 16 118 34
$btnCopyGroupMemberNames = New-SoftButton (Get-UiText "Common.CopyNames") 533 16 130 34

$lblGroupMembersSearch = New-Label (Get-UiText "Common.Search") 18 60 55 22
$txtGroupMembersSearch = New-TextBoxEx 73 57 250 $false

$lblGroupMembersInfo = New-Label (Get-UiText "Common.ExportVisibleInfo") 340 58 490 22 8.5 ([System.Drawing.FontStyle]::Italic)
$lblGroupMembersInfo.ForeColor = $script:Theme.Muted

$lblGroupMembersCount = New-Label (Get-UiText "GroupMembers.CountEmpty") 850 22 230 24 10 ([System.Drawing.FontStyle]::Bold)
$lblGroupMembersCount.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblGroupMembersCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight

$groupMembersTop.Controls.AddRange(@($btnGetGroupMembers, $btnClearGroupMembers, $btnExportGroupMembersCsv, $btnExportGroupMembersXlsx, $btnCopyGroupMemberNames, $lblGroupMembersSearch, $txtGroupMembersSearch, $lblGroupMembersInfo, $lblGroupMembersCount))

$gridGroupMembers = New-Object System.Windows.Forms.DataGridView
$gridGroupMembers.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridGroupMembers.AutoGenerateColumns = $false
$gridGroupMembers.ColumnHeadersVisible = $true
$gridGroupMembers.BackgroundColor = [System.Drawing.Color]::White
$gridGroupMembers.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$gridGroupMembers.ReadOnly = $true
$gridGroupMembers.AllowUserToAddRows = $false
$gridGroupMembers.AllowUserToDeleteRows = $false
$gridGroupMembers.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$gridGroupMembers.MultiSelect = $true
$gridGroupMembers.RowHeadersVisible = $false
$gridGroupMembers.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$gridGroupMembers.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$gridGroupMembers.Font = New-UiFont 9
$gridGroupMembers.ColumnHeadersDefaultCellStyle.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Bold)
$gridGroupMembers.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(174, 48, 82)
$gridGroupMembers.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$gridGroupMembers.ColumnHeadersDefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(174, 48, 82)
$gridGroupMembers.EnableHeadersVisualStyles = $false
$gridGroupMembers.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(253, 244, 247)
$gridGroupMembers.GridColor = $script:Theme.Border
$gridGroupMembers.RowTemplate.Height = 25
Set-DoubleBuffered $gridGroupMembers

[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "Name" (Get-UiText "Column.Name") 190 $true))
[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "SamAccountName" (Get-UiText "Column.Login") 150 $true))
[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "DisplayName" (Get-UiText "Column.DisplayName") 190 $true))
[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "ObjectType" (Get-UiText "Column.Type") 95 $true))
[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "Enabled" "Enabled" 80 $true))
[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "UserPrincipalName" "UPN" 210 $true))
[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "Description" (Get-UiText "Column.Description") 260 $true))
[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "DistinguishedName" "DN" 320 $false))

$tabGroupMembers.Controls.Add($gridGroupMembers)
$tabGroupMembers.Controls.Add($groupMembersTop)



# ---- Managed groups tab ----
$managedGroupsTop = New-Object System.Windows.Forms.Panel
$managedGroupsTop.Dock = [System.Windows.Forms.DockStyle]::Top
$managedGroupsTop.Height = 92
$managedGroupsTop.BackColor = $script:Theme.Back

$btnGetManagedGroups = New-FlatButton (Get-UiText "ManagedGroups.Get") 18 16 135 34
$btnClearManagedGroups = New-SoftButton (Get-UiText "Common.Clear") 163 16 95 34
$btnExportManagedGroupsCsv = New-SoftButton (Get-UiText "Common.ExportCsv") 268 16 112 34
$btnExportManagedGroupsXlsx = New-SoftButton (Get-UiText "Common.ExportXlsx") 390 16 118 34
$btnCopyManagedGroupNames = New-SoftButton (Get-UiText "Common.CopyNames") 518 16 130 34

$lblManagedGroupsSearch = New-Label (Get-UiText "Common.Search") 18 60 55 22
$txtManagedGroupsSearch = New-TextBoxEx 73 57 250 $false

$lblManagedGroupsInfo = New-Label (Get-UiText "Common.ExportVisibleInfo") 340 58 490 22 8.5 ([System.Drawing.FontStyle]::Italic)
$lblManagedGroupsInfo.ForeColor = $script:Theme.Muted

$lblManagedGroupsCount = New-Label (Get-UiText "Groups.CountEmpty") 850 22 230 24 10 ([System.Drawing.FontStyle]::Bold)
$lblManagedGroupsCount.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblManagedGroupsCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight

$managedGroupsTop.Controls.AddRange(@($btnGetManagedGroups, $btnClearManagedGroups, $btnExportManagedGroupsCsv, $btnExportManagedGroupsXlsx, $btnCopyManagedGroupNames, $lblManagedGroupsSearch, $txtManagedGroupsSearch, $lblManagedGroupsInfo, $lblManagedGroupsCount))

$gridManagedGroups = New-Object System.Windows.Forms.DataGridView
$gridManagedGroups.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridManagedGroups.AutoGenerateColumns = $false
$gridManagedGroups.ColumnHeadersVisible = $true
$gridManagedGroups.BackgroundColor = [System.Drawing.Color]::White
$gridManagedGroups.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$gridManagedGroups.ReadOnly = $true
$gridManagedGroups.AllowUserToAddRows = $false
$gridManagedGroups.AllowUserToDeleteRows = $false
$gridManagedGroups.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$gridManagedGroups.MultiSelect = $true
$gridManagedGroups.RowHeadersVisible = $false
$gridManagedGroups.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$gridManagedGroups.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$gridManagedGroups.Font = New-UiFont 9
$gridManagedGroups.ColumnHeadersDefaultCellStyle.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Bold)
$gridManagedGroups.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(82, 104, 201)
$gridManagedGroups.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$gridManagedGroups.ColumnHeadersDefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(82, 104, 201)
$gridManagedGroups.EnableHeadersVisualStyles = $false
$gridManagedGroups.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(244, 245, 255)
$gridManagedGroups.GridColor = $script:Theme.Border
$gridManagedGroups.RowTemplate.Height = 25
Set-DoubleBuffered $gridManagedGroups

[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "Name" (Get-UiText "Column.Name") 190 $true))
[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "SamAccountName" (Get-UiText "Column.GroupLogin") 150 $true))
[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "DisplayName" (Get-UiText "Column.DisplayName") 190 $true))
[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "Type" (Get-UiText "Column.Type") 95 $true))
[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "Scope" (Get-UiText "Column.Scope") 95 $true))
[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "Source" (Get-UiText "Column.Source") 115 $true))
[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "Description" (Get-UiText "Column.Description") 260 $true))
[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "DistinguishedName" "DN" 300 $false))

$tabManagedGroups.Controls.Add($gridManagedGroups)
$tabManagedGroups.Controls.Add($managedGroupsTop)


# ---- Manager accounts tab ----
$managerTop = New-Object System.Windows.Forms.Panel
$managerTop.Dock = [System.Windows.Forms.DockStyle]::Top
$managerTop.Height = 92
$managerTop.BackColor = $script:Theme.Back

$btnManaged = New-FlatButton (Get-UiText "ManagerAccounts.Get") 18 16 135 34
$btnClearManaged = New-SoftButton (Get-UiText "Common.Clear") 163 16 95 34
$btnExportCsv = New-SoftButton (Get-UiText "ManagerAccounts.ExportCsv") 268 16 112 34
$btnExportXlsx = New-SoftButton (Get-UiText "ManagerAccounts.ExportXlsx") 390 16 118 34
$btnCopyLogins = New-SoftButton (Get-UiText "ManagerAccounts.CopyLogins") 518 16 120 34

$lblManagedFilter = New-Label (Get-UiText "ManagerAccounts.Show") 18 60 50 22
$rdoManagedAll = New-Object System.Windows.Forms.RadioButton
$rdoManagedAll.Text = Get-UiText "Filter.All"
$rdoManagedAll.Location = New-Point 72 58
$rdoManagedAll.AutoSize = $true
$rdoManagedAll.Checked = $true
$rdoManagedAll.Font = New-UiFont 9
$rdoManagedActive = New-Object System.Windows.Forms.RadioButton
$rdoManagedActive.Text = Get-UiText "Filter.Active"
$rdoManagedActive.Location = New-Point 162 58
$rdoManagedActive.AutoSize = $true
$rdoManagedActive.Font = New-UiFont 9
$rdoManagedInactive = New-Object System.Windows.Forms.RadioButton
$rdoManagedInactive.Text = Get-UiText "Filter.Inactive"
$rdoManagedInactive.Location = New-Point 242 58
$rdoManagedInactive.AutoSize = $true
$rdoManagedInactive.Font = New-UiFont 9

$lblSearch = New-Label (Get-UiText "ManagerAccounts.Search") 380 60 55 22
$txtManagedSearch = New-TextBoxEx 435 57 230 $false

$lblManagedCount = New-Label (Get-UiText "ManagerAccounts.CountEmpty") 700 22 360 24 10 ([System.Drawing.FontStyle]::Bold)
$lblManagedCount.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblManagedCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblManagedInfo = New-Label (Get-UiText "ManagerAccounts.ExportInfo") 700 56 360 22 8.5 ([System.Drawing.FontStyle]::Italic)
$lblManagedInfo.ForeColor = $script:Theme.Muted
$lblManagedInfo.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblManagedInfo.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight

$managerTop.Controls.AddRange(@($btnManaged, $btnClearManaged, $btnExportCsv, $btnExportXlsx, $btnCopyLogins, $lblManagedFilter, $rdoManagedAll, $rdoManagedActive, $rdoManagedInactive, $lblSearch, $txtManagedSearch, $lblManagedCount, $lblManagedInfo))

$gridManaged = New-Object System.Windows.Forms.DataGridView
$gridManaged.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridManaged.AutoGenerateColumns = $false
$gridManaged.ColumnHeadersVisible = $true
$gridManaged.BackgroundColor = [System.Drawing.Color]::White
$gridManaged.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$gridManaged.ReadOnly = $true
$gridManaged.AllowUserToAddRows = $false
$gridManaged.AllowUserToDeleteRows = $false
$gridManaged.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$gridManaged.MultiSelect = $true
$gridManaged.RowHeadersVisible = $false
$gridManaged.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$gridManaged.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$gridManaged.Font = New-UiFont 9
$gridManaged.ColumnHeadersDefaultCellStyle.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Bold)
$gridManaged.ColumnHeadersDefaultCellStyle.BackColor = $script:Theme.Navy
$gridManaged.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$gridManaged.ColumnHeadersDefaultCellStyle.SelectionBackColor = $script:Theme.Navy
$gridManaged.EnableHeadersVisualStyles = $false
$gridManaged.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(245, 249, 253)
$gridManaged.GridColor = $script:Theme.Border
$gridManaged.RowTemplate.Height = 24
Set-DoubleBuffered $gridManaged

[void]$gridManaged.Columns.Add((New-TextGridColumn "SamAccountName" (Get-UiText "Column.Login") 120 $true))
[void]$gridManaged.Columns.Add((New-TextGridColumn "Name" (Get-UiText "Column.Name") 150 $true))
[void]$gridManaged.Columns.Add((New-TextGridColumn "DisplayName" (Get-UiText "Column.DisplayName") 185 $true))
[void]$gridManaged.Columns.Add((New-TextGridColumn "Enabled" (Get-UiText "Column.Enabled") 70 $true))
[void]$gridManaged.Columns.Add((New-TextGridColumn "UserPrincipalName" "UPN" 210 $true))
[void]$gridManaged.Columns.Add((New-TextGridColumn "Description" (Get-UiText "Column.Description") 260 $true))
[void]$gridManaged.Columns.Add((New-TextGridColumn "PasswordLastSet" (Get-UiText "Column.PasswordLastSet") 150 $true))
[void]$gridManaged.Columns.Add((New-TextGridColumn "DistinguishedName" "DN" 260 $false))


$tabManager.Controls.Add($gridManaged)
$tabManager.Controls.Add($managerTop)

function Set-AccountPropertiesGrid {
    param([object[]]$Rows)

    $gridAccountProps.SuspendLayout()
    try {
        $gridAccountProps.Rows.Clear()
        if ($null -ne $Rows) {
            foreach ($row in $Rows) {
                [void]$gridAccountProps.Rows.Add(
                    [string]$row.Attribute,
                    [string]$row.Value,
                    [string]$row.Count
                )
            }
        }
        $gridAccountProps.ClearSelection()
    }
    finally {
        $gridAccountProps.ResumeLayout()
    }
}

function Filter-AccountPropertyRows {
    param([object[]]$Rows)

    if ($null -eq $Rows) { return @() }
    $query = ""
    try { $query = $txtAccountPropsSearch.Text.Trim() } catch { }
    if (Is-Blank $query) { return @($Rows) }

    $q = $query.ToLowerInvariant()
    return @($Rows | Where-Object {
        ([string]$_.Attribute).ToLowerInvariant().Contains($q)
    })
}

function Refresh-AccountPropertiesGrid {
    $filteredRows = @(Filter-AccountPropertyRows -Rows $script:AccountPropertyRows)
    $totalCount = @($script:AccountPropertyRows).Count
    Set-AccountPropertiesGrid -Rows $filteredRows

    if (Is-Blank $txtAccountPropsSearch.Text) {
        $lblAccountPropsCount.Text = Get-UiText "AccountProperties.Count" @($filteredRows.Count)
    }
    else {
        $lblAccountPropsCount.Text = Get-UiText "AccountProperties.CountFiltered" @($filteredRows.Count, $totalCount)
    }
    return $filteredRows.Count
}

function Update-AccountPropertiesSearchView {
    if (-not $script:AccountPropertyRowsLoaded) { return }
    $visibleCount = Refresh-AccountPropertiesGrid
    $totalCount = @($script:AccountPropertyRows).Count
    Set-Status (Get-UiText "Status.AccountPropertiesSearch" @($txtAccountPropsSearch.Text, $visibleCount, $totalCount)) "Info"
}

function Get-CurrentVisibleAccountPropertyRows {
    if (-not $script:AccountPropertyRowsLoaded) { return @() }
    return @(Filter-AccountPropertyRows -Rows $script:AccountPropertyRows)
}

function Copy-SelectedAccountPropertyValues {
    try {
        $selectedRows = @($gridAccountProps.SelectedRows | Where-Object {
            $null -ne $_ -and -not $_.IsNewRow
        } | Sort-Object -Property Index)

        if ($selectedRows.Count -eq 0) {
            Show-InfoBox (Get-UiText "Status.SelectRow") (Get-UiText "Dialog.NoSelection")
            return
        }

        $values = @($selectedRows | ForEach-Object {
            [string]$_.Cells["Value"].Value
        })
        $text = $values -join [Environment]::NewLine

        if ($text.Length -eq 0) {
            [System.Windows.Forms.Clipboard]::Clear()
        }
        else {
            [System.Windows.Forms.Clipboard]::SetText($text)
        }
        Set-Status (Get-UiText "Status.ValuesCopied" @($values.Count)) "Ok"
    }
    catch {
        Set-Status (Get-UiText "Status.ClipboardFailed" @($_.Exception.Message)) "Error"
    }
}

function Export-AccountPropertiesWithDialog {
    param([ValidateSet("CSV", "XLSX")][string]$Format)

    if (-not $script:AccountPropertyRowsLoaded) {
        Show-InfoBox (Get-UiText "Status.GetAccountPropertiesFirst") (Get-UiText "Dialog.NoData")
        return
    }
    if (@($script:AccountPropertyRows).Count -eq 0) {
        Show-InfoBox (Get-UiText "Status.NoAccountPropertiesToExport") (Get-UiText "Dialog.NoData")
        return
    }

    $rows = @(Get-CurrentVisibleAccountPropertyRows)
    if ($rows.Count -eq 0) {
        Show-InfoBox (Get-UiText "Status.NoVisibleAccountProperties") (Get-UiText "Dialog.NoData")
        return
    }

    Export-VisibleRowsWithDialog `
        -Format $Format `
        -ExportRows @(Convert-AccountPropertyRowsToExportRows -Rows $rows) `
        -FileNameBase (Get-UiText "Export.AccountPropertiesFileNameBase") `
        -SheetName (Get-UiText "Export.AccountPropertiesSheetName") `
        -SaveTitle (Get-UiText "Export.AccountPropertiesSaveTitle") `
        -Widths @(28, 80, 10)
}

function Set-AccountGroupsGrid {
    param([object[]]$Rows)

    $gridAccountGroups.SuspendLayout()
    try {
        $gridAccountGroups.Rows.Clear()
        if ($null -ne $Rows) {
            foreach ($row in $Rows) {
                [void]$gridAccountGroups.Rows.Add(
                    [string]$row.Name,
                    [string]$row.SamAccountName,
                    [string]$row.DisplayName,
                    [string]$row.Type,
                    [string]$row.Scope,
                    [string]$row.Source,
                    [string]$row.Description,
                    [string]$row.DistinguishedName
                )
            }
        }
        $gridAccountGroups.ClearSelection()
    }
    finally {
        $gridAccountGroups.ResumeLayout()
    }
}

function Filter-GroupRows {
    param([object[]]$Rows, [string]$Query)

    if ($null -eq $Rows) { return @() }
    if (Is-Blank $Query) { return @($Rows) }

    $q = $Query.Trim().ToLowerInvariant()
    return @($Rows | Where-Object {
        ([string]$_.Name).ToLowerInvariant().Contains($q) -or
        ([string]$_.SamAccountName).ToLowerInvariant().Contains($q) -or
        ([string]$_.DisplayName).ToLowerInvariant().Contains($q) -or
        ([string]$_.Type).ToLowerInvariant().Contains($q) -or
        ([string]$_.Scope).ToLowerInvariant().Contains($q) -or
        ([string]$_.Source).ToLowerInvariant().Contains($q) -or
        ([string]$_.Description).ToLowerInvariant().Contains($q)
    })
}

function Refresh-AccountGroupsGrid {
    $filteredRows = @(Filter-GroupRows -Rows $script:AccountGroupRows -Query $txtAccountGroupsSearch.Text)
    $totalCount = @($script:AccountGroupRows).Count
    Set-AccountGroupsGrid -Rows $filteredRows

    if (Is-Blank $txtAccountGroupsSearch.Text) {
        $lblAccountGroupsCount.Text = Get-UiText "Groups.Count" @($filteredRows.Count)
    }
    else {
        $lblAccountGroupsCount.Text = Get-UiText "Groups.CountFiltered" @($filteredRows.Count, $totalCount)
    }
    return $filteredRows.Count
}

function Update-AccountGroupsSearchView {
    if (-not $script:AccountGroupRowsLoaded) { return }
    $visibleCount = Refresh-AccountGroupsGrid
    $totalCount = @($script:AccountGroupRows).Count
    Set-Status (Get-UiText "Status.AccountGroupsSearch" @($txtAccountGroupsSearch.Text, $visibleCount, $totalCount)) "Info"
}

function Get-CurrentVisibleAccountGroupRows {
    if (-not $script:AccountGroupRowsLoaded) { return @() }
    return @(Filter-GroupRows -Rows $script:AccountGroupRows -Query $txtAccountGroupsSearch.Text)
}

function Copy-SelectedGroupNames {
    param($Grid)

    try {
        if ($Grid.SelectedRows.Count -eq 0) {
            Show-InfoBox (Get-UiText "Status.SelectRow") (Get-UiText "Dialog.NoSelection")
            return
        }

        $names = @()
        foreach ($row in $Grid.SelectedRows) {
            if ($null -ne $row.Cells["Name"].Value) {
                $names += [string]$row.Cells["Name"].Value
            }
        }
        $names = @($names | Sort-Object -Unique)
        $text = $names -join [Environment]::NewLine
        if (-not (Is-Blank $text)) {
            [System.Windows.Forms.Clipboard]::SetText($text)
            Set-Status (Get-UiText "Status.NamesCopied" @($names.Count)) "Ok"
        }
    }
    catch {
        Set-Status (Get-UiText "Status.ClipboardFailed" @($_.Exception.Message)) "Error"
    }
}

function Export-AccountGroupsWithDialog {
    param([ValidateSet("CSV", "XLSX")][string]$Format)

    if (-not $script:AccountGroupRowsLoaded) {
        Show-InfoBox (Get-UiText "Status.GetAccountGroupsFirst") (Get-UiText "Dialog.NoData")
        return
    }
    if (@($script:AccountGroupRows).Count -eq 0) {
        Show-InfoBox (Get-UiText "Status.NoAccountGroupsToExport") (Get-UiText "Dialog.NoData")
        return
    }

    $rows = @(Get-CurrentVisibleAccountGroupRows)
    if ($rows.Count -eq 0) {
        Show-InfoBox (Get-UiText "Status.NoVisibleAccountGroups") (Get-UiText "Dialog.NoData")
        return
    }

    Export-VisibleRowsWithDialog `
        -Format $Format `
        -ExportRows @(Convert-GroupRowsToExportRows -Rows $rows) `
        -FileNameBase (Get-UiText "Export.AccountGroupsFileNameBase") `
        -SheetName (Get-UiText "Export.AccountGroupsSheetName") `
        -SaveTitle (Get-UiText "Export.AccountGroupsSaveTitle") `
        -Widths @(28, 24, 28, 16, 16, 18, 42)
}


function Set-ManagedGroupsGrid {
    param([object[]]$Rows)

    $gridManagedGroups.SuspendLayout()
    try {
        $gridManagedGroups.Rows.Clear()
        if ($null -ne $Rows) {
            foreach ($row in $Rows) {
                [void]$gridManagedGroups.Rows.Add(
                    [string]$row.Name,
                    [string]$row.SamAccountName,
                    [string]$row.DisplayName,
                    [string]$row.Type,
                    [string]$row.Scope,
                    [string]$row.Source,
                    [string]$row.Description,
                    [string]$row.DistinguishedName
                )
            }
        }
        $gridManagedGroups.ClearSelection()
    }
    finally {
        $gridManagedGroups.ResumeLayout()
    }
}

function Refresh-ManagedGroupsGrid {
    $filteredRows = @(Filter-GroupRows -Rows $script:ManagedGroupRows -Query $txtManagedGroupsSearch.Text)
    $totalCount = @($script:ManagedGroupRows).Count
    Set-ManagedGroupsGrid -Rows $filteredRows

    if (Is-Blank $txtManagedGroupsSearch.Text) {
        $lblManagedGroupsCount.Text = Get-UiText "Groups.Count" @($filteredRows.Count)
    }
    else {
        $lblManagedGroupsCount.Text = Get-UiText "Groups.CountFiltered" @($filteredRows.Count, $totalCount)
    }
    return $filteredRows.Count
}

function Update-ManagedGroupsSearchView {
    if (-not $script:ManagedGroupRowsLoaded) { return }
    $visibleCount = Refresh-ManagedGroupsGrid
    $totalCount = @($script:ManagedGroupRows).Count
    Set-Status (Get-UiText "Status.ManagedGroupsSearch" @($txtManagedGroupsSearch.Text, $visibleCount, $totalCount)) "Info"
}

function Get-CurrentVisibleManagedGroupRows {
    if (-not $script:ManagedGroupRowsLoaded) { return @() }
    return @(Filter-GroupRows -Rows $script:ManagedGroupRows -Query $txtManagedGroupsSearch.Text)
}

function Export-ManagedGroupsWithDialog {
    param([ValidateSet("CSV", "XLSX")][string]$Format)

    if (-not $script:ManagedGroupRowsLoaded) {
        Show-InfoBox (Get-UiText "Status.GetManagedGroupsFirst") (Get-UiText "Dialog.NoData")
        return
    }
    if (@($script:ManagedGroupRows).Count -eq 0) {
        Show-InfoBox (Get-UiText "Status.NoManagedGroupsToExport") (Get-UiText "Dialog.NoData")
        return
    }

    $rows = @(Get-CurrentVisibleManagedGroupRows)
    if ($rows.Count -eq 0) {
        Show-InfoBox (Get-UiText "Status.NoVisibleManagedGroups") (Get-UiText "Dialog.NoData")
        return
    }

    Export-VisibleRowsWithDialog `
        -Format $Format `
        -ExportRows @(Convert-GroupRowsToExportRows -Rows $rows) `
        -FileNameBase (Get-UiText "Export.ManagedGroupsFileNameBase") `
        -SheetName (Get-UiText "Export.ManagedGroupsSheetName") `
        -SaveTitle (Get-UiText "Export.ManagedGroupsSaveTitle") `
        -Widths @(28, 24, 28, 16, 16, 18, 42)
}





function Set-DomainGroupMembersGrid {
    param([object[]]$Rows)

    $gridGroupMembers.SuspendLayout()
    try {
        $gridGroupMembers.Rows.Clear()
        if ($null -ne $Rows) {
            foreach ($row in $Rows) {
                [void]$gridGroupMembers.Rows.Add(
                    [string]$row.Name,
                    [string]$row.SamAccountName,
                    [string]$row.DisplayName,
                    [string]$row.ObjectType,
                    [string]$row.Enabled,
                    [string]$row.UserPrincipalName,
                    [string]$row.Description,
                    [string]$row.DistinguishedName
                )
            }
        }
        $gridGroupMembers.ClearSelection()
    }
    finally {
        $gridGroupMembers.ResumeLayout()
    }
}

function Filter-GroupMemberRows {
    param([object[]]$Rows, [string]$Query)

    if ($null -eq $Rows) { return @() }
    if (Is-Blank $Query) { return @($Rows) }

    $q = $Query.Trim().ToLowerInvariant()
    return @($Rows | Where-Object {
        ([string]$_.Name).ToLowerInvariant().Contains($q) -or
        ([string]$_.SamAccountName).ToLowerInvariant().Contains($q) -or
        ([string]$_.DisplayName).ToLowerInvariant().Contains($q) -or
        ([string]$_.ObjectType).ToLowerInvariant().Contains($q) -or
        ([string]$_.Enabled).ToLowerInvariant().Contains($q) -or
        ([string]$_.UserPrincipalName).ToLowerInvariant().Contains($q) -or
        ([string]$_.Description).ToLowerInvariant().Contains($q)
    })
}

function Refresh-GroupMembersGrid {
    $filteredRows = @(Filter-GroupMemberRows -Rows $script:DomainGroupMemberRows -Query $txtGroupMembersSearch.Text)
    $totalCount = @($script:DomainGroupMemberRows).Count
    Set-DomainGroupMembersGrid -Rows $filteredRows

    if (Is-Blank $txtGroupMembersSearch.Text) {
        $lblGroupMembersCount.Text = Get-UiText "GroupMembers.Count" @($filteredRows.Count)
    }
    else {
        $lblGroupMembersCount.Text = Get-UiText "GroupMembers.CountFiltered" @($filteredRows.Count, $totalCount)
    }
    return $filteredRows.Count
}

function Update-GroupMembersSearchView {
    if (-not $script:DomainGroupMemberRowsLoaded) { return }
    $visibleCount = Refresh-GroupMembersGrid
    $totalCount = @($script:DomainGroupMemberRows).Count
    Set-Status (Get-UiText "Status.GroupMembersSearch" @($txtGroupMembersSearch.Text, $visibleCount, $totalCount)) "Info"
}

function Get-CurrentVisibleGroupMemberRows {
    if (-not $script:DomainGroupMemberRowsLoaded) { return @() }
    return @(Filter-GroupMemberRows -Rows $script:DomainGroupMemberRows -Query $txtGroupMembersSearch.Text)
}

function Export-GroupMembersWithDialog {
    param([ValidateSet("CSV", "XLSX")][string]$Format)

    if (-not $script:DomainGroupMemberRowsLoaded) {
        Show-InfoBox (Get-UiText "Status.GetGroupMembersFirst") (Get-UiText "Dialog.NoData")
        return
    }
    if (@($script:DomainGroupMemberRows).Count -eq 0) {
        Show-InfoBox (Get-UiText "Status.NoGroupMembersToExport") (Get-UiText "Dialog.NoData")
        return
    }

    $rows = @(Get-CurrentVisibleGroupMemberRows)
    if ($rows.Count -eq 0) {
        Show-InfoBox (Get-UiText "Status.NoVisibleGroupMembers") (Get-UiText "Dialog.NoData")
        return
    }

    Export-VisibleRowsWithDialog `
        -Format $Format `
        -ExportRows @(Convert-GroupMemberRowsToExportRows -Rows $rows) `
        -FileNameBase (Get-UiText "Export.GroupMembersFileNameBase") `
        -SheetName (Get-UiText "Export.GroupMembersSheetName") `
        -SaveTitle (Get-UiText "Export.GroupMembersSaveTitle") `
        -Widths @(28, 24, 28, 16, 14, 32, 42)
}

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.SizingGrip = $true
$statusStrip.BackColor = [System.Drawing.Color]::FromArgb(235, 241, 248)
$toolStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
$script:StatusLabel = $toolStatus
$toolStatus.Text = Get-UiText "Status.ReadyShort"
$toolStatus.ForeColor = $script:Theme.Text
$toolStatus.Spring = $true
$toolStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
[void]$statusStrip.Items.Add($toolStatus)

$form.Controls.Add($tabs)
$form.Controls.Add($contextPanel)
$form.Controls.Add($header)
$form.Controls.Add($statusStrip)

