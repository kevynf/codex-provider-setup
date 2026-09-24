import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";

const windowsCandidates = [
  process.env.SHELL,
  "C:\\Program Files\\Git\\bin\\sh.exe",
  "C:\\Program Files (x86)\\Git\\bin\\sh.exe",
].filter((value): value is string => Boolean(value));

const shell =
  process.platform === "win32"
    ? windowsCandidates.find((candidate) => existsSync(candidate))
    : process.env.SHELL || "sh";

if (!shell) throw new Error("No POSIX shell was found. Install Git for Windows or set SHELL.");

const result = spawnSync(shell, ["./tests/shell/codex-provider-setup.Tests.sh"], {
  cwd: process.cwd(),
  env: process.env,
  stdio: "inherit",
});

if (result.error) throw result.error;
process.exit(result.status ?? 1);
