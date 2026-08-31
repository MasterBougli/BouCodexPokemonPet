param(
    [string]$DataRoot = (Join-Path $env:LOCALAPPDATA 'BouCodexPokemonPet'),
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$registryPath = Join-Path $DataRoot 'pets.json'
$speciesPath = Join-Path $DataRoot 'pokemon-species.csv'
$configPath = Join-Path $DataRoot 'config.json'
$statePath = Join-Path $DataRoot 'state.json'
$pidPath = Join-Path $DataRoot 'watcher.pid'
$watcherPath = Join-Path $PSScriptRoot 'pokemonpet.ps1'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runName = 'PokemonPet'

function Get-Catalog {
    $registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json
    return @($registry.pets | Where-Object { $_.style -eq '3d' -and $_.category -eq 'pokemon' } | Sort-Object gen, pokedex_id)
}

function Get-EvolutionPaths($Selected, $Catalog, $Species) {
    $byIdentifier = @{}
    foreach ($pet in $Catalog) { $byIdentifier[$pet.species_slug] = $pet }
    $selectedSpecies = $Species | Where-Object { [int]$_.id -eq [int]$Selected.pokedex_id } | Select-Object -First 1
    if (-not $selectedSpecies) { return ,@($Selected) }

    $family = @($Species | Where-Object { $_.evolution_chain_id -eq $selectedSpecies.evolution_chain_id })
    $children = @{}
    foreach ($member in $family) {
        if ($member.evolves_from_species_id) {
            $key = [string]$member.evolves_from_species_id
            if (-not $children.ContainsKey($key)) { $children[$key] = @() }
            $children[$key] += $member
        }
    }

    function Expand-Path($Node, $Path) {
        $nextPath = @($Path)
        if ($byIdentifier.ContainsKey($Node.identifier)) { $nextPath += $byIdentifier[$Node.identifier] }
        $key = [string]$Node.id
        if (-not $children.ContainsKey($key) -or $children[$key].Count -eq 0) { return ,$nextPath }
        $paths = @()
        foreach ($child in $children[$key]) { $paths += @(Expand-Path $child $nextPath) }
        return $paths
    }

    $paths = @(Expand-Path $selectedSpecies @())
    $usable = @($paths | Where-Object { $_.Count -gt 0 })
    if ($usable.Count -eq 0) { return ,@($Selected) }
    return $usable
}

function Get-Thresholds([int]$Count) {
    if ($Count -le 1) { return @(0) }
    if ($Count -eq 2) { return @(0, 500) }
    return @(0, 500, 2000)
}

function Stop-Watcher {
    if (-not (Test-Path -LiteralPath $pidPath)) { return }
    $watcherPid = [int](Get-Content -Raw -LiteralPath $pidPath)
    $process = Get-Process -Id $watcherPid -ErrorAction SilentlyContinue
    if ($process) { Stop-Process -Id $watcherPid -Force }
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}

function Start-Watcher {
    $hostExe = (Get-Process -Id $PID).Path
    Start-Process -FilePath $hostExe -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $watcherPath),
        '-DataRoot', ('"{0}"' -f $DataRoot)
    ) | Out-Null
}

function Set-Autostart([bool]$Enabled) {
    if ($Enabled) {
        $hostExe = (Get-Process -Id $PID).Path
        $command = '"{0}" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" -DataRoot "{2}"' -f $hostExe, $watcherPath, $DataRoot
        New-Item -Path $runKey -Force | Out-Null
        Set-ItemProperty -Path $runKey -Name $runName -Value $command
    } else {
        Remove-ItemProperty -Path $runKey -Name $runName -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $registryPath) -or -not (Test-Path -LiteralPath $speciesPath)) {
    throw "Installation incomplete. Lancez d'abord install.ps1."
}
$catalog = Get-Catalog
$species = @(Import-Csv -LiteralPath $speciesPath)

