# Shared TSV record reader for Localization.csv.
#
# Localization rows may contain quoted fields with embedded newlines, so records
# cannot be split per physical line. Each record keeps its own line terminator so
# existing rows can be re-emitted byte-for-byte and diffs stay minimal.

function Read-LocalizationRecords {
    param([Parameter(Mandatory)][string]$Path)

    $text = [System.IO.File]::ReadAllText($Path)
    $records = [System.Collections.Generic.List[object]]::new()
    $buffer = $null
    $startLine = 0
    $lineNo = 0

    $segments = $text -split "`n", 0, 'SimpleMatch'
    # A file ending with a newline yields a trailing empty segment. That is the end
    # of the last record, not a new record, so drop it before parsing.
    if ($segments.Count -gt 0 -and $segments[-1] -eq '') {
        $segments = $segments[0..($segments.Count - 2)]
    }

    foreach ($line in $segments) {
        $lineNo++
        if ($null -eq $buffer) { $buffer = $line; $startLine = $lineNo }
        else { $buffer = $buffer + "`n" + $line }

        if (([regex]::Matches($buffer, '"')).Count % 2 -ne 0) { continue }

        $body = $buffer
        $terminator = ''
        if ($body.EndsWith("`r`n")) { $terminator = "`r`n"; $body = $body.Substring(0, $body.Length - 2) }
        elseif ($body.EndsWith("`n")) { $terminator = "`n"; $body = $body.Substring(0, $body.Length - 1) }

        $fields = $body -split "`t"
        $records.Add([pscustomobject]@{
            Line    = $startLine
            Raw     = $buffer
            Body    = $body
            Term    = $terminator
            Key     = $fields[0]
            Type    = if ($fields.Count -ge 2) { $fields[1] } else { '' }
            Desc    = if ($fields.Count -ge 3) { $fields[2] } else { '' }
            Value   = if ($fields.Count -ge 4) { ConvertFrom-LocalizationField $fields[3] } else { '' }
            Fields  = $fields.Count
        })
        $buffer = $null
    }

    if ($null -ne $buffer) {
        $fields = $buffer -split "`t"
        $records.Add([pscustomobject]@{
            Line = $startLine; Raw = $buffer; Body = $buffer; Term = ''
            Key = $fields[0]
            Type = if ($fields.Count -ge 2) { $fields[1] } else { '' }
            Desc = if ($fields.Count -ge 3) { $fields[2] } else { '' }
            Value = if ($fields.Count -ge 4) { ConvertFrom-LocalizationField $fields[3] } else { '' }
            Fields = $fields.Count
        })
    }

    return , $records
}

function ConvertFrom-LocalizationField {
    param([string]$Raw)
    if ($null -eq $Raw) { return '' }
    if ($Raw.Length -ge 2 -and $Raw.StartsWith('"') -and $Raw.EndsWith('"')) {
        return ($Raw.Substring(1, $Raw.Length - 2) -replace '""', '"')
    }
    return $Raw
}

function ConvertTo-LocalizationField {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -match "[`t`n`r]" -or $Value.StartsWith('"')) {
        return '"' + ($Value -replace '"', '""') + '"'
    }
    return $Value
}

function Get-LocalizationAllowlist {
    param([Parameter(Mandatory)][string]$Path)
    $allow = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*(#|$)') { continue }
        $parts = $line -split "`t", 2
        if ($parts.Count -eq 2) { $allow[$parts[1].Trim()] = $parts[0].Trim() }
    }
    return $allow
}

function ConvertTo-CSharpStringLiteral {
    # Escapes a value so it can sit inside a C# "..." literal verbatim.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('"')
    foreach ($ch in $Value.ToCharArray()) {
        switch ($ch) {
            '\' { [void]$sb.Append('\\'); continue }
            '"' { [void]$sb.Append('\"'); continue }
            "`r" { [void]$sb.Append('\r'); continue }
            "`n" { [void]$sb.Append('\n'); continue }
            "`t" { [void]$sb.Append('\t'); continue }
            default { [void]$sb.Append($ch) }
        }
    }
    [void]$sb.Append('"')
    $sb.ToString()
}

function ConvertFrom-CSharpStringLiteral {
    param([Parameter(Mandatory)][string]$Literal)
    $sb = [System.Text.StringBuilder]::new()
    for ($i = 1; $i -lt $Literal.Length - 1; $i++) {
        $ch = $Literal[$i]
        if ($ch -ne '\') { [void]$sb.Append($ch); continue }
        $i++
        switch ($Literal[$i]) {
            '\' { [void]$sb.Append('\') }
            '"'  { [void]$sb.Append('"') }
            'r'  { [void]$sb.Append("`r") }
            'n'  { [void]$sb.Append("`n") }
            't'  { [void]$sb.Append("`t") }
            default { [void]$sb.Append($Literal[$i]) }
        }
    }
    $sb.ToString()
}

function Get-LocalizationKeyList {
    # Exact Key column of a localization file, in file order, header excluded.
    param([Parameter(Mandatory)][string]$Path)
    $records = Read-LocalizationRecords -Path $Path
    $keys = [System.Collections.Generic.List[string]]::new()
    foreach ($record in $records) {
        if ($record.Key -and $record.Key -ne 'Key') { $keys.Add($record.Key) }
    }
    $keys.ToArray()
}

function New-VietnameseKeysSource {
    # Deterministic C# source embedding the exact key set. Ordinal sort and LF
    # endings, so the same keys always produce byte-identical output.
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Keys)
    $sorted = [string[]]@($Keys)
    [Array]::Sort($sorted, [System.StringComparer]::Ordinal)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('// <auto-generated>')
    $lines.Add('// Generated by tools/Sync-Localization.ps1 from Localization/Localization.csv.')
    $lines.Add('// Do not edit by hand; tests/Test-LocalizationValidity.ps1 fails if this drifts from the CSV.')
    $lines.Add('// </auto-generated>')
    $lines.Add('namespace VietnameseCoreKeeper')
    $lines.Add('{')
    $lines.Add('    internal static class VietnameseKeys')
    $lines.Add('    {')
    $lines.Add("        internal static readonly string[] All = new string[$($sorted.Count)]")
    $lines.Add('        {')
    foreach ($key in $sorted) { $lines.Add('            ' + (ConvertTo-CSharpStringLiteral -Value $key) + ',') }
    $lines.Add('        };')
    $lines.Add('    }')
    $lines.Add('}')

    # LF endings keep the output byte-identical regardless of where it is generated.
    ($lines -join "`n") + "`n"
}

function Get-VietnameseKeysFromSource {
    # Parses the literals back out of a generated file so drift can be reported precisely.
    param([Parameter(Mandatory)][string]$Path)
    $keys = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $trimmed = $line.Trim()
        if (-not $trimmed.StartsWith('"')) { continue }
        $keys.Add((ConvertFrom-CSharpStringLiteral -Literal $trimmed.TrimEnd(',')))
    }
    $keys.ToArray()
}
