> **[English version](CICD.en.md)** | Francais

# CI/CD — Roon Controller

## Vue d'ensemble

La chaine CI/CD repose sur **GitHub Actions** avec deux workflows independants :

| Workflow | Fichier | Runner | Declencheurs |
|----------|---------|--------|--------------|
| **CI** (build + tests) | `.github/workflows/ci.yml` | `macos-15` (Sequoia) | push, PR, cron hebdo |
| **Claude Code** (revue IA) | `.github/workflows/claude.yml` | `ubuntu-latest` | PR, mentions `@claude` |
| **Version Watch** (veille versions) | `.github/workflows/version-watch.yml` | `macos-15` (Sequoia) | cron hebdo, manuel |

```
                         ┌─────────────────────────────────────────────┐
                         │              GitHub Actions                  │
                         │                                             │
  push / PR / cron ──────┤  ci.yml                                     │
                         │  ┌─────────┐  ┌─────────┐  ┌────────────┐  │
                         │  │ Checkout │→ │  Build   │→ │   Tests    │  │
                         │  └─────────┘  │ (Debug)  │  │ (36 tests) │  │
                         │               └─────────┘  └────────────┘  │
                         │                                             │
  PR opened / sync ──────┤  claude.yml                                 │
  @claude mention ───────┤  ┌─────────┐  ┌──────────────────────────┐  │
                         │  │ Checkout │→ │ Claude Code Action (v1)  │  │
                         │  └─────────┘  │ revue auto / interactif  │  │
                         │               └──────────────────────────┘  │
                         │                                             │
  cron hebdo / manuel ──┤  version-watch.yml                          │
                         │  ┌─────────┐  ┌──────────┐  ┌───────────┐  │
                         │  │ Checkout │→ │ Versions │→ │ Issue si  │  │
                         │  └─────────┘  │ macOS    │  │ changement│  │
                         │               │ Xcode    │  └───────────┘  │
                         │               │ Swift    │                  │
                         │               │ Roon     │                  │
                         │               └──────────┘                  │
                         └─────────────────────────────────────────────┘
```

## Workflow CI — Build & Tests

### Declencheurs

| Evenement | Condition | Raison |
|-----------|-----------|--------|
| `push` | branche `main` | Valider chaque merge |
| `pull_request` | vers `main` | Verifier avant merge |
| `schedule` | lundi 08:00 UTC | Detecter les regressions dues aux mises a jour des runners macOS/Xcode |

Le build cron hebdomadaire est essentiel : Apple met a jour Xcode sur les runners GitHub sans preavis. Une mise a jour de Xcode 16.3 vers 16.4 a par exemple introduit des erreurs de concurrence Swift 6 qui n'existaient pas localement.

### Etapes

```yaml
jobs:
  build-and-test:
    runs-on: macos-15          # Sequoia — correspond au deployment target 15.0
    steps:
      - Checkout du code
      - Affichage versions Xcode/Swift    # diagnostic en cas de regression
      - Build (xcodebuild, scheme RoonController, Debug)
      - Tests (xcodebuild test, scheme RoonControllerTests, 36 tests)
```

### Pas de signature de code

Le projet utilise "Sign to Run Locally" — aucun certificat ou profil de provisioning n'est necessaire sur le runner CI. Les tests n'exigent pas non plus d'app signee.

### Badge de statut

Le badge CI est affiche en haut du `README.md` :

```markdown
[![CI](https://github.com/renesenses/roon-controller/actions/workflows/ci.yml/badge.svg)]
```

## Workflow Claude Code — Revue IA

### Declencheurs

| Evenement | Condition | Comportement |
|-----------|-----------|--------------|
| `pull_request` | `opened` ou `synchronize` | Revue automatique de chaque PR |
| `issue_comment` | contient `@claude` | Reponse interactive sur une issue |
| `pull_request_review_comment` | contient `@claude` | Reponse interactive sur un commentaire de PR |

### Configuration

```yaml
- uses: anthropics/claude-code-action@v1
  with:
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
    claude_args: "--max-turns 5"
    timeout-minutes: 10
```

- **`--max-turns 5`** : limite le nombre d'iterations pour controler les couts API
- **`timeout-minutes: 10`** : coupe-circuit si l'execution s'emballe

### Consignes de revue

Le prompt configure Claude pour se concentrer sur :

- Bonnes pratiques Swift et patterns SwiftUI
- Regressions potentielles dans les protocoles SOOD/MOO
- Securite des threads (`@MainActor`, conformite `Sendable`)
- Gestion d'erreurs et cas limites

### Permissions

Le workflow dispose des permissions minimales necessaires :

| Permission | Niveau | Usage |
|------------|--------|-------|
| `contents` | write | Modifier des fichiers si necessaire |
| `pull-requests` | write | Commenter et pousser sur les PRs |
| `issues` | write | Repondre aux mentions `@claude` |