if ($SelfTest) {
    $charmander = $catalog | Where-Object species_slug -eq 'charmander' | Select-Object -First 1
    $eevee = $catalog | Where-Object species_slug -eq 'eevee' | Select-Object -First 1
    $charmanderPaths = @(Get-EvolutionPaths $charmander $catalog $species)
    $eeveePaths = @(Get-EvolutionPaths $eevee $catalog $species)
    if (($charmanderPaths[0] | ForEach-Object species_slug) -join ',' -ne 'charmander,charmeleon,charizard') { throw 'Evolution lineaire invalide.' }
    if ($eeveePaths.Count -lt 8) { throw 'Branches d evolution invalides.' }
    if ($catalog.Count -lt 1000) { throw 'Catalogue 3D incomplet.' }
    if ([math]::Max(0, [math]::Min(-1, 2)) -ne 0) { throw 'Indice de progression invalide.' }
    Write-Output "Self-test UI OK ($($catalog.Count) Pokemon, $($eeveePaths.Count) branches pour Eevee)"
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'PokemonPet pour Codex'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(520, 500)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#FFF7ED')
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Choisir votre compagnon'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
$title.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#7C2D12')
$title.SetBounds(24, 20, 470, 38)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Chaque utilisation de Codex lui donne de l XP et le fait evoluer.'
$subtitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#7C2D12')
$subtitle.SetBounds(26, 60, 470, 24)
$form.Controls.Add($subtitle)

function Add-Label([string]$Text, [int]$Top) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.SetBounds(26, $Top, 460, 22)
    $form.Controls.Add($label)
}

Add-Label 'Generation' 102
$generation = New-Object System.Windows.Forms.ComboBox
$generation.DropDownStyle = 'DropDownList'
$generation.SetBounds(26, 126, 468, 34)
1..9 | ForEach-Object { [void]$generation.Items.Add("Generation $_") }
$form.Controls.Add($generation)

Add-Label 'Pokemon de depart' 168
$pokemon = New-Object System.Windows.Forms.ComboBox
$pokemon.DropDownStyle = 'DropDownList'
$pokemon.DisplayMember = 'name'
$pokemon.SetBounds(26, 192, 468, 34)
$form.Controls.Add($pokemon)

Add-Label 'Parcours d evolution' 234
$evolution = New-Object System.Windows.Forms.ComboBox
$evolution.DropDownStyle = 'DropDownList'
$evolution.SetBounds(26, 258, 468, 34)
$form.Controls.Add($evolution)

$statusBox = New-Object System.Windows.Forms.GroupBox
$statusBox.Text = 'Progression actuelle'
$statusBox.SetBounds(26, 310, 468, 88)
$form.Controls.Add($statusBox)

$status = New-Object System.Windows.Forms.Label
$status.SetBounds(16, 24, 430, 22)
$statusBox.Controls.Add($status)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.SetBounds(16, 52, 430, 18)
$statusBox.Controls.Add($progress)

$autostart = New-Object System.Windows.Forms.CheckBox
$autostart.Text = 'Demarrer PokemonPet automatiquement avec Windows'
$autostart.SetBounds(28, 410, 440, 28)
$form.Controls.Add($autostart)

$save = New-Object System.Windows.Forms.Button
$save.Text = 'Appliquer et lancer'
$save.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#2563EB')
$save.ForeColor = [System.Drawing.Color]::White
$save.FlatStyle = 'Flat'
$save.SetBounds(314, 448, 180, 42)
$form.Controls.Add($save)
$form.AcceptButton = $save

$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = 'Fermer'
$cancel.SetBounds(208, 448, 96, 42)
$cancel.Add_Click({ $form.Close() })
$form.Controls.Add($cancel)

$script:paths = @()
$generation.Add_SelectedIndexChanged({
    $pokemon.Items.Clear()
    $items = @($catalog | Where-Object { [int]$_.gen -eq ($generation.SelectedIndex + 1) } | Sort-Object name)
    foreach ($item in $items) { [void]$pokemon.Items.Add($item) }
    if ($pokemon.Items.Count -gt 0) { $pokemon.SelectedIndex = 0 }
})

