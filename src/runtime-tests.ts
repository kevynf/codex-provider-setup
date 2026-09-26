import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

type Runtime = "powershell" | "windows-powershell" | "shell";

interface Selection {
  readonly provider: string;
  readonly baseUrl: string;
  readonly model: string;
  readonly reasoningEffort?: string;
  readonly contextWindow?: string;
  readonly apiKey: string;
}

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const runtime = process.argv[2] as Runtime | undefined;
if (!runtime || !["powershell", "windows-powershell", "shell"].includes(runtime)) {
  throw new Error("Choose a runtime: powershell, windows-powershell, or shell");
}
const windowsShells = [
  process.env.SHELL,
  "C:\\Program Files\\Git\\bin\\sh.exe",
  "C:\\Program Files (x86)\\Git\\bin\\sh.exe",
].filter((value): value is string => Boolean(value));
const shell =
  process.platform === "win32" ? windowsShells.find((candidate) => existsSync(candidate)) : process.env.SHELL || "sh";
if (runtime === "shell" && !shell) throw new Error("No POSIX shell was found. Install Git for Windows or set SHELL.");

const testRoot = resolve(projectRoot, ".tmp", `runtime-tests-${runtime}-${process.pid}`);
const allowedRoot = resolve(projectRoot, ".tmp") + sep;
if (!testRoot.startsWith(allowedRoot)) throw new Error(`Unsafe test directory: ${testRoot}`);
mkdirSync(testRoot, { recursive: true });
const generatedScript = runtime === "shell" ? "dist/codex-provider-setup.sh" : "dist/codex-provider-setup.ps1";
const adapter = runtime === "shell" ? "tests/adapters/runtime.sh" : "tests/adapters/runtime.ps1";
let passed = 0;
let failed = 0;

function projectPath(path: string): string {
  return relative(projectRoot, path).replaceAll("\\", "/");
}

function invoke(
  action: string,
  values: Readonly<Record<string, string>> = {},
  input?: string,
  extraEnv: Readonly<Record<string, string>> = {},
): string {
  let command: string;
  let args: string[];
  if (runtime === "shell") {
    command = shell!;
    args = [adapter, action, generatedScript, ...Object.values(values)];
  } else {
    command = runtime === "windows-powershell" ? "powershell.exe" : "pwsh";
    args = ["-NoProfile"];
    if (runtime === "windows-powershell") args.push("-ExecutionPolicy", "Bypass");
    args.push("-File", adapter, "-Action", action, "-ScriptPath", generatedScript);
    for (const [name, value] of Object.entries(values)) args.push(`-${name}`, value);
  }
  const result = spawnSync(command, args, {
    cwd: projectRoot,
    encoding: "utf8",
    env: { ...process.env, ...extraEnv, NO_COLOR: "1", TERM: "dumb" },
    input,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      [result.stdout, result.stderr].filter(Boolean).join("\n").trim() || `${command} exited with ${result.status}`,
    );
  }
  return result.stdout.trim();
}

function inputFile(name: string, content: string): string {
  const path = resolve(testRoot, `${name}.toml`);
  writeFileSync(path, content.replaceAll("\r\n", "\n"), "utf8");
  return projectPath(path);
}

function transform(name: string, input: string, selection: Selection): string {
  const outputPath = resolve(testRoot, `${name}-output.toml`);
  invoke("transform", {
    InputPath: inputFile(`${name}-input`, input),
    OutputPath: projectPath(outputPath),
    ProviderName: selection.provider,
    BaseUrl: selection.baseUrl,
    Model: selection.model,
    ReasoningEffort: selection.reasoningEffort ?? "",
    ContextWindow: selection.contextWindow ?? "",
    ApiKey: selection.apiKey,
  });
  return readFileSync(outputPath, "utf8").replaceAll("\r\n", "\n");
}

function configure(home: string, selection: Selection): string {
  return invoke("configure", {
    CodexHome: projectPath(home),
    ProviderName: selection.provider,
    BaseUrl: selection.baseUrl,
    Model: selection.model,
    ReasoningEffort: selection.reasoningEffort ?? "",
    ContextWindow: selection.contextWindow ?? "",
    ApiKey: selection.apiKey,
  });
}

