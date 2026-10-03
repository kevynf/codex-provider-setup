# Codex Provider Setup

Configure Codex with an OpenAI model preset or any Responses-compatible provider.

## Codex

### Run

#### Windows

<!-- prettier-ignore -->
```powershell
irm https://kevynf.github.io/codex-provider-setup/setup.ps1 | iex
```

#### Linux and macOS

```sh
curl -fsSL https://kevynf.github.io/codex-provider-setup/setup.sh | sh
```

### Provider management

- **Add** creates and selects a preset or custom provider.
- **Switch** selects a provider added earlier.
- **Remove** deletes a provider that is not currently selected.
- **Restore** returns `config.toml` to its state before the first setup.

Unrelated settings and existing provider sections are preserved. The original config is backed up to `.provider-backup` under the Codex home directory. API keys remain in plain text in `config.toml`.

## Claude Code (additional)

### Run

#### Windows

<!-- prettier-ignore -->
```powershell
irm https://kevynf.github.io/codex-provider-setup/cc-setup.ps1 | iex
```

#### Linux and macOS

```sh
curl -fsSL https://kevynf.github.io/codex-provider-setup/cc-setup.sh | sh
```

### Provider management

The Claude Code script uses `settings.json` under `CLAUDE_CONFIG_DIR` or
`~/.claude` for an Anthropic-compatible provider.

- **Configure** writes the Base URL, model, and auth token while preserving existing settings.
- **Restore** returns the settings file to its state before the first setup.

An existing settings file is backed up under `.provider-backup`. POSIX setup
requires Node.js.

## Architecture

`src/spec.ts` is the source of truth for model presets, messages, versions, markers, and colors. The generator combines it with platform runtime templates and writes complete standalone scripts to `dist/`.

The scripts organize the UI into two related layers: interaction flow and rendering:

```text
Interaction model
├── Input interaction
│   ├── Message | Table
│   └── Input
└── Feedback interaction
    └── Message | Table

Rendering model
├── Message(Type, Content)
├── Table(Title, Message[])
│   └── Ordered | Unordered
└── Input(Message)
```

## Development

Requires Node.js 24, pnpm 12, PowerShell 7, and a POSIX `sh` implementation.

```sh
pnpm install
pnpm fmt
pnpm test
```

`pnpm test` runs the Codex tests and the Claude Code tests.

On Windows, also test Windows PowerShell 5.1:

```powershell
pnpm test:windows-powershell
```

Edit `src/spec.ts` for shared data and `templates/` for platform behavior. Generated scripts in `dist/` must not be edited directly.

## Release

Create and push a version tag matching `v*`:

```sh
git tag v1.1.0
git push origin v1.1.0
```

The release workflow publishes versioned scripts with checksums and build provenance. Every push to `main` updates the short GitHub Pages URLs above.
