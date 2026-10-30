# Contributing

A disposable Windows Sandbox that installs a chosen toolchain and logs what
runs inside it. Issues and pull requests are welcome. For anything that could
be abused before it is fixed, use the private route in
[SECURITY.md](SECURITY.md) instead of an issue.

## What runs where

- `setup.ps1` runs on the host. It resolves the profiles into
  `scripts/tools.json` and generates `sandbox.wsb` from the template; both
  outputs are git-ignored. This is the part the Pester tests exercise.
- `scripts/autostart.ps1` runs inside the sandbox, started by
  `scripts/launch.cmd` from the `.wsb` logon command. It applies the
  hardening and logging, runs the winget installs and sets up Sysmon. It can
  only be exercised in a real sandbox: say in the pull request which profiles
  you launched, whether `-Offline` was used and whether "Sandbox ready"
  appeared.
- `install.ps1` is the `irm | iex` bootstrap and tracks `main`. Keep it small
  enough to read before running.

## Adding or changing tools

Edit `tools.json` only. Every entry needs `name`, `wingetId` and `enabled`; a
tool without a winget package needs `"wingetId": ""`, `"source": "manual"` and
a `url`, and is listed for manual download at the end of setup. CI validates
exactly those keys. Keep the opt-in profiles on their own domain; `default` is
the fullstack box every session gets.

## Workflow

1. Branch from `main` and open a pull request against `main`.
2. CI (`.github/workflows/lint.yml`) runs on pull requests and on pushes to
   `main` when a `*.ps1` file, `tools.json`, the `.wsb` template, the analyzer
   settings or the workflow itself change: PSScriptAnalyzer and Pester on
   `windows-latest`, and the `tools.json` validation on Ubuntu.

## Checks

The same checks CI runs, from a clone in `pwsh`:

```powershell
# Static analysis. CI fails on Warning or Error; the settings exclude only
# PSAvoidUsingWriteHost.
Install-Module PSScriptAnalyzer -Scope CurrentUser
Get-ChildItem -Path . -Filter *.ps1 -Recurse |
    ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Settings .psscriptanalyzer.psd1 -Severity Warning,Error }

# Pester tests for setup.ps1: profile resolution, de-duplication, sandbox.wsb
# generation. They run setup.ps1 in a child pwsh against a copy under Pester's
# TestDrive, so they never touch the repository and also pass under pwsh on
# macOS and Linux. -CI writes testResults.xml, which is git-ignored.
Install-Module Pester -Scope CurrentUser -SkipPublisherCheck
Invoke-Pester -Path tests -CI
```

The `tools.json` validation is the inline script of the `validate-json` job
in `lint.yml`; `Get-Content tools.json | ConvertFrom-Json` is the quick local
syntax check.

## File rules

`.editorconfig` carries them and `.gitattributes` enforces the line endings:

- Four-space indentation in PowerShell, two in YAML, JSON, Markdown and the
  `.wsb` template.
- LF line endings and UTF-8 without BOM, except `scripts/launch.cmd`, which
  stays CRLF for `cmd.exe`.
- No binaries in the repository; `.gitignore` blocks installers. Tools come
  from winget, or are pre-staged into `scripts/` by the user for offline mode.

## License

MIT, see [LICENSE](LICENSE). Contributions are accepted under the same
license.
