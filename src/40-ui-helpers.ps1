# ==================================================
# GUI helpers
# ==================================================

function New-UiFont {
    param(
        [single]$Size = 9.0,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )

    return New-Object System.Drawing.Font("Segoe UI", $Size, $Style)
}

function New-Point {
    param([int]$X, [int]$Y)
    return New-Object System.Drawing.Point($X, $Y)
}

function New-Size {
    param([int]$W, [int]$H)
    return New-Object System.Drawing.Size($W, $H)
}

function Set-DoubleBuffered {
    param($Control)

    if ($null -eq $Control) { return }

    try {
        $flags = [System.Reflection.BindingFlags] "Instance, NonPublic"
        $prop = $Control.GetType().GetProperty("DoubleBuffered", $flags)
        if ($null -ne $prop) { $prop.SetValue($Control, $true, $null) }
    }
    catch { }
}


function Get-AppWindowIcon {
    <#
        A WinForms window does not always inherit the icon set by ps2exe -IconFile.
        That parameter sets the EXE file icon, while the form still requires
        an explicit $form.Icon value.

        Lookup order:
        1. known kombajn*.ico files next to the script/EXE,
        2. the icon embedded in the running EXE by ps2exe -IconFile.
    #>

    $candidates = New-Object System.Collections.ArrayList

    try {
        if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
            [void]$candidates.Add((Join-Path $PSScriptRoot "kombajn1.ico"))
            [void]$candidates.Add((Join-Path $PSScriptRoot "kombajn2.ico"))
            [void]$candidates.Add((Join-Path $PSScriptRoot "kombajn3.ico"))
        }
    }
    catch { }

    try {
        $exeDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
        if (-not [string]::IsNullOrWhiteSpace($exeDir)) {
            [void]$candidates.Add((Join-Path $exeDir "kombajn1.ico"))
            [void]$candidates.Add((Join-Path $exeDir "kombajn2.ico"))
            [void]$candidates.Add((Join-Path $exeDir "kombajn3.ico"))
        }
    }
    catch { }

    foreach ($candidate in $candidates) {
        try {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if (-not (Test-Path -LiteralPath $candidate)) { continue }

            $fs = [System.IO.File]::Open($candidate, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $ico = New-Object System.Drawing.Icon($fs)
                return $ico.Clone()
            }
            finally {
                $fs.Dispose()
            }
        }
        catch { }
    }

    try {
        $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if (-not [string]::IsNullOrWhiteSpace($exePath) -and (Test-Path -LiteralPath $exePath)) {
            return [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
        }
    }
    catch { }

    return $null
}

function Apply-AppWindowIcon {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Form]$Form
    )

    try {
        if ($null -eq $script:AppWindowIcon) {
            $script:AppWindowIcon = Get-AppWindowIcon
        }

        if ($null -ne $script:AppWindowIcon) {
            $Form.Icon = $script:AppWindowIcon
        }
    }
    catch { }
}

function Select-UiLanguage {
    if ($script:UiLanguage -in @("pl", "en")) { return $true }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "ADKombajn - Language / Język"
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $true
    $dialog.ClientSize = New-Size 430 172
    $dialog.BackColor = $script:Theme.Back
    Apply-AppWindowIcon $dialog

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Choose interface language / Wybierz język interfejsu"
    $title.Location = New-Point 20 20
    $title.Size = New-Size 390 28
    $title.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $title.Font = New-UiFont 10.5 ([System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $script:Theme.Text

    $btnPolish = New-FlatButton "Polski" 52 76 145 44
    $btnEnglish = New-FlatButton "English" 232 76 145 44

    $btnPolish.Add_Click({
        $script:UiLanguage = "pl"
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
    })
    $btnEnglish.Add_Click({
        $script:UiLanguage = "en"
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
    })

    $dialog.Controls.AddRange(@($title, $btnPolish, $btnEnglish))
    try {
        [void]$dialog.ShowDialog()
    }
    finally {
        $dialog.Dispose()
    }

    return ($script:UiLanguage -in @("pl", "en"))
}

function New-FlatButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 120,
        [int]$H = 32,
        [System.Drawing.Color]$BackColor = $script:Theme.Accent,
        [System.Drawing.Color]$ForeColor = [System.Drawing.Color]::White
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Point $X $Y
    $btn.Size = New-Size $W $H
    $btn.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Bold)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 1
    $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(174, 229, 199)
    $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(35, 145, 94)
    $btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(12, 82, 55)
    $btn.BackColor = $BackColor
    $btn.ForeColor = $ForeColor
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.UseVisualStyleBackColor = $false
    return $btn
}