function switchProvider(home: string, choice: string): string {
  return invoke("switch-provider", { CodexHome: projectPath(home) }, undefined, {
    CODEX_PROVIDER_SETUP_TEST_CONFIRM: choice,
  });
}

function removeProvider(home: string, choice: string): string {
  return invoke("remove-provider", { CodexHome: projectPath(home) }, undefined, {
    CODEX_PROVIDER_SETUP_TEST_CONFIRM: choice,
  });
}

function restore(home: string): string {
  return invoke("restore", { CodexHome: projectPath(home) });
}

function configOf(home: string): string {
  return readFileSync(resolve(home, "config.toml"), "utf8").replaceAll("\r\n", "\n");
}

function manifestOf(home: string): Map<string, string> {
  const fields = new Map<string, string>();
  const content = readFileSync(resolve(home, ".provider-backup", "manifest.txt"), "utf8").replaceAll("\r\n", "\n");
  for (const line of content.split("\n")) {
    const separator = line.indexOf("=");
    if (separator > 0) fields.set(line.slice(0, separator), line.slice(separator + 1));
  }
  return fields;
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function includes(content: string, expected: string, message: string): void {
  assert(content.includes(expected), `${message}: ${JSON.stringify(expected)}`);
}

function excludes(content: string, unexpected: string, message: string): void {
  assert(!content.includes(unexpected), `${message}: ${JSON.stringify(unexpected)}`);
}

function providerIds(content: string): string[] {
  return [...content.matchAll(/\[model_providers\.(provider_[0-9a-f]{8})\]/g)].map((match) => match[1]!);
}

function manifestKey(providerId: string, field: string): string {
  return `provider_${providerId.slice("provider_".length)}_${field}`;
}

function test(name: string, body: () => void): void {
  try {
    body();
    console.log(`[PASS] ${name}`);
    passed += 1;
  } catch (error) {
    console.error(`[FAIL] ${name}\n  ${error instanceof Error ? error.message : String(error)}`);
    failed += 1;
  }
}

try {
  test("Missing config becomes a complete config", () => {
    const output = transform("missing", "", {
      provider: "Custom",
      baseUrl: "http://0.0.0.0/v1",
      model: "local-model",
      apiKey: "test-key",
    });
    includes(output, 'model = "local-model"', "Model is missing");
    assert(providerIds(output).length === 1, "Provider selection is missing");
    includes(output, `[model_providers.${providerIds(output)[0]}]`, "Provider section is missing");
  });

  test("Adding preserves unrelated top-level and provider settings", () => {
    const output = transform(
      "preserve",
      [
        'approval_policy = "on-request"',
        'profile = "old"',
        'model_catalog_json = "catalog.json"',
        'model = "old-model"',
        "",
        "[model_providers.keep]",
        'name = "Keep"',
        "",
        "[model_providers.provider_11111111.headers]",
        'old-secret = "keep"',
        "",
      ].join("\n"),
      {
        provider: "OpenAI",
        baseUrl: "https://proxy.example/v1",
        model: "gpt-6-sol",
        reasoningEffort: "medium",
        contextWindow: "272000",
        apiKey: 'secret"value',
      },
    );
    includes(output, 'approval_policy = "on-request"', "Unrelated setting was removed");
    includes(output, 'profile = "old"', "Profile was removed");
    includes(output, 'model_catalog_json = "catalog.json"', "Model catalog was removed");
    includes(output, "[model_providers.keep]", "Unrelated provider was removed");
    includes(output, "old-secret", "Unowned prefixed provider was removed");
    includes(output, 'experimental_bearer_token = "secret\\"value"', "API key was not escaped");
  });

  test("Multiline strings hide section and key-shaped text", () => {
    const output = transform(
      "multiline",
      [
        'developer_instructions = """',
        "[this is text, not a section]",
        'model = "inside text"',
        '"""',
        'model = "old"',
        "",
        "[features]",
        "apps = true",
        "",
      ].join("\n"),
      { provider: "Custom", baseUrl: "https://example.test/v1", model: "model-x", apiKey: "key" },
    );
    includes(output, "[this is text, not a section]", "Multiline text was damaged");
    includes(output, 'model = "inside text"', "Managed-looking multiline text was damaged");
    includes(output, "[features]", "Following section was removed");
  });

  test("TOML strings escape quotes and backslashes", () => {
    const output = transform("escaping", "", {
      provider: 'Provider "Q" \\ edge',
      baseUrl: "https://example.test/v1",
      model: 'model"\\x',
      apiKey: 'secret"\\value',
    });
    includes(output, 'model = "model\\"\\\\x"', "Model was not escaped");
    includes(output, 'name = "Provider \\"Q\\" \\\\ edge"', "Provider was not escaped");
    includes(output, 'experimental_bearer_token = "secret\\"\\\\value"', "API key was not escaped");
  });

  test("A UTF-8 BOM does not hide or duplicate the model key", () => {
    const output = transform("bom", '\uFEFFmodel = "old-model"\nprofile = "keep"\n', {
      provider: "Custom",
      baseUrl: "https://example.test/v1",
      model: "new-model",
      apiKey: "test-key",
    });
    assert((output.match(/^model\s*=/gm) ?? []).length === 1, "Generated config has duplicate model keys");
    includes(output, 'model = "new-model"', "Generated model is missing");
    includes(output, 'profile = "keep"', "Unrelated setting was removed");
  });

  test("Base URLs use local and public defaults", () => {
    const cases = new Map([
      ["0.0.0.0/v1", "http://0.0.0.0/v1"],
      ["localhost:11434/v1", "http://localhost:11434/v1"],
      ["api.example.com/v1", "https://api.example.com/v1"],
    ]);
    for (const [value, expected] of cases) {
      const output = invoke("resolve-base-url", { Value: value });
      includes(output, expected, `Unexpected Base URL for ${value}`);
      includes(output, "verify that you trust this Base URL", "Base URL security warning is missing");
    }
  });

  test("Restore refuses when there is no original config backup", () => {
    const caseRoot = resolve(testRoot, "no-original-config");
    mkdirSync(caseRoot, { recursive: true });
    configure(caseRoot, {
      provider: "New setup",
      baseUrl: "https://example.test/v1",
      model: "model-x",
      apiKey: "test-key",
    });
    const generated = configOf(caseRoot);
    const manifest = readFileSync(resolve(caseRoot, ".provider-backup", "manifest.txt"), "utf8");
    let failure = "";
    try {
      restore(caseRoot);
    } catch (error) {
      failure = error instanceof Error ? error.message : String(error);
    }
    includes(failure, "No original config.toml backup is available", "Restore did not report the missing backup");
    assert(configOf(caseRoot) === generated, "Restore changed config without an original backup");
    assert(
      readFileSync(resolve(caseRoot, ".provider-backup", "manifest.txt"), "utf8") === manifest,
      "Restore changed the manifest without an original backup",
    );
  });

  if (runtime === "shell") {
    test("Noninteractive shell input does not consume piped script data", () => {
      const output = invoke("noninteractive-input", {}, "piped script text\n");
      includes(output, "INPUT=REJECTED", "Shell input fell back to standard input without a TTY");
      excludes(output, "piped script text", "Piped script text was consumed as user input");
    });
  }

  test("Messages and tables share one left-aligned layout", () => {
    const output = invoke("ui-layout").replaceAll("\r\n", "\n");
    const expected = [
      "[i] Notice",
      "",
      "Summary:",
      "[i] Name: Value",
      "",
      "Changes:",
      "[~] Changed",
      "",
      "Menu:",
      "[1] First",
      "[2] Second",
    ].join("\n");
    assert(output === expected, `Unexpected UI layout:\n${output}`);
  });

  test("Message types, choice, and default input preserve their contracts", () => {
    includes(invoke("message-types"), "INVALID=REJECTED", "Unknown message type was accepted");
    includes(invoke("choice", {}, "2\n"), "RESULT=2", "Choice result is wrong");
    includes(invoke("default-input", {}, "\n"), "RESULT=https://api.example/v1", "Default input result is wrong");
  });

  test("Setup menu exposes the minimal provider operations", () => {
    const keys = invoke("menu-items")
      .split("\n")
      .map((row) => row.split("\t")[0]);
    assert(keys.join(",") === "1,2,3,4,9", `Unexpected setup menu: ${keys.join(",")}`);
  });

  test("Adding, switching, removing, and restoring preserve list invariants", () => {
    const caseRoot = resolve(testRoot, "lifecycle");
    mkdirSync(caseRoot, { recursive: true });
    const original = 'approval_policy = "never"\nprofile = "keep"\nmodel_catalog_json = "catalog.json"\n';
    writeFileSync(resolve(caseRoot, "config.toml"), original, "utf8");
    configure(caseRoot, {
      provider: "Shared name",
      baseUrl: "https://first.example/v1",
      model: "model-1",
      apiKey: "first-key",
    });
    configure(caseRoot, {
      provider: "Shared name",
      baseUrl: "https://second.example/v1",
      model: "model-2",
      reasoningEffort: "low",
      contextWindow: "272000",
      apiKey: "second-key",
    });
    const backup = readFileSync(resolve(caseRoot, ".provider-backup", "config.toml"), "utf8").replaceAll("\r\n", "\n");
    assert(backup === original, "Initial backup changed");
    const added = configOf(caseRoot);
    const addedProviderIds = providerIds(added);
    assert(addedProviderIds.length === 2, "Provider IDs are missing or not hash-based");
    includes(added, `[model_providers.${addedProviderIds[0]}]`, "First provider is missing");
    includes(added, `[model_providers.${addedProviderIds[1]}]`, "Second provider is missing");
    includes(added, "first-key", "First key was lost");
    includes(added, "second-key", "Second key was lost");
    includes(added, 'profile = "keep"', "Profile was removed");
    includes(added, 'model_catalog_json = "catalog.json"', "Model catalog was removed");

    switchProvider(caseRoot, "1");
    const switched = configOf(caseRoot);
    includes(switched, `model_provider = "${addedProviderIds[0]}"`, "Provider was not switched");
    includes(switched, 'model = "model-1"', "Model was not switched");
    excludes(switched, "model_reasoning_effort", "Old reasoning effort was retained");
    excludes(switched, "model_context_window", "Old context window was retained");
    includes(switched, "first-key", "Switch changed the first provider");
    includes(switched, "second-key", "Switch changed the second provider");

    removeProvider(caseRoot, "1");
    const removed = configOf(caseRoot);
    includes(removed, `[model_providers.${addedProviderIds[0]}]`, "Current provider was removed");
    excludes(removed, `[model_providers.${addedProviderIds[1]}]`, "Inactive provider was retained");
    const manifest = manifestOf(caseRoot);
    assert(manifest.get("provider_count") === "1", "Provider list was not compacted");
    assert(
      manifest.get(manifestKey(addedProviderIds[0]!, "model")) === "model-1",
      "Manifest and config provider IDs differ",
    );
    assert(!manifest.has(manifestKey(addedProviderIds[0]!, "name")), "Manifest duplicated provider name");
    assert(!manifest.has(manifestKey(addedProviderIds[0]!, "base_url")), "Manifest duplicated provider Base URL");
    excludes(
      readFileSync(resolve(caseRoot, ".provider-backup", "manifest.txt"), "utf8"),
      "-key",
      "Manifest leaked a key",
    );

    restore(caseRoot);
    assert(configOf(caseRoot) === original, "Restore did not return to the initial config");
    assert(!existsSync(resolve(caseRoot, ".provider-backup")), "Restore left the backup directory behind");
  });

  test("The current or only provider cannot be removed", () => {
    const caseRoot = resolve(testRoot, "remove-current");
    mkdirSync(caseRoot, { recursive: true });
    configure(caseRoot, {
      provider: "Only",
      baseUrl: "https://only.example/v1",
      model: "only-model",
      apiKey: "only-key",
    });
    const before = configOf(caseRoot);
    includes(removeProvider(caseRoot, "1"), "No inactive provider", "Current-provider guard was not reported");
    assert(configOf(caseRoot) === before, "Current provider was removed");
  });

  test("Unowned prefixed sections are preserved and never registered", () => {
    const caseRoot = resolve(testRoot, "unowned-prefix");
    mkdirSync(caseRoot, { recursive: true });
    const existing = [
      "[model_providers.provider_11111111]",
      'name = "User owned"',
      'base_url = "https://user.example/v1"',
      'env_key = "USER_KEY"',
      "",
    ].join("\n");
    writeFileSync(resolve(caseRoot, "config.toml"), existing, "utf8");
    configure(caseRoot, {
      provider: "Managed",
      baseUrl: "https://managed.example/v1",
      model: "managed-model",
      apiKey: "managed-key",
    });
    const config = configOf(caseRoot);
    includes(config, "[model_providers.provider_11111111]", "User-owned provider was removed");
    const managedIds = providerIds(config).filter((id) => id !== "provider_11111111");
    assert(managedIds.length === 1, "Managed provider did not receive a hash ID");
    assert(
      manifestOf(caseRoot).get(manifestKey(managedIds[0]!, "model")) === "managed-model",
      "Unowned provider was registered",
    );
  });

  test("Adding stops when a registered provider section is missing", () => {
    const caseRoot = resolve(testRoot, "missing-registered-provider");
    mkdirSync(caseRoot, { recursive: true });
    configure(caseRoot, {
      provider: "First",
      baseUrl: "https://first.example/v1",
      model: "model-1",
      apiKey: "first-key",
    });
    configure(caseRoot, {
      provider: "Second",
      baseUrl: "https://second.example/v1",
      model: "model-2",
      apiKey: "second-key",
    });
    const firstId = providerIds(configOf(caseRoot))[0];
    const firstSection = [
      "",
      `[model_providers.${firstId}]`,
      'name = "First"',
      'base_url = "https://first.example/v1"',
      'wire_api = "responses"',
      'experimental_bearer_token = "first-key"',
    ].join("\n");
    const drifted = configOf(caseRoot).replace(firstSection, "");
    writeFileSync(resolve(caseRoot, "config.toml"), drifted, "utf8");
    const manifestBefore = readFileSync(resolve(caseRoot, ".provider-backup", "manifest.txt"), "utf8");
    let failure = "";
    try {
      configure(caseRoot, {
        provider: "Third",
        baseUrl: "https://third.example/v1",
        model: "model-3",
        apiKey: "third-key",
      });
    } catch (error) {
      failure = error instanceof Error ? error.message : String(error);
    }
    includes(failure, "missing", "Missing registered provider was not reported");
    assert(configOf(caseRoot) === drifted, "Config changed after provider drift was detected");
    assert(
      readFileSync(resolve(caseRoot, ".provider-backup", "manifest.txt"), "utf8") === manifestBefore,
      "Manifest changed after provider drift was detected",
    );
  });

  test("Invalid manifests stop before changing config", () => {
    const caseRoot = resolve(testRoot, "invalid-manifest");
    const backupDir = resolve(caseRoot, ".provider-backup");
    mkdirSync(backupDir, { recursive: true });
    const original = 'approval_policy = "never"\n';
    writeFileSync(resolve(caseRoot, "config.toml"), original, "utf8");
    writeFileSync(
      resolve(backupDir, "manifest.txt"),
      [
        "format_version=1",
        "script_version=1.1.0",
        "created_at=2026-09-25 00:00:00",
        "original_config_existed=1",
        "provider_count=1",
        "provider_user_provider_model=model-x",
        "provider_user_provider_reasoning_effort=",
        "provider_user_provider_context_window=",
        "",
      ].join("\n"),
      "utf8",
    );
    let failure = "";
    try {
      configure(caseRoot, {
        provider: "Blocked",
        baseUrl: "https://blocked.example/v1",
        model: "blocked-model",
        apiKey: "blocked-key",
      });
    } catch (error) {
      failure = error instanceof Error ? error.message : String(error);
    }
    includes(failure, "manifest", "Invalid manifest was not reported");
    assert(configOf(caseRoot) === original, "Invalid manifest allowed config changes");
  });
} finally {
  rmSync(testRoot, { recursive: true, force: true });
}

const runtimeName =
  runtime === "powershell" ? "PowerShell" : runtime === "windows-powershell" ? "Windows PowerShell" : "Shell";
console.log(`\nShared ${runtimeName} behavior: ${passed} passed; ${failed} failed`);
if (failed > 0) process.exit(1);
