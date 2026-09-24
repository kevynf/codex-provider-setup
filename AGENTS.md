# Repository Guidelines

## Project Structure & Module Organization

`src/` contains the TypeScript build tools. Treat `src/spec.ts` as the source of truth for provider presets, messages, versions, markers, and colors; `src/generate.ts` combines that specification with the PowerShell and POSIX shell templates in `templates/`. Generated standalone scripts are written to `dist/` and must not be edited directly. Cross-runtime behavior tests live in `src/runtime-tests.ts`, platform checks live under `tests/powershell/` and `tests/shell/`, and `tests/adapters/` exposes runtime operations to those tests. GitHub Actions workflows are in `.github/workflows/`.

## Build, Test, and Development Commands

Use Node.js 24, pnpm 12, PowerShell 7, and a POSIX `sh` implementation.

- `pnpm install --frozen-lockfile`: install the exact dependency set.
- `pnpm build`: compile TypeScript into the ignored `.build/` directory.
- `pnpm generate`: rebuild `dist/codex-provider-setup.{ps1,sh}`.
- `pnpm fmt`: format the repository, then regenerate distributable scripts.
- `pnpm fmt:check`: verify formatting and that generated files are current.
- `pnpm test`: run generated-file, PowerShell, and shell checks.
- `pnpm test:powershell` or `pnpm test:shell`: run one platform suite.
- `pnpm test:windows-powershell`: additionally verify Windows PowerShell 5.1.

## Coding Style & Naming Conventions

Prettier is authoritative: use LF endings, a 120-column width, two-space indentation for TypeScript and shell, and four spaces for PowerShell. TypeScript is strict; retain explicit interfaces, camelCase values/functions, and PascalCase types. Follow existing shell `snake_case` and PowerShell `Verb-Noun` naming. Keep generated output ASCII and edit its owning spec or template instead.

## Testing Guidelines

Tests use lightweight repository-owned harnesses rather than an external test framework. Add behavioral cases to `src/runtime-tests.ts` when both runtimes must agree, and platform-specific assertions to the matching `*.Tests.ps1` or `*.Tests.sh` file. No numeric coverage threshold is defined. Run the focused suite while developing, then `pnpm fmt:check` and `pnpm test` before review. CI also runs ShellCheck on shell artifacts.

## Commit & Pull Request Guidelines

The repository currently has no commit history from which to infer a convention. Use Conventional Commits with a concise Chinese description, for example `fix: 保留自定义提供商配置`. Keep each commit focused. Pull requests should explain behavior changes, list verification commands, link relevant issues, and include terminal output or screenshots when user-visible interaction changes.

## Security & Configuration

Never commit API keys, local Codex configuration, logs, or temporary files. Preserve the scripts' backup behavior and ensure manifests never include secrets.
