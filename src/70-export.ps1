# ==================================================
# CSV / XLSX export without additional modules
# ==================================================

function Convert-ManagedRowsToExportRows {
    param([object[]]$Rows)

    $exportRows = @()
    if ($null -eq $Rows) { return $exportRows }

    foreach ($row in $Rows) {
        if ($null -eq $row) { continue }
        $exportRow = [ordered]@{}
        $exportRow[(Get-UiText "Column.Login")] = [string]$row.SamAccountName
        $exportRow[(Get-UiText "Column.Name")] = [string]$row.Name
        $exportRow[(Get-UiText "Column.DisplayName")] = [string]$row.DisplayName
        $exportRow[(Get-UiText "Column.Enabled")] = [string]$row.Enabled
        $exportRow["UPN"] = [string]$row.UserPrincipalName
        $exportRow[(Get-UiText "Column.Description")] = [string]$row.Description
        $exportRow[(Get-UiText "Column.PasswordLastSet")] = [string]$row.PasswordLastSet
        $exportRows += [PSCustomObject]$exportRow
    }
    return $exportRows
}

function Convert-AccountPropertyRowsToExportRows {
    param([object[]]$Rows)

    $exportRows = @()
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $exportRow = [ordered]@{}
        $exportRow[(Get-UiText "Column.Attribute")] = [string]$row.Attribute
        $exportRow[(Get-UiText "Column.Value")] = [string]$row.Value
        $exportRow[(Get-UiText "Column.Count")] = [string]$row.Count
        $exportRows += [PSCustomObject]$exportRow
    }
    return $exportRows
}

function Convert-GroupRowsToExportRows {
    param([object[]]$Rows)

    $exportRows = @()
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $exportRow = [ordered]@{}
        $exportRow[(Get-UiText "Column.Name")] = [string]$row.Name
        $exportRow[(Get-UiText "Column.GroupLogin")] = [string]$row.SamAccountName
        $exportRow[(Get-UiText "Column.DisplayName")] = [string]$row.DisplayName
        $exportRow[(Get-UiText "Column.Type")] = [string]$row.Type
        $exportRow[(Get-UiText "Column.Scope")] = [string]$row.Scope
        $exportRow[(Get-UiText "Column.Source")] = [string]$row.Source
        $exportRow[(Get-UiText "Column.Description")] = [string]$row.Description
        $exportRows += [PSCustomObject]$exportRow
    }
    return $exportRows
}

function Convert-GroupMemberRowsToExportRows {
    param([object[]]$Rows)

    $exportRows = @()
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $exportRow = [ordered]@{}
        $exportRow[(Get-UiText "Column.Name")] = [string]$row.Name
        $exportRow[(Get-UiText "Column.Login")] = [string]$row.SamAccountName
        $exportRow[(Get-UiText "Column.DisplayName")] = [string]$row.DisplayName
        $exportRow[(Get-UiText "Column.Type")] = [string]$row.ObjectType
        $exportRow[(Get-UiText "Column.Enabled")] = [string]$row.Enabled
        $exportRow["UPN"] = [string]$row.UserPrincipalName
        $exportRow[(Get-UiText "Column.Description")] = [string]$row.Description
        $exportRows += [PSCustomObject]$exportRow
    }
    return $exportRows
}

function Get-SafeFileNamePart {
    param([string]$Text)

    if (Is-Blank $Text) { return (Get-UiText "Export.NoDataPart") }
    $safe = [regex]::Replace($Text.Trim(), '[\\/:*?"<>|]+', '_')
    $safe = [regex]::Replace($safe, '\s+', '_')
    $safe = $safe.Trim('_')
    if (Is-Blank $safe) { return (Get-UiText "Export.NoDataPart") }
    return $safe
}

function Export-ManagedAccountsToCsv {
    param([object[]]$Rows, [string]$Path)

    $exportRows = @(Convert-ManagedRowsToExportRows -Rows $Rows)
    if ($exportRows.Count -eq 0) { throw (Get-UiText "Error.ExportNoAccounts") }
    $exportRows | Export-Csv -Path $Path -NoTypeInformation -Delimiter ";" -Encoding UTF8 -Force
}

function Export-TabularRowsToCsv {
    param([object[]]$Rows, [string]$Path)

    $exportRows = @($Rows)
    if ($exportRows.Count -eq 0) { throw (Get-UiText "Error.ExportNoRows") }
    $exportRows | Export-Csv -Path $Path -NoTypeInformation -Delimiter ";" -Encoding UTF8 -Force
}

function Convert-ToExcelColumnName {
    param([int]$ColumnNumber)

    if ($ColumnNumber -lt 1) { throw (Get-UiText "Error.ExcelColumn" @($ColumnNumber)) }
    $name = ""
    $n = $ColumnNumber
    while ($n -gt 0) {
        $mod = ($n - 1) % 26
        $name = ([char](65 + $mod)) + $name
        $n = [math]::Floor(($n - $mod) / 26)
    }
    return $name
}

function Convert-ToXmlText {
    param([object]$Value)

    if ($null -eq $Value) { return "" }
    $text = [string]$Value
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $text.ToCharArray()) {
        $code = [int][char]$ch
        if (($code -eq 9) -or ($code -eq 10) -or ($code -eq 13) -or ($code -ge 32)) {
            [void]$sb.Append($ch)
        }
    }
    return [System.Security.SecurityElement]::Escape($sb.ToString())
}

