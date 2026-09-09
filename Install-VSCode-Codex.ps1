[CmdletBinding()]
param(
    [switch]$SkipExtensionInstall,
    [switch]$SkipLaunchTest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$script:InstallRoot = Join-Path $env:LOCALAPPDATA 'VSCode-Codex'
$script:Desktop = [Environment]::GetFolderPath('DesktopDirectory')
$script:Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    # Windows PowerShell 5.1 exige un BOM pour decoder de facon fiable les
    # caracteres Unicode presents dans un script .ps1.
    $encoding = if ([IO.Path]::GetExtension($Path) -ieq '.ps1') { $script:Utf8Bom } else { $script:Utf8NoBom }
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Backup-And-Write {
    param([string]$Path, [string]$Content)

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $Path) {
        $current = [System.IO.File]::ReadAllText($Path)
        if ($current -ceq $Content) { return $false }
        Copy-Item -LiteralPath $Path -Destination ($Path + '.bak.' + $script:Timestamp) -Force
    }

    Write-Utf8File -Path $Path -Content $Content
    return $true
}

function Backup-And-WriteBytes {
    param([string]$Path, [byte[]]$Content)

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (Test-Path -LiteralPath $Path) {
        $current = [System.IO.File]::ReadAllBytes($Path)
        if ([Convert]::ToBase64String($current) -ceq [Convert]::ToBase64String($Content)) { return $false }
        Copy-Item -LiteralPath $Path -Destination ($Path + '.bak.' + $script:Timestamp) -Force
    }
    [System.IO.File]::WriteAllBytes($Path, $Content)
    return $true
}

function New-TintedVsCodeIcon {
    param(
        [string]$CodeExe,
        [string]$Destination,
        [ValidateSet('Cobalt', 'Red')][string]$Tint
    )

    Add-Type -AssemblyName System.Drawing
    $codeRoot = Split-Path -Parent $CodeExe
    $source = Get-ChildItem -LiteralPath $codeRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { Join-Path $_.FullName 'resources\app\resources\win32\code_150x150.png' } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if (-not $source) { throw 'Image source du logo VS Code introuvable.' }

    $original = [System.Drawing.Bitmap]::FromFile($source)
    try {
        # Le PNG livre avec VS Code comporte une marge transparente importante.
        # La rogner evite une icone minuscule dans l'Explorateur et la barre des taches.
        $left = $original.Width
        $top = $original.Height
        $right = -1
        $bottom = -1
        for ($y = 0; $y -lt $original.Height; $y++) {
            for ($x = 0; $x -lt $original.Width; $x++) {
                if ($original.GetPixel($x, $y).A -gt 8) {
                    if ($x -lt $left) { $left = $x }
                    if ($x -gt $right) { $right = $x }
                    if ($y -lt $top) { $top = $y }
                    if ($y -gt $bottom) { $bottom = $y }
                }
            }
        }
        if ($right -lt $left -or $bottom -lt $top) { throw 'Le logo VS Code source est entierement transparent.' }

        $cropWidth = $right - $left + 1
        $cropHeight = $bottom - $top + 1
        $frames = @()
        foreach ($size in 256, 64, 48, 32, 16) {
            $bitmap = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            try {
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                try {
                    $graphics.Clear([System.Drawing.Color]::Transparent)
                    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                    $maximum = [Math]::Max(1, [int][Math]::Floor($size * 0.96))
                    $scale = [Math]::Min($maximum / $cropWidth, $maximum / $cropHeight)
                    $drawWidth = [Math]::Max(1, [int][Math]::Round($cropWidth * $scale))
                    $drawHeight = [Math]::Max(1, [int][Math]::Round($cropHeight * $scale))
                    $drawX = [int][Math]::Floor(($size - $drawWidth) / 2)
                    $drawY = [int][Math]::Floor(($size - $drawHeight) / 2)
                    $destinationRectangle = New-Object System.Drawing.Rectangle $drawX, $drawY, $drawWidth, $drawHeight
                    $graphics.DrawImage($original, $destinationRectangle, $left, $top, $cropWidth, $cropHeight, [System.Drawing.GraphicsUnit]::Pixel)
                } finally {
                    $graphics.Dispose()
                }

                for ($pixelY = 0; $pixelY -lt $bitmap.Height; $pixelY++) {
                    for ($pixelX = 0; $pixelX -lt $bitmap.Width; $pixelX++) {
                        $pixel = $bitmap.GetPixel($pixelX, $pixelY)
                        if ($pixel.A -eq 0) { continue }
                        $luma = [int](0.299 * $pixel.R + 0.587 * $pixel.G + 0.114 * $pixel.B)
                        if ($Tint -eq 'Red') {
                            $red = [Math]::Min(255, [int](45 + 0.90 * $luma))
                            $green = [Math]::Min(255, [int](0.22 * $luma))
                            $blue = [Math]::Min(255, [int](0.20 * $luma))
                        } else {
                            # Cobalt profond, volontairement eloigne du bleu cyan VS Code d'origine.
                            $red = [Math]::Min(255, [int](18 + 0.18 * $luma))
                            $green = [Math]::Min(255, [int](42 + 0.36 * $luma))
                            $blue = [Math]::Min(255, [int](88 + 0.78 * $luma))
                        }
                        $bitmap.SetPixel($pixelX, $pixelY, [System.Drawing.Color]::FromArgb($pixel.A, $red, $green, $blue))
                    }
                }

                $pngStream = New-Object System.IO.MemoryStream
                try {
                    $bitmap.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
                    $frames += [PSCustomObject]@{ Size = $size; Bytes = $pngStream.ToArray() }
                } finally {
                    $pngStream.Dispose()
                }
            } finally {
                $bitmap.Dispose()
            }
        }

        $icoStream = New-Object System.IO.MemoryStream
        $writer = New-Object System.IO.BinaryWriter $icoStream
        try {
            $writer.Write([uint16]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]$frames.Count)
            $offset = 6 + (16 * $frames.Count)
            foreach ($frame in $frames) {
                $dimension = if ($frame.Size -eq 256) { [byte]0 } else { [byte]$frame.Size }
                $writer.Write($dimension)
                $writer.Write($dimension)
                $writer.Write([byte]0)
                $writer.Write([byte]0)
                $writer.Write([uint16]1)
                $writer.Write([uint16]32)
                $writer.Write([uint32]$frame.Bytes.Length)
                $writer.Write([uint32]$offset)
                $offset += $frame.Bytes.Length
            }
            foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Bytes) }
            $writer.Flush()
            $icoBytes = $icoStream.ToArray()
        } finally {
            $writer.Dispose()
            $icoStream.Dispose()
        }
        Backup-And-WriteBytes -Path $Destination -Content $icoBytes | Out-Null
    } finally {
        $original.Dispose()
    }
}

