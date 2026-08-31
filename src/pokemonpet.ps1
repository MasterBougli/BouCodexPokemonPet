param(
    [string[]]$Stages = @('pichu-3d', 'pikachu-3d', 'raichu-3d'),
    [int[]]$EvolutionXp = @(0, 500, 2000),
    [int]$TokensPerXp = 100,
    [string]$DataRoot = (Join-Path $env:LOCALAPPDATA 'BouCodexPokemonPet'),
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$statePath = Join-Path $DataRoot 'state.json'
$configPath = Join-Path $DataRoot 'config.json'
$pidPath = Join-Path $DataRoot 'watcher.pid'
$stopPath = Join-Path $DataRoot 'stop-watcher'
$cacheRoot = Join-Path $DataRoot 'pets'
$assetBaseUrl = 'https://raw.githubusercontent.com/dnnyngyen/codex-pokepets/main/pets'
$codexRoot = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$sessionsPath = Join-Path $codexRoot 'sessions'
$installedPetPath = Join-Path (Join-Path $codexRoot 'pets') 'pokemonpet'

function Get-StageIndex([int]$Xp, [int[]]$Thresholds) {
    $index = 0
    for ($i = 0; $i -lt $Thresholds.Count; $i++) {
        if ($Xp -ge $Thresholds[$i]) { $index = $i }
    }
    return $index
}

function Get-XpFromUsage($Usage, [int]$Divisor) {
    $usefulTokens = [math]::Max(0, [int64]$Usage.input_tokens - [int64]$Usage.cached_input_tokens) + [int64]$Usage.output_tokens
    return [int][math]::Ceiling($usefulTokens / $Divisor)
}

function Get-XpProgressText([int]$Xp, [int[]]$Thresholds) {
    $next = @($Thresholds | Where-Object { $_ -gt $Xp } | Select-Object -First 1)
    if ($next.Count -eq 0) { return "$Xp XP - evolution finale" }
    $previous = @($Thresholds | Where-Object { $_ -le $Xp } | Select-Object -Last 1)[0]
    $range = [math]::Max(1, [int]$next[0] - [int]$previous)
    $filled = [math]::Min(10, [math]::Floor((($Xp - [int]$previous) / $range) * 10))
    $bar = ('#' * $filled) + ('-' * (10 - $filled))
    return "$Xp/$($next[0]) XP [$bar]"
}

function New-PokeballIcon {
    $bitmap = New-Object System.Drawing.Bitmap 32, 32
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $outlinePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), 3
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.FillEllipse([System.Drawing.Brushes]::White, 2, 2, 28, 28)
    $graphics.FillPie([System.Drawing.Brushes]::Red, 2, 2, 28, 28, 180, 180)
    $graphics.DrawEllipse($outlinePen, 2, 2, 28, 28)
    $graphics.DrawLine($outlinePen, 3, 16, 29, 16)
    $graphics.FillEllipse([System.Drawing.Brushes]::White, 11, 11, 10, 10)
    $graphics.DrawEllipse($outlinePen, 11, 11, 10, 10)
    $handle = $bitmap.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($handle).Clone()
    [void][NativeIcon]::DestroyIcon($handle)
    $outlinePen.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
    return $icon
}

function Get-CachedPet([string]$Slug) {
    $source = Join-Path $cacheRoot $Slug
    $metadata = Join-Path $source 'pet.json'
    $sheet = Join-Path $source 'spritesheet.webp'
    if (-not (Test-Path -LiteralPath $metadata) -or -not (Test-Path -LiteralPath $sheet)) {
        New-Item -ItemType Directory -Force -Path $source | Out-Null
        Invoke-WebRequest -UseBasicParsing -Uri "$assetBaseUrl/$Slug/pet.json" -OutFile $metadata
        Invoke-WebRequest -UseBasicParsing -Uri "$assetBaseUrl/$Slug/spritesheet.webp" -OutFile $sheet
    }
    return $source
}

function Set-PetMetadata([string]$Slug, [int]$Xp) {
    $source = Get-CachedPet $Slug
    $metadata = Get-Content -Raw -LiteralPath (Join-Path $source 'pet.json') | ConvertFrom-Json
    New-Item -ItemType Directory -Force -Path $installedPetPath | Out-Null
    [ordered]@{
        id = 'pokemonpet'
        displayName = "$($metadata.displayName) - $Xp XP"
        description = $metadata.description
        spritesheetPath = 'spritesheet.webp'
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $installedPetPath 'pet.json') -Encoding utf8
}

function Install-CurrentPet([string]$Slug, [int]$Xp) {
    $source = Get-CachedPet $Slug
    Set-PetMetadata $Slug $Xp
    Copy-Item -LiteralPath (Join-Path $source 'spritesheet.webp') -Destination (Join-Path $installedPetPath 'spritesheet.webp') -Force
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeIcon {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool DestroyIcon(IntPtr handle);
}
'@

if ($SelfTest) {
    if ((Get-StageIndex 499 @(0, 500, 2000)) -ne 0) { throw 'Stage test failed' }
    if ((Get-StageIndex 500 @(0, 500, 2000)) -ne 1) { throw 'Evolution test failed' }
    $usage = [pscustomobject]@{ input_tokens = 1200; cached_input_tokens = 1000; output_tokens = 101 }
    if ((Get-XpFromUsage $usage 100) -ne 4) { throw 'XP test failed' }
    if ((Get-XpProgressText 250 @(0, 500, 2000)) -ne '250/500 XP [#####-----]') { throw 'Progress test failed' }
    $testIcon = New-PokeballIcon
    if (-not $testIcon) { throw 'Tray icon test failed' }
    $testIcon.Dispose()
    Write-Output 'Self-test OK'
    exit 0
}

New-Item -ItemType Directory -Force -Path $DataRoot | Out-Null
Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $configPath) {
    $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    if (-not $PSBoundParameters.ContainsKey('Stages')) { $Stages = @($config.stages) }
    if (-not $PSBoundParameters.ContainsKey('EvolutionXp')) { $EvolutionXp = @($config.evolutionXp) }
    if (-not $PSBoundParameters.ContainsKey('TokensPerXp')) { $TokensPerXp = [int]$config.tokensPerXp }
}

