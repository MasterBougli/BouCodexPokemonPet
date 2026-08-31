param(
    [string]$DataRoot = (Join-Path $env:LOCALAPPDATA 'BouCodexPokemonPet'),
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$configPath = Join-Path $DataRoot 'config.json'
$statePath = Join-Path $DataRoot 'state.json'

New-Item -ItemType Directory -Force -Path $DataRoot | Out-Null
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/dnnyngyen/codex-pokepets/main/pets.json' -OutFile (Join-Path $DataRoot 'pets.json')
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/pokemon_species.csv' -OutFile (Join-Path $DataRoot 'pokemon-species.csv')
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/pokemon_species_names.csv' -OutFile (Join-Path $DataRoot 'pokemon-species-names.csv')

# Migre la progression des premieres versions locales sans la publier dans Git.
$legacyState = Join-Path $PSScriptRoot '.pokemonpet-state.json'
if (-not (Test-Path -LiteralPath $statePath) -and (Test-Path -LiteralPath $legacyState)) {
    Copy-Item -LiteralPath $legacyState -Destination $statePath
}
if (-not (Test-Path -LiteralPath $configPath)) {
    [ordered]@{
        stages = @('pichu-3d', 'pikachu-3d', 'raichu-3d')
        evolutionXp = @(0, 500, 2000)
        tokensPerXp = 100
    } | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8
}

$watcher = Join-Path $PSScriptRoot 'src\pokemonpet.ps1'
$selector = Join-Path $PSScriptRoot 'src\pokemonpet-ui.ps1'
& $watcher -SelfTest
& $selector -DataRoot $DataRoot -SelfTest
Write-Output "PokemonPet est installe dans $DataRoot"

if (-not $NoLaunch) {
    $hostExe = (Get-Process -Id $PID).Path
    Start-Process -FilePath $hostExe -WindowStyle Normal -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $selector),
        '-DataRoot', ('"{0}"' -f $DataRoot)
    ) | Out-Null
}
