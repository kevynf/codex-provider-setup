# Codex Provider Setup

Configure Codex with an OpenAI model preset or any Responses-compatible provider.

## Run

### Windows

<!-- prettier-ignore -->
```powershell
irm https://kevynf.github.io/codex-provider-setup/setup.ps1 | iex
```

### Linux and macOS

```sh
curl -fsSL https://kevynf.github.io/codex-provider-setup/setup.sh | sh
```

Both scripts preserve unrelated settings and keep a restorable backup in `$CODEX_HOME/.provider-backup` (or `~/.codex/.provider-backup` when `CODEX_HOME` is unset). API keys remain in plain text in `config.toml` and are never added to the backup manifest.

## Architecture

`src/spec.ts` is the source of truth for model presets, messages, versions, markers, and colors. The generator combines it with platform runtime templates and writes complete standalone scripts to `dist/`.

```text
UI
├── Interaction
│   ├── InputUI
│   │   ├── Message | Table
│   │   └── Input
│   └── FeedbackUI
│       └── Message | Table
└── Style
    ├── Message(Type, Content)
    ├── Table(Title, Message[])
    │   ├── Ordered
    │   └── Unordered
    └── Input(Message)
```

`Message` renders table rows and input prompts. Types control colors, and Interaction controls spacing.

## Development

Requires Node.js 24, pnpm 12, PowerShell 7, and a POSIX `sh` implementation.

```sh
pnpm install
pnpm fmt
pnpm test
```

On Windows, also test Windows PowerShell 5.1:

```powershell
pnpm test:windows-powershell
```

Edit `src/spec.ts` for presets, copy, and type styling. Edit `templates/` for platform behavior. `pnpm fmt:check` enforces formatting and generated files in CI.

## Release

Create and push a version tag matching `v*`:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The release workflow publishes versioned scripts with checksums and build provenance. Every push to `main` updates the short GitHub Pages URLs above.
