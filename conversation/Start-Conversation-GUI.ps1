[CmdletBinding()]
param([ValidateRange(1024, 65535)][int]$Port = 8765)

$ErrorActionPreference = 'Stop'
$url = "http://127.0.0.1:$Port/"
$health = "http://127.0.0.1:$Port/api/health"

function Test-Board {
    try {
        $result = Invoke-RestMethod -Uri $health -TimeoutSec 1
        return $result.ok -eq $true
    }
    catch { return $false }
}

try {
    if (-not (Test-Board)) {
        $python = Get-Command python.exe -ErrorAction SilentlyContinue
        if (-not $python) { $python = Get-Command py.exe -ErrorAction SilentlyContinue }
        if (-not $python) { throw 'Python est introuvable. La GUI locale ne peut pas demarrer.' }

        $logRoot = Join-Path $env:LOCALAPPDATA 'VSCode-Codex\logs'
        New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
        $stdoutPath = Join-Path $logRoot 'alice-bob-conversation.out.log'
        $stderrPath = Join-Path $logRoot 'alice-bob-conversation.err.log'
        $serverPath = Join-Path $PSScriptRoot 'server.py'
        $arguments = @('"' + $serverPath + '"', '--port', $Port)
        Start-Process -FilePath $python.Source -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

        $ready = $false
        foreach ($attempt in 1..20) {
            Start-Sleep -Milliseconds 250
            if (Test-Board) { $ready = $true; break }
        }
        if (-not $ready) { throw "Le serveur local n'a pas demarre. Consultez $stderrPath" }
    }

    Start-Process $url
}
catch {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show($_.Exception.Message, 'Alice & Bob - Erreur', 'OK', 'Error') | Out-Null
    exit 1
}