function Get-CodeInstallation {
    $localCandidate = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'
    $programFilesCandidate = Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe'
    $programFilesX86Candidate = if (${env:ProgramFiles(x86)}) {
        Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\Code.exe'
    }
    $command = Get-Command code -ErrorAction SilentlyContinue

    $candidates = @($localCandidate, $programFilesCandidate, $programFilesX86Candidate)
    if ($command) {
        $source = $command.Source
        if ([IO.Path]::GetExtension($source) -ieq '.cmd') {
            $sourceRoot = Split-Path (Split-Path $source -Parent) -Parent
            $candidates += (Join-Path $sourceRoot 'Code.exe')
        } elseif ([IO.Path]::GetExtension($source) -ieq '.exe') {
            $candidates += $source
        }
    }

    $codeExe = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $codeExe) {
        throw 'VS Code est introuvable dans les emplacements Windows usuels et via Get-Command code.'
    }
    $codeExe = (Resolve-Path -LiteralPath $codeExe).Path
    $codeRoot = Split-Path -Parent $codeExe

    $portableCandidates = @(
        (Join-Path $codeRoot 'data'),
        (Join-Path (Split-Path $codeRoot -Parent) 'data')
    ) | Select-Object -Unique
    $portable = $portableCandidates | Where-Object { Test-Path -LiteralPath $_ }
    if ($portable) {
        throw ('Mode portable VS Code detecte ({0}). Le dossier data existant ne sera pas modifie. Utilisez une installation Windows non portable ou retirez volontairement le mode portable avant de relancer.' -f ($portable -join ', '))
    }

    $codeCli = Join-Path $codeRoot 'bin\code.cmd'
    if (-not (Test-Path -LiteralPath $codeCli)) {
        if ($command -and (Test-Path -LiteralPath $command.Source)) {
            $codeCli = $command.Source
        } else {
            throw 'Le lanceur CLI de VS Code est introuvable.'
        }
    }

    [pscustomobject]@{
        CodeExe = $codeExe
        CodeCli = (Resolve-Path -LiteralPath $codeCli).Path
        Version = (Get-Item -LiteralPath $codeExe).VersionInfo.FileVersion
    }
}

