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

if (runtime === "shell" && !shell) {
  throw new Error("No POSIX shell was found. Install Git for Windows or set SHELL.");
}

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

function invoke(action: string, values: Readonly<Record<string, string>> = {}, input?: string): string {
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
    env: { ...process.env, NO_COLOR: "1", TERM: "dumb" },
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
  const inputPath = inputFile(`${name}-input`, input);
  const outputPath = resolve(testRoot, `${name}-output.toml`);
  const reportPath = resolve(testRoot, `${name}-report.txt`);
  const values = {
    InputPath: inputPath,
    OutputPath: projectPath(outputPath),
    ReportPath: projectPath(reportPath),
    ProviderName: selection.provider,
    BaseUrl: selection.baseUrl,
    Model: selection.model,
    ReasoningEffort: selection.reasoningEffort ?? "",
    ContextWindow: selection.contextWindow ?? "",
    ApiKey: selection.apiKey,
  };
  invoke("transform", values);
  return readFileSync(outputPath, "utf8").replaceAll("\r\n", "\n");
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
    includes(output, "[model_providers.codex_provider_setup]", "Managed provider is missing");
  });

  test("Unrelated settings survive managed replacement", () => {
    const output = transform(
      "preserve",
      [
        'approval_policy = "on-request"',
        'profile = "old"',
        'model = "old-model"',
        "",
        "[model_providers.keep]",
        'name = "Keep"',
        "",
        "[model_providers.codex_provider_setup.headers]",
        'old-secret = "remove"',
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
    includes(output, "[model_providers.keep]", "Unrelated provider was removed");
    includes(output, 'model_reasoning_effort = "medium"', "Reasoning effort is missing");
    includes(output, "model_context_window = 272000", "Context window is missing");
    includes(output, 'experimental_bearer_token = "secret\\"value"', "API key was not escaped");
    excludes(output, 'profile = "old"', "Profile was retained");
    excludes(output, "old-secret", "Managed provider subtable was retained");
    assert(
      (output.match(/\[model_providers\.codex_provider_setup\]/g) ?? []).length === 1,
      "Managed provider was duplicated",
    );
  });

  test("Quoted and case-sensitive provider keys stay independent", () => {
    const output = transform(
      "quoted",
      [
        '[model_providers."codex_provider_setup.extra"]',
        'name = "Keep quoted key"',
        "",
        "[model_providers.CODEX_PROVIDER_SETUP]",
        'name = "Keep case-sensitive key"',
        "",
      ].join("\n"),
      {
        provider: "Custom",
        baseUrl: "https://example.test/v1",
        model: "model-x",
        apiKey: "key",
      },
    );
    includes(output, '[model_providers."codex_provider_setup.extra"]', "Quoted provider was removed");
    includes(output, "[model_providers.CODEX_PROVIDER_SETUP]", "Case-sensitive provider was removed");
  });

  test("Multiline strings hide section and key-shaped text", () => {
    const output = transform(
      "multiline",
      [
        'developer_instructions = """',
        "[this is text, not a section]",
        'model = "inside text"',
        'foo = "inside text"',
        '"""',
        'foo = "outside"',
        'model = "old"',
        "",
        "[features]",
        "apps = true",
        "",
      ].join("\n"),
      {
        provider: "Custom",
        baseUrl: "https://example.test/v1",
        model: "model-x",
        apiKey: "key",
      },
    );
    includes(output, "[this is text, not a section]", "Multiline section-shaped text was damaged");
    includes(output, 'model = "inside text"', "Multiline managed-looking text was damaged");
    includes(output, 'foo = "outside"', "Top-level unrelated key was removed");
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

  test("Managed-provider detection respects TOML boundaries", () => {
    const textOnly = inputFile(
      "guard-text",
      [
        'developer_instructions = """',
        "[model_providers.codex_provider_setup]",
        '"""',
        "[model_providers.keep]",
        "",
      ].join("\n"),
    );
    const actual = inputFile("guard-actual", "[model_providers.codex_provider_setup.headers]\n");
    assert(
      invoke("contains-managed-provider", { InputPath: textOnly }) === "false",
      "Multiline text was treated as a provider",
    );
    assert(
      invoke("contains-managed-provider", { InputPath: actual }) === "true",
      "Managed provider subtable was not detected",
    );
  });

  test("Base URLs use local and public defaults", () => {
    const cases = new Map([
      ["0.0.0.0/v1", "http://0.0.0.0/v1"],
      ["localhost:11434/v1", "http://localhost:11434/v1"],
      ["api.example.com/v1", "https://api.example.com/v1"],
      ["http://127.0.0.1:8080/v1", "http://127.0.0.1:8080/v1"],
      ["https://gateway.example/v1", "https://gateway.example/v1"],
    ]);
    for (const [value, expected] of cases) {
      assert(invoke("resolve-base-url", { Value: value }) === expected, `Unexpected Base URL for ${value}`);
    }
  });

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
    assert(
      output.split("\n").every((line) => !line.startsWith(" ")),
      "UI output is not left-aligned",
    );
  });

  test("Message types own markers and reject unknown types", () => {
    const output = invoke("message-types").replaceAll("\r\n", "\n");
    const expected = [
      "[i] Info",
      "[i] Detail",
      "[+] Success",
      "[!] Warning",
      "[X] Error",
      "[?] Prompt",
      "[~] Change",
      "[7] 7",
      "INVALID=REJECTED",
    ].join("\n");
    assert(output === expected, `Unexpected message types:\n${output}`);
  });

  test("Choice renders an ordered table before input", () => {
    const output = invoke("choice", {}, "2\n").replaceAll("\r\n", "\n");
    const expected = ["Choose:", "[1] First", "[2] Second", "[?] Select: RESULT=2"].join("\n");
    assert(output === expected, `Unexpected choice interaction:\n${output}`);
  });

  test("Defaulted input renders its value as a table", () => {
    const output = invoke("default-input", {}, "\n").replaceAll("\r\n", "\n");
    const expected = [
      "Base URL:",
      "[i] Default: https://api.example/v1",
      "[?] Enter Base URL: RESULT=https://api.example/v1",
    ].join("\n");
    assert(output === expected, `Unexpected default input interaction:\n${output}`);
  });

  test("Message templates format one or multiple values", () => {
    const output = invoke("messages").replaceAll("\r\n", "\n");
    const expected = [
      "Updated config.toml",
      "Failed to write the config. The pre-setup backup remains at backup. write failed",
    ].join("\n");
    assert(output === expected, `Unexpected formatted messages:\n${output}`);
  });

  test("Configure and restore preserve the initial config", () => {
    const caseRoot = resolve(testRoot, "lifecycle");
    const configPath = resolve(caseRoot, "config.toml");
    const backupDir = resolve(caseRoot, "backup-codex-provider-setup");
    const backupConfig = resolve(backupDir, "config.toml");
    const manifestPath = resolve(backupDir, "manifest.txt");
    const original = 'approval_policy = "never"\n';
    mkdirSync(caseRoot, { recursive: true });
    writeFileSync(configPath, original, "utf8");

    invoke("configure", {
      CodexHome: projectPath(caseRoot),
      ProviderName: "Custom",
      BaseUrl: "http://0.0.0.0/v1",
      Model: "local-model",
      ReasoningEffort: "",
      ContextWindow: "",
      ApiKey: "cycle-test-key",
    });

    assert(existsSync(backupConfig), "Original config was not backed up");
    includes(readFileSync(configPath, "utf8"), "cycle-test-key", "Configured API key is missing");
    excludes(readFileSync(manifestPath, "utf8"), "cycle-test-key", "Manifest leaked the API key");

    invoke("restore", { CodexHome: projectPath(caseRoot) });
    assert(readFileSync(configPath, "utf8").replaceAll("\r\n", "\n") === original, "Original config was not restored");
    assert(!existsSync(backupDir), "Restore left the backup directory behind");
  });

  test("Restore succeeds when the generated config is already absent", () => {
    const caseRoot = resolve(testRoot, "restore-absent");
    const backupDir = resolve(caseRoot, "backup-codex-provider-setup");
    mkdirSync(backupDir, { recursive: true });
    writeFileSync(resolve(backupDir, "manifest.txt"), "original_config_existed=0\n", "utf8");

    const output = invoke("restore", { CodexHome: projectPath(caseRoot) });
    includes(output, "[+] The generated config.toml was already absent.", "Absent config result is missing");
    assert(!existsSync(backupDir), "Restore left the backup directory behind");
  });
} finally {
  rmSync(testRoot, { recursive: true, force: true });
}

const runtimeName =
  runtime === "powershell" ? "PowerShell" : runtime === "windows-powershell" ? "Windows PowerShell" : "Shell";
console.log(`\nShared ${runtimeName} behavior: ${passed} passed; ${failed} failed`);
if (failed > 0) process.exit(1);