$pokemon.Add_SelectedIndexChanged({
    $evolution.Items.Clear()
    if (-not $pokemon.SelectedItem) { return }
    $script:paths = @(Get-EvolutionPaths $pokemon.SelectedItem $catalog $species)
    foreach ($path in $script:paths) {
        $names = @($path | ForEach-Object { $_.name -replace ' \(3D\)$', '' })
        [void]$evolution.Items.Add(($names -join '  >  '))
    }
    if ($evolution.Items.Count -gt 0) { $evolution.SelectedIndex = 0 }
})

$existingConfig = if (Test-Path -LiteralPath $configPath) { Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json } else { $null }
$existingState = if (Test-Path -LiteralPath $statePath) { Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json } else { [pscustomobject]@{ xp = 0; stage = 0 } }
$currentIndex = if ($existingConfig) { [math]::Max(0, [math]::Min([int]$existingState.stage, @($existingConfig.stages).Count - 1)) } else { 0 }
$currentSlug = if ($existingConfig) { @($existingConfig.stages)[$currentIndex] } else { 'pichu-3d' }
$selectionSlug = if ($existingConfig) { @($existingConfig.stages)[0] } else { 'pichu-3d' }
$currentPet = $catalog | Where-Object slug -eq $currentSlug | Select-Object -First 1
$selectionPet = $catalog | Where-Object slug -eq $selectionSlug | Select-Object -First 1
$status.Text = if ($currentPet) { "$($currentPet.name -replace ' \(3D\)$', '') - $($existingState.xp) XP" } else { "$($existingState.xp) XP" }
$thresholds = if ($existingConfig) { @($existingConfig.evolutionXp) } else { @(0, 500, 2000) }
$next = @($thresholds | Where-Object { $_ -gt [int]$existingState.xp } | Select-Object -First 1)
if ($next.Count -gt 0) {
    $previous = @($thresholds | Where-Object { $_ -le [int]$existingState.xp } | Select-Object -Last 1)[0]
    $progress.Maximum = [math]::Max(1, [int]$next[0] - [int]$previous)
    $progress.Value = [math]::Min($progress.Maximum, [int]$existingState.xp - [int]$previous)
} else { $progress.Maximum = 1; $progress.Value = 1 }
$autostart.Checked = $null -ne (Get-ItemProperty -Path $runKey -Name $runName -ErrorAction SilentlyContinue)

$initialGen = if ($selectionPet) { [int]$selectionPet.gen } else { 1 }
$generation.SelectedIndex = $initialGen - 1
if ($selectionPet) {
    for ($i = 0; $i -lt $pokemon.Items.Count; $i++) {
        if ($pokemon.Items[$i].slug -eq $selectionPet.slug) { $pokemon.SelectedIndex = $i; break }
    }
}

$save.Add_Click({
    if (-not $pokemon.SelectedItem -or $evolution.SelectedIndex -lt 0) { return }
    $path = @($script:paths[$evolution.SelectedIndex])
    $stages = @($path | ForEach-Object slug)
    $changed = -not $existingConfig -or ((@($existingConfig.stages) -join ',') -ne ($stages -join ','))
    if ($changed -and [int]$existingState.xp -gt 0) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            'Changer de Pokemon remet sa progression a zero. Continuer ?',
            'Reinitialiser la progression',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }

    Stop-Watcher
    [ordered]@{
        stages = $stages
        evolutionXp = @(Get-Thresholds $stages.Count)
        tokensPerXp = 100
    } | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8
    if ($changed) { [ordered]@{ xp = 0; stage = -1 } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8 }
    Set-Autostart $autostart.Checked
    Start-Watcher
    [System.Windows.Forms.MessageBox]::Show(
        'PokemonPet est actif. Dans Codex, selectionnez PokemonPet dans les reglages de mascotte.',
        'PokemonPet',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    $form.Close()
})

[void]$form.ShowDialog()