function Remove-JsonComments {
    param([string]$Text)
    $builder = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    $lineComment = $false
    $blockComment = $false

    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }

        if ($lineComment) {
            if ($c -eq "`r" -or $c -eq "`n") {
                $lineComment = $false
                [void]$builder.Append($c)
            }
            continue
        }
        if ($blockComment) {
            if ($c -eq '*' -and $next -eq '/') {
                $blockComment = $false
                $i++
            } elseif ($c -eq "`r" -or $c -eq "`n") {
                [void]$builder.Append($c)
            }
            continue
        }
        if ($inString) {
            [void]$builder.Append($c)
            if ($escaped) { $escaped = $false; continue }
            if ($c -eq '\') { $escaped = $true; continue }
            if ($c -eq '"') { $inString = $false }
            continue
        }
        if ($c -eq '"') {
            $inString = $true
            [void]$builder.Append($c)
            continue
        }
        if ($c -eq '/' -and $next -eq '/') {
            $lineComment = $true
            $i++
            continue
        }
        if ($c -eq '/' -and $next -eq '*') {
            $blockComment = $true
            $i++
            continue
        }
        [void]$builder.Append($c)
    }

    $withoutComments = $builder.ToString()
    return [regex]::Replace($withoutComments, ',(?=\s*[}\]])', '')
}

