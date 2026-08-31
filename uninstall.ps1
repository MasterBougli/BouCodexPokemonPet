param(
    [string]$DataRoot = (Join-Path $env:LOCALAPPDATA 'BouCodexPokemonPet'),
    [switch]$KeepProgress,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if (-not $Force) {
    $answer = Read-Host 'Supprimer PokemonPet de Codex et du demarrage automatique ? (o/N)'
    if ($answer -notmatch '^(o|oui|y|yes)$') { exit 0 }
}

$pidPath = Join-Path $DataRoot 'watcher.pid'
if (Test-Path -LiteralPath $pidPath) {
    $watcherPid = [int](Get-Content -Raw -LiteralPath $pidPath)
    Stop-Process -Id $watcherPid -Force -ErrorAction SilentlyContinue
}
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'PokemonPet' -ErrorAction SilentlyContinue
$codexRoot = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
Remove-Item -LiteralPath (Join-Path (Join-Path $codexRoot 'pets') 'pokemonpet') -Recurse -Force -ErrorAction SilentlyContinue
if (-not $KeepProgress) { Remove-Item -LiteralPath $DataRoot -Recurse -Force -ErrorAction SilentlyContinue }
Write-Output 'PokemonPet a ete desinstalle.'
