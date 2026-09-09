[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Message,

    [ValidateSet('message', 'question', 'answer', 'status')]
    [string]$Kind = 'message'
)

$ErrorActionPreference = 'Stop'

function Get-Identity {
    if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        throw 'CODEX_HOME est absent. Utilisez ce skill depuis Alice ou Bob.'
    }

    $path = [IO.Path]::GetFullPath($env:CODEX_HOME)
    if ($path -match '(?i)[\\/]Compte-1[\\/]codex[\\/]?$') {
        return [pscustomobject]@{ Name = 'Alice'; Partner = 'Bob' }
    }
    if ($path -match '(?i)[\\/]Compte-2[\\/]codex[\\/]?$') {
        return [pscustomobject]@{ Name = 'Bob'; Partner = 'Alice' }
    }
    throw "CODEX_HOME ne correspond ni a Alice ni a Bob : $path"
}

$identity = Get-Identity
$boardRoot = Join-Path $env:LOCALAPPDATA 'VSCode-Codex\conversation'
$messagesRoot = Join-Path $boardRoot 'messages'
New-Item -ItemType Directory -Path $messagesRoot -Force | Out-Null

$id = [Guid]::NewGuid().ToString('N')
$record = [ordered]@{
    id             = $id
    created_at_utc = [DateTime]::UtcNow.ToString('o')
    from           = $identity.Name
    to             = $identity.Partner
    kind           = $Kind
    text           = $Message
}

$json = $record | ConvertTo-Json -Depth 4
$temporary = Join-Path $messagesRoot ('.{0}.tmp' -f $id)
$destination = Join-Path $messagesRoot ('{0}.json' -f $id)
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($temporary, $json, $utf8)
Move-Item -LiteralPath $temporary -Destination $destination

[pscustomobject]@{
    Sent = $true
    Id = $id
    From = $identity.Name
    To = $identity.Partner
    CreatedAtUtc = $record.created_at_utc
}