if ($Stages.Count -ne $EvolutionXp.Count) { throw 'Stages et EvolutionXp doivent avoir la meme taille.' }
if ($TokensPerXp -lt 1) { throw 'TokensPerXp doit etre superieur a zero.' }
if (-not (Test-Path -LiteralPath $sessionsPath)) { throw "Sessions Codex introuvables : $sessionsPath" }

$state = if (Test-Path -LiteralPath $statePath) {
    Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
} else {
    [pscustomobject]@{ xp = 0; stage = -1 }
}

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$trayStatus = New-Object System.Windows.Forms.ToolStripMenuItem
$trayStatus.Enabled = $false
$openSettings = New-Object System.Windows.Forms.ToolStripMenuItem
$openSettings.Text = 'Ouvrir les reglages'
$quitWatcher = New-Object System.Windows.Forms.ToolStripMenuItem
$quitWatcher.Text = 'Quitter PokemonPet'
[void]$trayMenu.Items.Add($trayStatus)
[void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$trayMenu.Items.Add($openSettings)
[void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$trayMenu.Items.Add($quitWatcher)

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon = New-PokeballIcon
$trayIcon.ContextMenuStrip = $trayMenu
$trayIcon.Visible = $true
$openSelector = {
    $hostExe = (Get-Process -Id $PID).Path
    Start-Process -FilePath $hostExe -WindowStyle Normal -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f (Join-Path $PSScriptRoot 'pokemonpet-ui.ps1')),
        '-DataRoot', ('"{0}"' -f $DataRoot)
    ) | Out-Null
}
$openSettings.Add_Click($openSelector)
$trayIcon.Add_DoubleClick($openSelector)
$quitWatcher.Add_Click({ Set-Content -LiteralPath $stopPath -Value 'stop' -Encoding ascii })

$lineCounts = @{}
Get-ChildItem -LiteralPath $sessionsPath -Filter '*.jsonl' -File -Recurse | ForEach-Object {
    $lineCounts[$_.FullName] = @(Get-Content -LiteralPath $_.FullName).Count
}

Write-Output 'PokemonPet surveille maintenant les sessions Codex.'
Write-Output 'Dans Codex, choisissez "PokemonPet" dans Settings > Appearance > Pets.'
$displayedXp = -1
Set-Content -LiteralPath $pidPath -Value $PID -Encoding ascii

try {
    while (-not (Test-Path -LiteralPath $stopPath)) {
        $files = Get-ChildItem -LiteralPath $sessionsPath -Filter '*.jsonl' -File -Recurse |
            Where-Object { $_.LastWriteTimeUtc -gt [datetime]::UtcNow.AddMinutes(-10) }
        foreach ($file in $files) {
            $lines = @(Get-Content -LiteralPath $file.FullName)
            $start = if ($lineCounts.ContainsKey($file.FullName)) { $lineCounts[$file.FullName] } else { 0 }
            $nextCount = $lines.Count
            for ($i = $start; $i -lt $lines.Count; $i++) {
                try {
                    $record = $lines[$i] | ConvertFrom-Json
                    if ($record.type -eq 'event_msg' -and $record.payload.type -eq 'token_count' -and $record.payload.info.last_token_usage) {
                        $state.xp += Get-XpFromUsage $record.payload.info.last_token_usage $TokensPerXp
                    }
                } catch {
                    # ponytail: une ligne partielle est relue au passage suivant.
                    if ($i -eq $lines.Count - 1) { $nextCount = $i; break }
                }
            }
            $lineCounts[$file.FullName] = $nextCount
        }

        $stage = Get-StageIndex ([int]$state.xp) $EvolutionXp
        if ($stage -ne [int]$state.stage) {
            Install-CurrentPet $Stages[$stage] ([int]$state.xp)
            $state.stage = $stage
            Write-Output "Evolution active : $($Stages[$stage]) ($($state.xp) XP)"
        } elseif ($displayedXp -ne [int]$state.xp) {
            Set-PetMetadata $Stages[$stage] ([int]$state.xp)
        }
        $displayedXp = [int]$state.xp
        $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8
        $pokemonName = $Stages[$stage] -replace '-3d$', ''
        $progressText = Get-XpProgressText ([int]$state.xp) $EvolutionXp
        $trayStatus.Text = "$pokemonName - $progressText"
        $trayIcon.Text = "PokemonPet - $pokemonName - $($state.xp) XP".Substring(0, [math]::Min(63, "PokemonPet - $pokemonName - $($state.xp) XP".Length))
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 2
    }
} finally {
    $trayIcon.Visible = $false
    $trayIcon.Dispose()
    $trayMenu.Dispose()
    Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $pidPath) { Remove-Item -LiteralPath $pidPath -Force }
}
