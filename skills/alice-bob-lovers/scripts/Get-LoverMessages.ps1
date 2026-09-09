[CmdletBinding()]
param(
    [ValidateRange(1, 500)]
    [int]$Limit = 50,

    [switch]$UnreadOnly,
    [switch]$MarkRead
)

$ErrorActionPreference = 'Stop'

function Get-IdentityName {
    if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        throw 'CODEX_HOME est absent. Utilisez ce skill depuis Alice ou Bob.'
    }

    $path = [IO.Path]::GetFullPath($env:CODEX_HOME)
    if ($path -match '(?i)[\\/]Compte-1[\\/]codex[\\/]?$') { return 'Alice' }
    if ($path -match '(?i)[\\/]Compte-2[\\/]codex[\\/]?$') { return 'Bob' }
    throw "CODEX_HOME ne correspond ni a Alice ni a Bob : $path"
}

$identity = Get-IdentityName
$boardRoot = Join-Path $env:LOCALAPPDATA 'VSCode-Codex\conversation'
$messagesRoot = Join-Path $boardRoot 'messages'
$receiptsRoot = Join-Path $boardRoot ("receipts\$identity")
New-Item -ItemType Directory -Path $messagesRoot, $receiptsRoot -Force | Out-Null

$records = foreach ($file in Get-ChildItem -LiteralPath $messagesRoot -File -Filter '*.json' -ErrorAction SilentlyContinue) {
    try {
        $record = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $incoming = $record.to -eq $identity -or $record.to -eq 'Tous'
        $receipt = Join-Path $receiptsRoot ("$($record.id).seen")
        $isRead = Test-Path -LiteralPath $receipt
        if ($UnreadOnly -and (-not $incoming -or $isRead)) { continue }
        if ($MarkRead -and $incoming -and -not $isRead) {
            [IO.File]::WriteAllText($receipt, $record.created_at_utc, [Text.UTF8Encoding]::new($false))
            $isRead = $true
        }
        [pscustomobject]@{
            id = $record.id
            created_at_utc = $record.created_at_utc
            from = $record.from
            to = $record.to
            kind = $record.kind
            text = $record.text
            incoming = $incoming
            read = $isRead
        }
    }
    catch {
        Write-Warning "Message local illisible ignore : $($file.Name)"
    }
}

@($records | Sort-Object created_at_utc | Select-Object -Last $Limit) | ConvertTo-Json -Depth 5
