# BouCodexPokemonPet

Une mascotte Pokémon évolutive pour l’application Codex sous Windows.

Choisissez un Pokémon par génération, utilisez Codex et gagnez de l’XP. La mascotte installée dans Codex change automatiquement de forme aux seuils d’évolution.

## Fonctionnalités

- sélecteur natif Windows `Génération → Pokémon`, limité aux Pokémon pouvant encore évoluer ;
- 1 004 Pokémon animés en style 3D, générations 1 à 9 ;
- parcours ramifiés, dont les huit évolutions d’Évoli ;
- XP calculée localement à partir des compteurs de tokens Codex hors cache ;
- difficulté d’XP configurable sans réinitialiser la progression ;
- seuils par défaut : 500 XP puis 2 000 XP ;
- démarrage automatique avec Windows en option ;
- une seule entrée `PokemonPet` dans le menu des mascottes Codex.

## Installation

Prérequis : Windows 10/11, PowerShell 5.1 ou plus récent, Git et l’application Codex avec les mascottes activées.

```powershell
git clone https://github.com/MasterBougli/BouCodexPokemonPet.git
cd BouCodexPokemonPet
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Le programme télécharge le registre de [Codex PokéPets](https://github.com/dnnyngyen/codex-pokepets) et les données d’évolution de [PokéAPI](https://github.com/PokeAPI/pokeapi). Les sprites ne sont téléchargés qu’au moment où une forme est utilisée.

Après avoir appliqué votre choix, sélectionnez **PokemonPet** dans **Settings → Appearance → Pets** de Codex. Un redémarrage de Codex peut être nécessaire lors du premier ajout.

### Difficulté d’XP

| Difficulté | Gain |
| --- | --- |
| Détente | 1 XP pour 50 tokens utiles |
| Normal | 1 XP pour 100 tokens utiles |
| Difficile | 1 XP pour 250 tokens utiles |
| Extrême | 1 XP pour 500 tokens utiles |

Changer uniquement la difficulté conserve l’XP déjà gagnée.

## Utilisation

Rouvrir le sélecteur :

```powershell
powershell -ExecutionPolicy Bypass -File .\src\pokemonpet-ui.ps1
```

Vérifier l’installation :

```powershell
.\src\pokemonpet.ps1 -SelfTest
.\src\pokemonpet-ui.ps1 -SelfTest
```

Les données privées restent dans `%LOCALAPPDATA%\BouCodexPokemonPet`. Le programme lit uniquement les nouveaux événements locaux `token_count` des sessions Codex ; il n’envoie pas le contenu des conversations.

## Désinstallation

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Utilisez `-KeepProgress` pour conserver l’XP et la configuration.

## Limites

Le contrat actuel des mascottes Codex ne fournit ni catégories personnalisées ni sous-menus. Le dépôt installe donc une seule mascotte `PokemonPet` et utilise son propre sélecteur `Génération → Pokémon`.

Ce projet cible Windows et repose sur un format de mascotte Codex non documenté publiquement, susceptible d’évoluer.

## Crédits et droits

Le code de ce dépôt est distribué sous licence MIT. Aucun sprite Pokémon n’est inclus dans le dépôt.

Les sprites utilisés à la demande proviennent de [Codex PokéPets](https://github.com/dnnyngyen/codex-pokepets), lui-même alimenté par Pokémon Showdown. Pokémon et les illustrations associées appartiennent à Nintendo, Game Freak et Creatures Inc. Ce projet de fan n’est ni affilié ni approuvé par ces sociétés, OpenAI, PokéAPI ou Pokémon Showdown. Usage personnel et non commercial uniquement pour les sprites.
