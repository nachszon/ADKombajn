# ==================================================
# Splash
# ==================================================

function New-RoundedRectanglePath {
    param(
        [System.Drawing.Rectangle]$Rect,
        [int]$Radius
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $Radius * 2

    if ($diameter -le 0) {
        [void]$path.AddRectangle($Rect)
        return $path
    }

    $arc = New-Object System.Drawing.Rectangle($Rect.X, $Rect.Y, $diameter, $diameter)
    [void]$path.AddArc($arc, 180, 90)
    $arc.X = $Rect.Right - $diameter
    [void]$path.AddArc($arc, 270, 90)
    $arc.Y = $Rect.Bottom - $diameter
    [void]$path.AddArc($arc, 0, 90)
    $arc.X = $Rect.X
    [void]$path.AddArc($arc, 90, 90)
    [void]$path.CloseFigure()
    return $path
}

function Show-WinSplash {
    param(
        [int]$Milliseconds = 1600,
        [string]$Title = "ADKombajn",
        [string]$Subtitle = (Get-UiText "Splash.Subtitle"),
        [string]$Version = $script:AppVersion,
        [string]$Author = (Get-UiText "Splash.Author" @($script:AppAuthor))
    )

    $splash = $null
    $splashPicture = $null

    try {
        $totalMs = [Math]::Max(700, [int]$Milliseconds)
        $greenDark = [System.Drawing.Color]::FromArgb(18, 66, 55)
        $green = [System.Drawing.Color]::FromArgb(38, 145, 94)
        $softGreen = [System.Drawing.Color]::FromArgb(222, 245, 232)
        $mutedGreen = [System.Drawing.Color]::FromArgb(196, 231, 212)

        $splash = New-Object System.Windows.Forms.Form
        $splash.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $splash.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $splash.ClientSize = New-Size 700 360
        $splash.BackColor = $greenDark
        $splash.ShowInTaskbar = $false
        $splash.TopMost = $true
        $splash.Opacity = 0.0
        $splash.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
        Set-DoubleBuffered $splash
        Apply-AppWindowIcon $splash

        $splash.Add_Paint({
            param($sender, $e)

            if ($sender.ClientRectangle.Width -le 0 -or $sender.ClientRectangle.Height -le 0) { return }

            $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList @(
                $sender.ClientRectangle,
                $greenDark,
                $green,
                [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal
            )
            try {
                $e.Graphics.FillRectangle($brush, $sender.ClientRectangle)
            }
            finally {
                $brush.Dispose()
            }
        })

        $splashPicture = New-Object System.Windows.Forms.PictureBox
        $splashPicture.Location = New-Point 26 48
        $splashPicture.Size = New-Size 300 190
        $splashPicture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $splashPicture.BackColor = [System.Drawing.Color]::Transparent
        $splashPicture.Image = $script:BrandImage
        $splashPicture.TabStop = $false
        [void]$splash.Controls.Add($splashPicture)

        $splashTitle = New-Object System.Windows.Forms.Label
        $splashTitle.Text = $Title
        $splashTitle.ForeColor = [System.Drawing.Color]::White
        $splashTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 30)
        $splashTitle.AutoSize = $true
        $splashTitle.Location = New-Point 350 78
        $splashTitle.BackColor = [System.Drawing.Color]::Transparent
        [void]$splash.Controls.Add($splashTitle)

        $splashSubtitle = New-Object System.Windows.Forms.Label
        $splashSubtitle.Text = $Subtitle
        $splashSubtitle.ForeColor = $softGreen
        $splashSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 11)
        $splashSubtitle.AutoSize = $true
        $splashSubtitle.Location = New-Point 354 139
        $splashSubtitle.BackColor = [System.Drawing.Color]::Transparent
        [void]$splash.Controls.Add($splashSubtitle)

        $splashVersion = New-Object System.Windows.Forms.Label
        $splashVersion.Text = Get-UiText "Splash.Version" @($Version)
        $splashVersion.ForeColor = [System.Drawing.Color]::White
        $splashVersion.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
        $splashVersion.AutoSize = $true
        $splashVersion.Location = New-Point 354 184
        $splashVersion.BackColor = [System.Drawing.Color]::Transparent
        [void]$splash.Controls.Add($splashVersion)

        $splashAuthor = New-Object System.Windows.Forms.Label
        $splashAuthor.Text = $Author
        $splashAuthor.ForeColor = $mutedGreen
        $splashAuthor.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $splashAuthor.AutoSize = $true
        $splashAuthor.Location = New-Point 354 209
        $splashAuthor.BackColor = [System.Drawing.Color]::Transparent
        [void]$splash.Controls.Add($splashAuthor)

        $barBack = New-Object System.Windows.Forms.Panel
        $barBack.Location = New-Point 30 300
        $barBack.Size = New-Size 640 8
        $barBack.BackColor = [System.Drawing.Color]::FromArgb(13, 74, 55)
        [void]$splash.Controls.Add($barBack)

        $barFill = New-Object System.Windows.Forms.Panel
        $barFill.Location = New-Point 0 0
        $barFill.Size = New-Size 12 8
        $barFill.BackColor = [System.Drawing.Color]::FromArgb(92, 225, 148)
        [void]$barBack.Controls.Add($barFill)

        $splashStatus = New-Object System.Windows.Forms.Label
        $splashStatus.Text = Get-UiText "Splash.Loading"
        $splashStatus.ForeColor = $softGreen
        $splashStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $splashStatus.AutoSize = $true
        $splashStatus.Location = New-Point 30 318
        $splashStatus.BackColor = [System.Drawing.Color]::Transparent
        [void]$splash.Controls.Add($splashStatus)

        $splash.Show()
        $splash.Activate()
        [System.Windows.Forms.Application]::DoEvents()

        $step = 25
        $elapsed = 0
        while ($elapsed -lt $totalMs) {
            $progress = [Math]::Min(1.0, ([double]$elapsed / [double]$totalMs))
            $barFill.Width = [int]([Math]::Max(12.0, [double]$barBack.Width * $progress))

            if ($elapsed -lt 250) {
                $splash.Opacity = [Math]::Min(1.0, ([double]$elapsed / 250.0))
            }
            elseif ($elapsed -gt ($totalMs - 280)) {
                $remaining = [Math]::Max(0, ($totalMs - $elapsed))
                $splash.Opacity = [Math]::Max(0.0, ([double]$remaining / 280.0))
            }
            else {
                $splash.Opacity = 1.0
            }

            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds $step
            $elapsed += $step
        }
    }
    catch { }
    finally {
        if ($null -ne $splashPicture) { $splashPicture.Image = $null }
        if ($null -ne $splash -and -not $splash.IsDisposed) {
            $splash.Close()
            [System.Windows.Forms.Application]::DoEvents()
            $splash.Dispose()
        }
    }
}