function New-SoftButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 120,
        [int]$H = 32
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Point $X $Y
    $btn.Size = New-Size $W $H
    $btn.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Regular)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderColor = $script:Theme.Border
    $btn.BackColor = [System.Drawing.Color]::White
    $btn.ForeColor = $script:Theme.Text
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $btn
}

function New-Label {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 100,
        [int]$H = 24,
        [single]$FontSize = 9.0,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.Location = New-Point $X $Y
    $lbl.Size = New-Size $W $H
    $lbl.Font = New-UiFont $FontSize $Style
    $lbl.ForeColor = $script:Theme.Text
    return $lbl
}

function New-TextBoxEx {
    param(
        [int]$X,
        [int]$Y,
        [int]$W = 240,
        [bool]$Password = $false
    )

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Point $X $Y
    $txt.Width = $W
    $txt.Font = New-UiFont 9.5
    $txt.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $txt.UseSystemPasswordChar = $Password
    return $txt
}

function New-CardGroup {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H
    )

    $grp = New-Object System.Windows.Forms.GroupBox
    $grp.Text = $Text
    $grp.Location = New-Point $X $Y
    $grp.Size = New-Size $W $H
    $grp.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Bold)
    $grp.ForeColor = $script:Theme.Text
    $grp.BackColor = $script:Theme.Card
    return $grp
}