function Set-ObjectProperty {
    param($Object, [string]$Name, $Value)
    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        $property.Value = $Value
    } else {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Merge-Settings {
    param(
        [string]$Path,
        [string]$Theme,
        [string]$WindowTitle,
        [hashtable]$Colors
    )

    if (Test-Path -LiteralPath $Path) {
        $raw = [System.IO.File]::ReadAllText($Path)
        try {
            $clean = Remove-JsonComments -Text $raw
            $settings = $clean | ConvertFrom-Json
        } catch {
            throw "Le fichier JSON/JSONC ne peut pas etre fusionne: $Path. Erreur: $($_.Exception.Message)"
        }
        if ($null -eq $settings) { $settings = [pscustomobject][ordered]@{} }
    } else {
        $settings = [pscustomobject][ordered]@{}
    }

    Set-ObjectProperty $settings 'workbench.colorTheme' $Theme
    Set-ObjectProperty $settings 'window.titleBarStyle' 'custom'
    Set-ObjectProperty $settings 'window.title' $WindowTitle
    Set-ObjectProperty $settings 'window.autoDetectColorScheme' $false
    Set-ObjectProperty $settings 'chatgpt.runCodexInWindowsSubsystemForLinux' $false

    $colorProperty = $settings.PSObject.Properties['workbench.colorCustomizations']
    if ($colorProperty -and $colorProperty.Value -is [pscustomobject]) {
        $colorObject = $colorProperty.Value
    } else {
        $colorObject = [pscustomobject][ordered]@{}
        Set-ObjectProperty $settings 'workbench.colorCustomizations' $colorObject
    }
    foreach ($entry in $Colors.GetEnumerator()) {
        Set-ObjectProperty $colorObject $entry.Key $entry.Value
    }

    $json = $settings | ConvertTo-Json -Depth 20
    Backup-And-Write -Path $Path -Content ($json + [Environment]::NewLine) | Out-Null
}

function Merge-TomlRootValue {
    param([string]$Text, [string]$Key, [string]$TomlValue)
    $lines = @($Text -split "`r?`n")
    $tableIndex = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[') { $tableIndex = $i; break }
    }

    $matched = $false
    for ($i = 0; $i -lt $tableIndex; $i++) {
        if ($lines[$i] -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
            $lines[$i] = "$Key = $TomlValue"
            $matched = $true
            break
        }
    }
    if (-not $matched) {
        $before = if ($tableIndex -gt 0) { @($lines[0..($tableIndex - 1)]) } else { @() }
        $after = if ($tableIndex -lt $lines.Count) { @($lines[$tableIndex..($lines.Count - 1)]) } else { @() }
        $lines = @($before + "$Key = $TomlValue" + $after)
    }
    return (($lines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine)
}

function Merge-CodexConfig {
    param([string]$Path)
    $text = if (Test-Path -LiteralPath $Path) { [System.IO.File]::ReadAllText($Path) } else { '' }
    $text = Merge-TomlRootValue -Text $text -Key 'cli_auth_credentials_store' -TomlValue '"file"'
    $text = Merge-TomlRootValue -Text $text -Key 'forced_login_method' -TomlValue '"chatgpt"'
    Backup-And-Write -Path $Path -Content $text | Out-Null
}

function Invoke-CodeCli {
    param([string[]]$Arguments)
    $savedElectron = $env:ELECTRON_RUN_AS_NODE
    $savedIpc = $env:VSCODE_IPC_HOOK_CLI
    $savedNodeOptions = $env:NODE_OPTIONS
    $savedErrorPreference = $ErrorActionPreference
    try {
        Remove-Item Env:VSCODE_IPC_HOOK_CLI -ErrorAction SilentlyContinue
        # Conserve la verification TLS et ajoute le magasin de certificats
        # Windows, necessaire sur certains reseaux avec proxy d'entreprise.
        $env:NODE_OPTIONS = if ($savedNodeOptions) { "$savedNodeOptions --use-system-ca" } else { '--use-system-ca' }
        # Windows PowerShell 5.1 convertit parfois stderr d'un programme natif en
        # NativeCommandError. Le code de sortie de la CLI reste le critere fiable.
        $ErrorActionPreference = 'Continue'
        $output = & $script:Code.CodeCli @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $savedErrorPreference
        if ($exitCode -ne 0) {
            throw "La CLI VS Code a retourne $exitCode. Sortie: $($output -join ' ')"
        }
        return @($output)
    } finally {
        $ErrorActionPreference = $savedErrorPreference
        if ($null -eq $savedElectron) { Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue } else { $env:ELECTRON_RUN_AS_NODE = $savedElectron }
        if ($null -eq $savedIpc) { Remove-Item Env:VSCODE_IPC_HOOK_CLI -ErrorAction SilentlyContinue } else { $env:VSCODE_IPC_HOOK_CLI = $savedIpc }
        if ($null -eq $savedNodeOptions) { Remove-Item Env:NODE_OPTIONS -ErrorAction SilentlyContinue } else { $env:NODE_OPTIONS = $savedNodeOptions }
    }
}

function New-OrUpdateShortcut {
    param(
        [string]$Path,
        [string]$Target,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$Description,
        [string]$IconLocation
    )

    $shell = New-Object -ComObject WScript.Shell
    if (Test-Path -LiteralPath $Path) {
        $existing = $shell.CreateShortcut($Path)
        $ours = ($existing.Description -like 'VSCode-Codex:*') -or ($existing.Arguments -like ('*' + [IO.Path]::GetFileName($script:LauncherPath) + '*'))
        if (-not $ours) {
            throw "Le raccourci existe deja mais ne semble pas appartenir a cette installation: $Path"
        }
    }
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $Target
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = $Description
    $shortcut.IconLocation = $IconLocation
    # PowerShell est deja cache par -WindowStyle Hidden. Le raccourci reste en
    # mode normal pour que la fenetre VS Code enfant ne demarre pas minimisee.
    $shortcut.WindowStyle = 1
    $shortcut.Save()
}

$script:Code = Get-CodeInstallation
$requirements = Join-Path $env:ProgramData 'OpenAI\Codex\requirements.toml'
$requirementsSummary = 'absent'
if (Test-Path -LiteralPath $requirements) {
    $policyLines = Get-Content -LiteralPath $requirements | Where-Object {
        $_ -match '^\s*(allowed_login_methods|cli_auth_credentials_store|allowed_chatgpt_workspaces|chatgpt_base_url)\s*='
    }
    $requirementsSummary = if ($policyLines) { $policyLines -join '; ' } else { 'present, aucune contrainte d authentification detectee par le controle cible' }
    if ($policyLines -match 'allowed_login_methods\s*=\s*\[[^\]]*"api"[^\]]*\]' -and $policyLines -notmatch '"chatgpt"') {
        throw "Une politique administrateur semble interdire la connexion ChatGPT: $requirements"
    }
    if ($policyLines -match 'cli_auth_credentials_store\s*=\s*"(keyring|ephemeral)"') {
        throw "Une politique administrateur impose un stockage incompatible avec auth.json: $requirements"
    }
}

$directories = @(
    $script:InstallRoot,
    (Join-Path $script:InstallRoot 'Compte-1\vscode\User'),
    (Join-Path $script:InstallRoot 'Compte-1\extensions'),
    (Join-Path $script:InstallRoot 'Compte-1\codex'),
    (Join-Path $script:InstallRoot 'Compte-2\vscode\User'),
    (Join-Path $script:InstallRoot 'Compte-2\extensions'),
    (Join-Path $script:InstallRoot 'Compte-2\codex'),
    (Join-Path $script:InstallRoot 'lanceurs'),
    (Join-Path $script:InstallRoot 'configuration'),
    (Join-Path $script:InstallRoot 'logs')
)
foreach ($directory in $directories) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

$projectConfigPath = Join-Path $script:InstallRoot 'configuration\projets.json'
if (-not (Test-Path -LiteralPath $projectConfigPath)) {
    $projectConfig = [ordered]@{ 'Compte-1' = ''; 'Compte-2' = '' } | ConvertTo-Json
    Write-Utf8File -Path $projectConfigPath -Content ($projectConfig + [Environment]::NewLine)
}

$blueColors = @{
    'titleBar.activeBackground' = '#123A63'
    'titleBar.activeForeground' = '#FFFFFF'
    'titleBar.inactiveBackground' = '#0D2947'
    'titleBar.inactiveForeground' = '#B8D5EE'
    'titleBar.border' = '#42A5F5'
    'statusBar.background' = '#1565C0'
    'statusBar.foreground' = '#FFFFFF'
    'statusBar.noFolderBackground' = '#0F4C8A'
    'statusBar.border' = '#42A5F5'
    'activityBar.background' = '#10263D'
    'activityBar.foreground' = '#FFFFFF'
    'activityBar.inactiveForeground' = '#B8D5EE'
    'activityBar.activeBorder' = '#42A5F5'
    'focusBorder' = '#42A5F5'
}
$redColors = @{
    'titleBar.activeBackground' = '#5A1515'
    'titleBar.activeForeground' = '#FFFFFF'
    'titleBar.inactiveBackground' = '#3A1010'
    'titleBar.inactiveForeground' = '#FFCDD2'
    'titleBar.border' = '#EF5350'
    'statusBar.background' = '#C62828'
    'statusBar.foreground' = '#FFFFFF'
    'statusBar.noFolderBackground' = '#8E1B1B'
    'statusBar.border' = '#EF5350'
    'activityBar.background' = '#2B1010'
    'activityBar.foreground' = '#FFFFFF'
    'activityBar.inactiveForeground' = '#FFB3B3'
    'activityBar.activeBorder' = '#EF5350'
    'focusBorder' = '#EF5350'
    'button.background' = '#C62828'
    'button.hoverBackground' = '#E53935'
    'progressBar.background' = '#EF5350'
    'badge.background' = '#C62828'
    'textLink.foreground' = '#FF6B6B'
}

Merge-Settings -Path (Join-Path $script:InstallRoot 'Compte-1\vscode\User\settings.json') -Theme 'Dark Modern' -WindowTitle 'CODEX — ALICE — BLEU — ${rootName}' -Colors $blueColors
Merge-Settings -Path (Join-Path $script:InstallRoot 'Compte-2\vscode\User\settings.json') -Theme 'Visual Studio Dark' -WindowTitle 'CODEX — BOB — ROUGE — ${rootName}' -Colors $redColors
Merge-CodexConfig -Path (Join-Path $script:InstallRoot 'Compte-1\codex\config.toml')
Merge-CodexConfig -Path (Join-Path $script:InstallRoot 'Compte-2\codex\config.toml')

$script:LauncherPath = Join-Path $script:InstallRoot 'lanceurs\Start-VSCode-Codex.ps1'
$launcherContent = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(1, 2)]
    [int]$Compte,
    [switch]$ProbeOnly
)