function New-XlsxInlineStringCellXml {
    param([string]$CellRef, [object]$Value, [int]$StyleIndex = 0)

    $xmlText = Convert-ToXmlText -Value $Value
    $styleText = ""
    if ($StyleIndex -gt 0) { $styleText = " s=`"$StyleIndex`"" }
    $spaceText = ""
    $plainText = [string]$Value
    if ($plainText -match '^\s|\s$') { $spaceText = ' xml:space="preserve"' }
    return "<c r=`"$CellRef`" t=`"inlineStr`"$styleText><is><t$spaceText>$xmlText</t></is></c>"
}

function Write-Utf8NoBomFile {
    param([string]$Path, [string]$Content)
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Export-TabularRowsToXlsx {
    param(
        [object[]]$Rows,
        [string]$Path,
        [string]$SheetName,
        [int[]]$Widths
    )

    $exportRows = @($Rows)
    if ($exportRows.Count -eq 0) { throw (Get-UiText "Error.ExportNoRows") }

    $headers = @($exportRows[0].PSObject.Properties | ForEach-Object { $_.Name })
    if ($null -eq $Widths -or $Widths.Count -ne $headers.Count) {
        $Widths = @(for ($i = 0; $i -lt $headers.Count; $i++) { 24 })
    }
    $lastColumnName = Convert-ToExcelColumnName -ColumnNumber $headers.Count
    $lastRow = $exportRows.Count + 1
    $sheetRef = "A1:$lastColumnName$lastRow"
    $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "ADKombajn_xlsx_" + [guid]::NewGuid().ToString("N"))

    try {
        [void](New-Item -Path $tmp -ItemType Directory -Force)
        foreach ($dir in @("_rels", "docProps", "xl", "xl\_rels", "xl\worksheets")) {
            [void](New-Item -Path (Join-Path $tmp $dir) -ItemType Directory -Force)
        }

        $nowUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        $sheetNameXml = Convert-ToXmlText -Value $SheetName

        Write-Utf8NoBomFile -Path (Join-Path $tmp "[Content_Types].xml") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
"@

        Write-Utf8NoBomFile -Path (Join-Path $tmp "_rels\.rels") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
"@

        Write-Utf8NoBomFile -Path (Join-Path $tmp "docProps\core.xml") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:creator>ADKombajn</dc:creator>
  <cp:lastModifiedBy>ADKombajn</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">$nowUtc</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">$nowUtc</dcterms:modified>
</cp:coreProperties>
"@

        Write-Utf8NoBomFile -Path (Join-Path $tmp "docProps\app.xml") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>ADKombajn</Application>
</Properties>
"@

        Write-Utf8NoBomFile -Path (Join-Path $tmp "xl\workbook.xml") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="$sheetNameXml" sheetId="1" r:id="rId1"/></sheets>
</workbook>
"@

        Write-Utf8NoBomFile -Path (Join-Path $tmp "xl\_rels\workbook.xml.rels") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
"@

        Write-Utf8NoBomFile -Path (Join-Path $tmp "xl\styles.xml") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>
  <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1F4E78"/><bgColor indexed="64"/></patternFill></fill></fills>
  <borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFD9E2F3"/></left><right style="thin"><color rgb="FFD9E2F3"/></right><top style="thin"><color rgb="FFD9E2F3"/></top><bottom style="thin"><color rgb="FFD9E2F3"/></bottom><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>
"@

        $colsXml = New-Object System.Text.StringBuilder
        [void]$colsXml.AppendLine("  <cols>")
        for ($i = 0; $i -lt $Widths.Count; $i++) {
            $colNum = $i + 1
            [void]$colsXml.AppendLine("    <col min=`"$colNum`" max=`"$colNum`" width=`"$($Widths[$i])`" customWidth=`"1`"/>")
        }
        [void]$colsXml.AppendLine("  </cols>")

        $sheetData = New-Object System.Text.StringBuilder
        [void]$sheetData.AppendLine("  <sheetData>")
        [void]$sheetData.Append("    <row r=`"1`" ht=`"20`" customHeight=`"1`">")
        for ($i = 0; $i -lt $headers.Count; $i++) {
            $cellRef = (Convert-ToExcelColumnName -ColumnNumber ($i + 1)) + "1"
            [void]$sheetData.Append((New-XlsxInlineStringCellXml -CellRef $cellRef -Value $headers[$i] -StyleIndex 1))
        }
        [void]$sheetData.AppendLine("</row>")

        $rowNumber = 2
        foreach ($exportRow in $exportRows) {
            [void]$sheetData.Append("    <row r=`"$rowNumber`">")
            for ($i = 0; $i -lt $headers.Count; $i++) {
                $header = $headers[$i]
                $cellRef = (Convert-ToExcelColumnName -ColumnNumber ($i + 1)) + $rowNumber
                [void]$sheetData.Append((New-XlsxInlineStringCellXml -CellRef $cellRef -Value $exportRow.$header -StyleIndex 2))
            }
            [void]$sheetData.AppendLine("</row>")
            $rowNumber++
        }
        [void]$sheetData.AppendLine("  </sheetData>")

        Write-Utf8NoBomFile -Path (Join-Path $tmp "xl\worksheets\sheet1.xml") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <dimension ref="$sheetRef"/>
  <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft"/></sheetView></sheetViews>
  <sheetFormatPr defaultRowHeight="15"/>
$($colsXml.ToString())$($sheetData.ToString())  <autoFilter ref="$sheetRef"/>
  <pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>
</worksheet>
"@

        if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tmp, $Path)
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Export-ManagedAccountsToXlsx {
    param([object[]]$Rows, [string]$Path)

    $exportRows = @(Convert-ManagedRowsToExportRows -Rows $Rows)
    if ($exportRows.Count -eq 0) { throw (Get-UiText "Error.ExportNoAccounts") }
    Export-TabularRowsToXlsx `
        -Rows $exportRows `
        -Path $Path `
        -SheetName (Get-UiText "Export.SheetName") `
        -Widths @(18, 24, 28, 12, 34, 42, 22)
}