### Prerequis

1. **Claude GitHub App** installee sur le depot (via [github.com/apps/claude](https://github.com/apps/claude))
2. **Secret `ANTHROPIC_API_KEY`** configure dans Settings > Secrets > Actions

## Workflow Version Watch — Veille versions

### Objectif

Detecter les mises a jour de macOS, Xcode, Swift (sur les runners GitHub) et Roon (via le forum communautaire) et ouvrir une issue quand une nouvelle version est detectee.

### Declencheurs

| Evenement | Condition | Raison |
|-----------|-----------|--------|
| `schedule` | lundi 09:00 UTC | Apres le build CI (08:00), verifie les versions |
| `workflow_dispatch` | manuel | Verification a la demande |

### Fonctionnement

1. **Versions runner** : `sw_vers`, `xcodebuild -version`, `swift --version` sur `macos-15`
2. **Version Roon** : requete API Discourse sur `community.roonlabs.com` (categorie Roon Software), extraction du dernier titre contenant "Release" et un numero de build
3. **Comparaison** : lecture de `.github/versions.json` et comparaison avec les versions detectees
4. **Alerte** : creation d'une issue GitHub avec label `version-watch` (ou commentaire si une issue est deja ouverte)
5. **Mise a jour** : commit automatique du nouveau `versions.json`

### Fichier de reference

`.github/versions.json` stocke les dernieres versions connues :

```json
{
  "macos": "15.2",
  "xcode": "16.2",
  "swift": "6.0.3",
  "roon": "Roon 2.0 (Build 1456) Release Notes"
}
```

### Limitations

- La detection Roon repose sur le forum communautaire Discourse — si la structure change, le check retournera `unknown` (pas de faux positif)
- Les versions du runner dependent de quand GitHub met a jour ses images `macos-15`

## Secrets

| Secret | Requis par | Description |
|--------|-----------|-------------|
| `ANTHROPIC_API_KEY` | `claude.yml` | Cle API Anthropic (depuis [console.anthropic.com](https://console.anthropic.com)) |

Le workflow CI ne necessite aucun secret — pas de signature de code, pas de deploiement.

## Matrice d'environnement

| Composant | Version CI | Version locale |
|-----------|-----------|----------------|
| Runner | `macos-15` (Sequoia) | macOS 15.x |
| Xcode | 16.4 (geree par GitHub) | 16.x |
| Swift | 6.1 | 6.x |
| Deployment target | macOS 15.0 | macOS 15.0 |

> **Attention** : la version Xcode du runner peut etre plus recente que la version locale. C'est voulu — le build cron hebdomadaire detecte les incompatibilites en avance.

## Problemes connus et solutions

### Swift 6 strict concurrency (Xcode 16.4+)

Xcode 16.4 sur les runners CI applique des regles de concurrence plus strictes que les versions anterieures. Corrections appliquees :

| Probleme | Fichier | Solution |
|----------|---------|----------|
| `BrowseResponse` / `LoadResponse` non `Sendable` | `RoonBrowseService.swift` | `@unchecked Sendable` (structs immuables avec `[String: Any]`) |
| Data race dans `sendPacket` | `SOODDiscovery.swift` | Capture de `sendFd` en `let` local, `dst` passe en immuable |
| `@MainActor` isolation dans `setUp()` | `RoonServiceTests.swift` | `override func setUp() async throws` |

### Fichier profraw fantome

Le fichier `default.profraw` (artefact de profiling local) etait reference dans le projet Xcode mais absent du depot. Supprime des references du `.pbxproj`.

### Groupes Xcode dupliques

Les groupes `Models`, `Services` et `Views` etaient references a la fois dans le groupe racine et dans le groupe `RoonController`. Corrige en supprimant les doublons du groupe racine.

## Utilisation au quotidien

### Verifier le statut CI

```bash
# Derniers runs
gh run list --limit 5

# Suivre un run en cours
gh run watch <run-id>

# Logs d'un run echoue
gh run view <run-id> --log-failed
```

### Interagir avec Claude sur une issue ou PR

Commenter avec `@claude` suivi de votre question :

```
@claude est-ce que ce changement peut casser la reconnexion WebSocket ?
```

### Relancer un build manuellement

Depuis l'onglet Actions sur GitHub, cliquer "Re-run all jobs" sur le dernier run, ou :

```bash
gh workflow run ci.yml
```

## Couts

- **CI** : gratuit (minutes macOS incluses dans le plan GitHub)
- **Claude Code** : consomme des tokens API Anthropic a chaque PR et mention `@claude`. Le budget est controle par `--max-turns 5` et `timeout-minutes: 10`. Suivi sur [console.anthropic.com/usage](https://console.anthropic.com/usage)