$ErrorActionPreference = 'Stop'

function Quote-NativeArgument {
    param([string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Show-LaunchError {
    param([string]$Message)
    try {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show($Message, 'VSCode-Codex - Erreur', 'OK', 'Error') | Out-Null
    } catch {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show($Message, 'VSCode-Codex - Erreur', 'OK', 'Error') | Out-Null
        } catch {}
    }
}

try {
    $root = Split-Path $PSScriptRoot -Parent
    $accountName = "Compte-$Compte"
    $displayName = if ($Compte -eq 1) { 'Alice — Bleu' } else { 'Bob — Rouge' }
    $accountRoot = Join-Path $root $accountName
    $userData = Join-Path $accountRoot 'vscode'
    $extensions = Join-Path $accountRoot 'extensions'
    $codexHome = Join-Path $accountRoot 'codex'
    $installConfigPath = Join-Path $root 'configuration\installation.json'
    $projectConfigPath = Join-Path $root 'configuration\projets.json'
    $logPath = Join-Path $root ("logs\lancement-compte-{0}.log" -f $Compte)

    foreach ($required in @($userData, $extensions, $codexHome, $installConfigPath, $projectConfigPath)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Element requis introuvable: $required" }
    }

    $installConfig = Get-Content -LiteralPath $installConfigPath -Raw | ConvertFrom-Json
    $codeExe = [string]$installConfig.CodeExe
    if (-not (Test-Path -LiteralPath $codeExe)) { throw "Executable VS Code introuvable: $codeExe" }

    $activeUpdater = @(Get-Process -Name 'CodeSetup-stable-*' -ErrorAction SilentlyContinue)
    if (-not $ProbeOnly -and $activeUpdater.Count -gt 0) {
        throw "Une mise a jour VS Code est en cours et bloque temporairement toute nouvelle instance. Ne forcez pas son arret. Lorsque vous pourrez fermer vos fenetres VS Code habituelles, laissez la mise a jour se terminer, puis relancez ce raccourci."
    }

    $projectConfig = Get-Content -LiteralPath $projectConfigPath -Raw | ConvertFrom-Json
    $projectProperty = $projectConfig.PSObject.Properties[$accountName]
    $projectPath = if ($projectProperty) { [string]$projectProperty.Value } else { '' }
    if ($projectPath -and -not (Test-Path -LiteralPath $projectPath)) {
        throw "Le projet configure pour $accountName n'existe pas: $projectPath. Corrigez configuration\projets.json ou laissez la valeur vide."
    }

    $env:CODEX_HOME = $codexHome
    Remove-Item Env:VSCODE_IPC_HOOK_CLI -ErrorAction SilentlyContinue
    Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue

    if ($ProbeOnly) {
        $probeScript = Join-Path $root 'configuration\Test-ChildEnvironment.ps1'
        $probeOutput = Join-Path $root ("logs\probe-environnement-compte-{0}.json" -f $Compte)
        $powerShellExe = Join-Path $PSHOME 'powershell.exe'
        $probeArgs = @(
            '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', (Quote-NativeArgument $probeScript),
            '-OutputPath', (Quote-NativeArgument $probeOutput)
        )
        $probeProcess = Start-Process -FilePath $powerShellExe -ArgumentList $probeArgs -Wait -PassThru
        if ($probeProcess.ExitCode -ne 0) { throw "Le test d'heritage CODEX_HOME a echoue avec le code $($probeProcess.ExitCode)." }
        return
    }

    $arguments = @(
        '--user-data-dir', (Quote-NativeArgument $userData),
        '--extensions-dir', (Quote-NativeArgument $extensions),
        '--new-window',
        '--sync', 'off'
    )
    if ($projectPath) { $arguments += (Quote-NativeArgument $projectPath) }

    $process = Start-Process -FilePath $codeExe -ArgumentList $arguments -WorkingDirectory $accountRoot -PassThru
    $safeLog = '{0} compte={1} nom={2} pid={3} CODEX_HOME={4} user-data-dir={5} extensions-dir={6}' -f (Get-Date -Format 's'), $Compte, $displayName, $process.Id, $codexHome, $userData, $extensions
    Add-Content -LiteralPath $logPath -Value $safeLog -Encoding UTF8
} catch {
    $friendlyName = if ($Compte -eq 1) { 'Alice — Bleu' } else { 'Bob — Rouge' }
    $message = "Impossible de lancer Codex — $friendlyName.`r`n`r`n$($_.Exception.Message)`r`n`r`nConsultez le dossier logs de VSCode-Codex."
    try {
        $fallbackRoot = Split-Path $PSScriptRoot -Parent
        Add-Content -LiteralPath (Join-Path $fallbackRoot 'logs\erreurs-lancement.log') -Value ('{0} compte={1} erreur={2}' -f (Get-Date -Format 's'), $Compte, $_.Exception.Message) -Encoding UTF8
    } catch {}
    Show-LaunchError -Message $message
    exit 1
}
'@
Backup-And-Write -Path $script:LauncherPath -Content $launcherContent | Out-Null

$probePath = Join-Path $script:InstallRoot 'configuration\Test-ChildEnvironment.ps1'
$probeContent = @'
param([Parameter(Mandatory = $true)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
$result = [ordered]@{
    CODEX_HOME = $env:CODEX_HOME
    VSCODE_IPC_HOOK_CLI = $env:VSCODE_IPC_HOOK_CLI
    ELECTRON_RUN_AS_NODE = $env:ELECTRON_RUN_AS_NODE
    ProcessId = $PID
}
$json = $result | ConvertTo-Json
[System.IO.File]::WriteAllText($OutputPath, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
'@
Backup-And-Write -Path $probePath -Content $probeContent | Out-Null

$installationPath = Join-Path $script:InstallRoot 'configuration\installation.json'
$installation = [ordered]@{
    CodeExe = $script:Code.CodeExe
    CodeCli = $script:Code.CodeCli
    CodeVersion = $script:Code.Version
    InstallRoot = $script:InstallRoot
    Desktop = $script:Desktop
    ExtensionId = 'openai.chatgpt'
    RequirementsPath = $requirements
    RequirementsSummary = $requirementsSummary
    LastMaintenance = (Get-Date).ToString('o')
} | ConvertTo-Json
Backup-And-Write -Path $installationPath -Content ($installation + [Environment]::NewLine) | Out-Null

$selfDestination = Join-Path $script:InstallRoot 'configuration\Install-VSCode-Codex.ps1'
$selfContent = [System.IO.File]::ReadAllText($MyInvocation.MyCommand.Path)
Backup-And-Write -Path $selfDestination -Content $selfContent | Out-Null

if (-not $SkipExtensionInstall) {
    foreach ($account in 1, 2) {
        $userData = Join-Path $script:InstallRoot "Compte-$account\vscode"
        $extensions = Join-Path $script:InstallRoot "Compte-$account\extensions"
        $installOutput = Invoke-CodeCli -Arguments @(
            '--user-data-dir', $userData,
            '--extensions-dir', $extensions,
            '--install-extension', 'openai.chatgpt'
        )
        Write-Utf8File -Path (Join-Path $script:InstallRoot "logs\installation-extension-compte-$account.log") -Content (($installOutput -join [Environment]::NewLine) + [Environment]::NewLine)
    }
}

$powerShellTarget = Join-Path $PSHOME 'powershell.exe'
$blueIconPath = Join-Path $script:InstallRoot 'configuration\icons\VSCode-Alice-Cobalt.ico'
$redIconPath = Join-Path $script:InstallRoot 'configuration\icons\VSCode-Bob-Rouge-v2.ico'
New-TintedVsCodeIcon -CodeExe $script:Code.CodeExe -Destination $blueIconPath -Tint Cobalt
New-TintedVsCodeIcon -CodeExe $script:Code.CodeExe -Destination $redIconPath -Tint Red
$controlReportPath = Join-Path $script:InstallRoot 'logs\compte-rendu-controles.md'
if (Test-Path -LiteralPath $controlReportPath) {
    $reportContent = [System.IO.File]::ReadAllText($controlReportPath, [System.Text.Encoding]::UTF8)
    $updatedReportContent = [System.Text.RegularExpressions.Regex]::Replace(
        $reportContent,
        '(?m)^- Bob utilise .*Alice conserve.*$',
        '- Alice et Bob utilisent chacun une icone personnalisee multi-resolution (256, 64, 48, 32 et 16 px), recadree a 96 % du canevas : bleu cobalt distinct du bleu VS Code d''origine pour Alice, rouge pour Bob.'
    )
    if ($updatedReportContent -cne $reportContent) {
        Backup-And-Write -Path $controlReportPath -Content $updatedReportContent | Out-Null
    }
}
$legacyShortcutArchive = Join-Path $script:InstallRoot 'configuration\anciens-raccourcis'
foreach ($account in 1, 2) {
    $displayName = if ($account -eq 1) { 'Alice' } else { 'Bob' }
    $colorName = if ($account -eq 1) { 'Bleu' } else { 'Rouge' }
    $shortcutName = "Codex - $displayName - $colorName.lnk"
    $shortcutPath = Join-Path $script:Desktop $shortcutName
    $legacyName = if ($account -eq 1) { 'Codex - Compte 1 - Bleu.lnk' } else { 'Codex - Compte 2 - Violet.lnk' }
    $legacyPath = Join-Path $script:Desktop $legacyName
    if ((Test-Path -LiteralPath $legacyPath) -and ($legacyPath -ne $shortcutPath)) {
        $shell = New-Object -ComObject WScript.Shell
        $legacy = $shell.CreateShortcut($legacyPath)
        if (($legacy.Description -like 'VSCode-Codex:*') -or ($legacy.Arguments -like '*Start-VSCode-Codex.ps1*')) {
            if (-not (Test-Path -LiteralPath $shortcutPath)) {
                Move-Item -LiteralPath $legacyPath -Destination $shortcutPath
            } else {
                New-Item -ItemType Directory -Path $legacyShortcutArchive -Force | Out-Null
                Move-Item -LiteralPath $legacyPath -Destination (Join-Path $legacyShortcutArchive ($legacyName + '.' + $script:Timestamp))
            }
        }
    }
    $shortcutArguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Compte {1}' -f $script:LauncherPath, $account
    $iconLocation = if ($account -eq 1) { $blueIconPath + ',0' } else { $redIconPath + ',0' }
    New-OrUpdateShortcut -Path $shortcutPath -Target $powerShellTarget -Arguments $shortcutArguments -WorkingDirectory (Join-Path $script:InstallRoot "Compte-$account") -Description "VSCode-Codex: environnement $displayName - $colorName, donnees et authentification separees" -IconLocation $iconLocation
}

$readmePath = Join-Path $script:InstallRoot 'README-installation.md'
$readme = @'
# Deux environnements VS Code Codex separes

Cette installation ajoute deux instances Windows natives independantes sans modifier le VS Code habituel, `%APPDATA%\Code`, `%USERPROFILE%\.codex`, les projets, Git ou GitHub.

## Raccourcis

- `Codex - Alice - Bleu.lnk` ouvre l'environnement **Alice — Bleu** avec `Compte-1\vscode`, `Compte-1\extensions` et `Compte-1\codex`. Son raccourci utilise une grande icone VS Code recoloree en bleu cobalt, distincte du bleu VS Code d'origine.
- `Codex - Bob - Rouge.lnk` ouvre l'environnement **Bob — Rouge** avec `Compte-2\vscode`, `Compte-2\extensions` et `Compte-2\codex`. Son raccourci utilise une grande icone VS Code filtree en rouge.

Les deux icones personnalisees sont stockees dans `configuration\icons` et contiennent plusieurs resolutions pour rester bien dimensionnees sur le Bureau et dans l'Explorateur.

Les lanceurs definissent `CODEX_HOME` uniquement dans leur propre processus et ses enfants, retirent localement `VSCODE_IPC_HOOK_CLI` et `ELECTRON_RUN_AS_NODE`, puis lancent VS Code avec `--user-data-dir`, `--extensions-dir`, `--new-window` et `--sync off`. Ils n'installent rien au lancement quotidien.

## Connexion des deux comptes

1. Ouvrez uniquement le raccourci **Alice — Bleu**.
2. Dans l'extension Codex, choisissez **Sign in with ChatGPT**. Dans le navigateur, verifiez l'adresse ou l'avatar du compte 1 et le bon espace de travail avant de valider.
3. Revenez dans la fenetre bleue. Ouvrez le menu de profil de Codex et verifiez le compte actif. Terminez cette connexion avant de continuer.
4. Ouvrez ensuite le raccourci **Bob — Rouge** et recommencez avec le compte 2, apres avoir controle l'identite dans le navigateur.
5. Dans chaque fenetre, reouvrez le menu de profil Codex pour comparer explicitement les identites et espaces de travail.

Ne communiquez jamais mot de passe, code de validation ou jeton. Apres connexion, `Compte-1\codex\auth.json` et `Compte-2\codex\auth.json` sont attendus. Ne les ouvrez pas et ne les partagez pas. Leur presence seule ne prouve pas que deux comptes differents sont connectes; l'identite affichee dans chaque interface fait foi.

## Choisir ou changer les projets

Editez `configuration\projets.json`. Chaque valeur peut rester vide pour ouvrir une fenetre sans projet, ou contenir un chemin Windows reel, par exemple :

```json
{
  "Compte-1": "D:\\Travail\\Projet-A",
  "Compte-2": "D:\\Travail\\Projet-B"
}
```

Fermez seulement la fenetre concernee si vous le souhaitez, modifiez le fichier, puis utilisez son raccourci. Les chemins d'exemple ne sont jamais crees. Pour un projet WSL, ouvrez-le manuellement avec la fonctionnalite Remote - WSL adaptee; ne remplacez pas un chemin Linux par un chemin Windows invente.

## Verifier la separation

Dans le terminal PowerShell integre de chaque fenetre, executez :

```powershell
$env:CODEX_HOME
```

Alice doit afficher `Compte-1\codex` et Bob `Compte-2\codex`. Cette commande confirme la variable heritee, pas a elle seule le stockage effectivement utilise par l'extension. Si l'extension propose d'ouvrir sa configuration, verifiez que `config.toml` vient du meme dossier. Les donnees VS Code, extensions et Codex doivent pointer vers trois dossiers propres a chaque compte.

Les titres `CODEX — ALICE — BLEU` et `CODEX — BOB — ROUGE` identifient les environnements; ils ne prouvent pas quel compte est connecte.

## Ajouter une extension a un seul environnement

Depuis PowerShell, adaptez le compte puis executez la CLI detectee dans `configuration\installation.json` :

```powershell
& 'C:\chemin\vers\code.cmd' --user-data-dir "$env:LOCALAPPDATA\VSCode-Codex\Compte-1\vscode" --extensions-dir "$env:LOCALAPPDATA\VSCode-Codex\Compte-1\extensions" --install-extension editeur.extension
```

Remplacez `Compte-1` par `Compte-2` pour l'autre environnement. Ne copiez jamais `globalStorage`, cookies, jetons ou `auth.json` entre les comptes.

## Maintenance reexecutable

Relancez `configuration\Install-VSCode-Codex.ps1`. Le script detecte de nouveau VS Code, fusionne les reglages geres, sauvegarde un fichier avant changement, met a jour les raccourcis de cette installation et verifie l'extension dans chaque dossier. Il ne supprime pas `auth.json` et ne reinitialise pas les connexions.

## Retirer cette installation

Avant toute suppression, sauvegardez ce que vous voulez conserver et sachez que supprimer `Compte-1\codex` ou `Compte-2\codex` efface les historiques et les connexions Codex de l'environnement concerne. Fermez d'abord uniquement les deux fenetres de cette installation. Supprimez ensuite manuellement les deux raccourcis portant les noms ci-dessus, puis `%LOCALAPPDATA%\VSCode-Codex`. Ne supprimez pas vos projets, `%APPDATA%\Code` ni `%USERPROFILE%\.codex`.

## Limite de l'isolation

Cette separation isole les donnees VS Code, les extensions et les caches Codex, mais ce n'est pas une isolation de securite entre deux machines ou deux comptes Windows. Les deux environnements s'executent sous le meme utilisateur Windows et peuvent acceder aux autres fichiers auxquels cet utilisateur a acces.
'@
Backup-And-Write -Path $readmePath -Content $readme | Out-Null

if (-not $SkipLaunchTest) {
    foreach ($account in 1, 2) {
        & $script:LauncherPath -Compte $account -ProbeOnly
    }
}

Write-Output "Installation terminee dans $script:InstallRoot"
Write-Output "Bureau detecte: $script:Desktop"
Write-Output "VS Code: $($script:Code.CodeExe) ($($script:Code.Version))"