function Write-Log {
    param(
        [string]$Text,
        [ValidateSet("INFO", "OK", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $stamp = Get-Date -Format "HH:mm:ss"
    $line = "[$stamp][$Level] $Text"

    try {
        $targets = @()
        if ($null -ne $script:txtLogs -and @($script:txtLogs).Count -gt 0) {
            $targets = @($script:txtLogs)
        }
        elseif ($null -ne $script:txtLog) {
            $targets = @($script:txtLog)
        }

        foreach ($logBox in $targets) {
            if ($null -ne $logBox -and -not $logBox.IsDisposed) {
                $logBox.AppendText($line + [Environment]::NewLine)
                $logBox.SelectionStart = $logBox.TextLength
                $logBox.ScrollToCaret()
            }
        }
    }
    catch { }
}

function Set-Status {
    param(
        [string]$Text,
        [ValidateSet("Info", "Ok", "Warn", "Error")]
        [string]$Kind = "Info",
        [bool]$ToLog = $true
    )

    $color = $script:Theme.Text
    $level = "INFO"

    switch ($Kind) {
        "Ok"    { $color = $script:Theme.Good; $level = "OK" }
        "Warn"  { $color = $script:Theme.Warn; $level = "WARN" }
        "Error" { $color = $script:Theme.Bad;  $level = "ERROR" }
        default  { $color = $script:Theme.Text; $level = "INFO" }
    }

    try {
        if ($null -ne $script:StatusLabel) {
            $script:StatusLabel.Text = $Text
            $script:StatusLabel.ForeColor = $color
        }
    }
    catch { }

    if ($ToLog) { Write-Log -Text $Text -Level $level }
    try { [System.Windows.Forms.Application]::DoEvents() } catch { }
}

function Show-InfoBox {
    param([string]$Text, [string]$Title = $script:AppName)
    [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

function Show-ErrorBox {
    param([string]$Text, [string]$Title = $script:AppName)
    [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

function Show-BusyProgressWindow {
    param(
        [string]$Title = (Get-UiText "Busy.Title"),
        [string]$Message = (Get-UiText "Busy.Message"),
        [string]$Detail = (Get-UiText "Busy.Detail"),
        [int]$Width = 470
    )

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $Title
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ControlBox = $false
    $dlg.ShowInTaskbar = $false
    $dlg.TopMost = $false
    $dlg.BackColor = $script:Theme.Back
    $dlg.ClientSize = New-Object System.Drawing.Size($Width, 145)

    try {
        if ($null -ne $script:AppWindowIcon) { $dlg.Icon = $script:AppWindowIcon }
    }
    catch { }

    $outer = New-Object System.Windows.Forms.Panel
    $outer.Location = New-Object System.Drawing.Point(12, 12)
    $outer.Size = New-Object System.Drawing.Size(($Width - 24), 121)
    $outer.BackColor = $script:Theme.Card
    $outer.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.AutoSize = $false
    $lblTitle.Location = New-Object System.Drawing.Point(18, 14)
    $lblTitle.Size = New-Object System.Drawing.Size(($Width - 60), 24)
    $lblTitle.Text = $Message
    $lblTitle.Font = New-UiFont 10.0 ([System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = $script:Theme.Text

    $lblDetail = New-Object System.Windows.Forms.Label
    $lblDetail.AutoSize = $false
    $lblDetail.Location = New-Object System.Drawing.Point(18, 40)
    $lblDetail.Size = New-Object System.Drawing.Size(($Width - 60), 22)
    $lblDetail.Text = $Detail
    $lblDetail.Font = New-UiFont 8.8 ([System.Drawing.FontStyle]::Regular)
    $lblDetail.ForeColor = $script:Theme.Muted

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(18, 76)
    $progress.Size = New-Object System.Drawing.Size(($Width - 60), 18)
    $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $progress.MarqueeAnimationSpeed = 28

    $lblWait = New-Object System.Windows.Forms.Label
    $lblWait.AutoSize = $false
    $lblWait.Location = New-Object System.Drawing.Point(18, 98)
    $lblWait.Size = New-Object System.Drawing.Size(($Width - 60), 18)
    $lblWait.Text = Get-UiText "Busy.DoNotClose"
    $lblWait.Font = New-UiFont 8.0 ([System.Drawing.FontStyle]::Italic)
    $lblWait.ForeColor = $script:Theme.Muted

    $outer.Controls.AddRange(@($lblTitle, $lblDetail, $progress, $lblWait))
    $dlg.Controls.Add($outer)

    try {
        if ($null -ne $script:MainForm -and -not $script:MainForm.IsDisposed) {
            [void]$dlg.Show($script:MainForm)
        }
        else {
            [void]$dlg.Show()
        }
        $dlg.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
    catch { }

    try {
        $dlg | Add-Member -MemberType NoteProperty -Name BusyProgressBar -Value $progress -Force
        $dlg | Add-Member -MemberType NoteProperty -Name BusyDetailLabel -Value $lblDetail -Force
        $dlg | Add-Member -MemberType NoteProperty -Name BusyTitleLabel -Value $lblTitle -Force
    }
    catch { }

    return $dlg
}

function Set-BusyProgressWindow {
    param(
        $ProgressWindow,
        [string]$Message,
        [string]$Detail,
        [int]$Value = -1,
        [int]$Maximum = -1,
        [bool]$Marquee = $false
    )

    try {
        if ($null -eq $ProgressWindow -or $ProgressWindow.IsDisposed) { return }

        if (-not (Is-Blank $Message) -and $null -ne $ProgressWindow.BusyTitleLabel) {
            $ProgressWindow.BusyTitleLabel.Text = $Message
        }

        if (-not (Is-Blank $Detail) -and $null -ne $ProgressWindow.BusyDetailLabel) {
            $ProgressWindow.BusyDetailLabel.Text = $Detail
        }

        if ($null -ne $ProgressWindow.BusyProgressBar) {
            if ($Marquee) {
                $ProgressWindow.BusyProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
                $ProgressWindow.BusyProgressBar.MarqueeAnimationSpeed = 28
            }
            elseif ($Maximum -gt 0) {
                $ProgressWindow.BusyProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
                $ProgressWindow.BusyProgressBar.MarqueeAnimationSpeed = 0
                $ProgressWindow.BusyProgressBar.Minimum = 0
                $ProgressWindow.BusyProgressBar.Maximum = $Maximum
                if ($Value -lt 0) { $Value = 0 }
                if ($Value -gt $Maximum) { $Value = $Maximum }
                $ProgressWindow.BusyProgressBar.Value = $Value
            }
        }

        $ProgressWindow.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
    catch { }
}

function Close-BusyProgressWindow {
    param($ProgressWindow)

    try {
        if ($null -ne $ProgressWindow -and -not $ProgressWindow.IsDisposed) {
            $ProgressWindow.Close()
            $ProgressWindow.Dispose()
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
    catch { }
}

