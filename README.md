# Windows Sandbox Lab — disposable, tooled, and watched

> One command spins up a **disposable Windows Sandbox** that auto-installs the toolchain you
> pick — fullstack, data, devops, database, web, or **security/malware-analysis** — and
> **watches what software does** (Sysmon + PowerShell logging + process auditing). Fresh every
> session, isolated from your host, gone on close.

![Lint](https://github.com/26zl/windows-sandbox-lab/actions/workflows/lint.yml/badge.svg)
![License](https://img.shields.io/github/license/26zl/windows-sandbox-lab)
![Windows 11 Pro](https://img.shields.io/badge/Windows-11%20Pro-0078D6?logo=windows&logoColor=white)
![Tools via winget](https://img.shields.io/badge/tools-winget-success)

## Why

Testing a sketchy installer, a new SDK, a client's repo, or a malware sample? Doing it on your
main machine is how you end up with leftover services, registry cruft, or worse. This gives you
a throwaway, fully-provisioned Windows box in minutes — and, unlike a bare sandbox, it shows you
what ran inside it.

- **Disposable** — built-in Windows Sandbox VM; everything is gone on close.
- **Tooled** — pick a profile, winget installs the latest versions automatically.
- **Watched** — PowerShell script-block/module logging and command-line process auditing are on
  by default, plus Sysmon where the built-in Windows 11 feature is available — so you can see
  what software did.

## Use cases

- Software/package triage before installing anything on your real machine.
- Client repo, SDK, compiler, and build-tool testing in a clean Windows environment.
- Browser/API/database/data-science/devops toolboxes without polluting your workstation.
- Malware triage and reverse-engineering practice with offline mode, audit logs, and RE tools.
- Pentest lab utilities for quick, disposable network and web testing.

## Prerequisites

- Windows 11 **Pro or Enterprise**
- [Windows Sandbox](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-overview) enabled
- Sysmon monitoring needs a Windows 11 build with the built-in Sysmon feature; PowerShell +
  process-creation logging work on every supported build

## Quick start

**One-liner** (PowerShell):

```powershell
irm https://raw.githubusercontent.com/26zl/windows-sandbox-lab/main/install.ps1 | iex
start sandbox.wsb
```

**Or clone** (gives you profile selection):

```powershell
git clone https://github.com/26zl/windows-sandbox-lab.git
cd windows-sandbox-lab
.\setup.ps1                          # default dev toolchain
start sandbox.wsb                    # winget installs everything automatically
```

> Setup takes ~**10–15 minutes** inside the sandbox (longer with big profiles). A PowerShell
> window shows progress — wait until it prints **"Sandbox ready"**.

## Profiles

The **default** profile is a fullstack dev box. Add any combination of opt-in profiles — the
default is always included, and duplicates are de-duplicated automatically:

```powershell
.\setup.ps1 -Profiles datascience,web        # default + two profiles
.\setup.ps1 -Profiles security               # default + reverse-engineering tools
.\setup.ps1 -Profiles security -Offline      # hardened, network-disabled box (see below)
```

| Profile | What you get |
| --- | --- |
| **default** | Go, Rust, Python 3.13, JDK 21, Node LTS, Ruby, PHP, Zig, .NET 9 SDK+runtime, VS Build Tools, CMake, Git, 7-Zip, Sysinternals, PowerShell 7, VS Code, Notepad++ |
| **datascience** | Miniconda, uv, R, RStudio, VS Code (JupyterLab via `uv tool install`) |
| **devops** | Terraform, kubectl, k9s, Helm, AWS/Azure/gcloud CLIs *(client-only — no local containers, see note)* |
| **database** | DBeaver, PostgreSQL, SQLite, SQL Server 2022 Express, SSMS |
| **web** | Firefox, Chrome, Brave, Bruno, Postman, VS Code |
| **security** | x64dbg, Detect It Easy, PE-bear, HxD, Resource Hacker, dnSpyEx, ILSpy, System Informer, YARA, FLOSS, Wireshark, mitmproxy + Ghidra/PEStudio/capa/CyberChef/CFF Explorer (auto-listed for manual download) |
| **pentest** | Nmap, Wireshark, Burp Suite Community, ffuf (sqlmap via pip) |

All winget tools are configured in `tools.json`. Tools without a winget package are listed at
the end of setup with a download link. Add your own with their [winget ID](https://winget.run/).

> **No nested virtualization.** Windows Sandbox can't run Docker Desktop, WSL2, Hyper-V,
> minikube/kind, or Android emulators. The devops profile ships **client CLIs** that manage
> remote infrastructure — not a local container engine.

## Security / malware analysis (offline)

For analysing untrusted binaries, use `-Offline` to generate a hardened box:

```powershell
.\setup.ps1 -Profiles security -Offline
start sandbox.wsb
```

`-Offline` generates `sandbox.wsb` with **networking and clipboard disabled**, and the same
`autostart.ps1` runs in no-network mode: it applies the logging/auditing hardening and lists the
tools to bring in (no winget).
Because winget needs the network, **pre-stage your tools** (and optionally a `sysmonconfig.xml`)
into `scripts/` on the host before launching — `scripts/` is mapped read-only, so a sample can
never modify your toolchain.

> ⚠️ **Windows Sandbox is not a malware-grade isolation boundary.** VM-aware malware detects it
> (the `WDAGUtilityAccount` user, Hyper-V artifacts) and may refuse to run or change behavior, so
> a "clean" run does **not** mean a sample is safe. It shares the host kernel via Hyper-V. For
> genuinely dangerous samples, use a dedicated, snapshot-capable, air-gapped analysis VM.

## How it compares

| | this | [ThioJoe/Windows-Sandbox-Tools](https://github.com/ThioJoe/Windows-Sandbox-Tools) | [WSBEditor](https://github.com/leestevetk/WSBEditor) | [FLARE-VM](https://github.com/mandiant/flare-vm) |
| --- | :-: | :-: | :-: | :-: |
| One command, auto-installs tools | ✅ | partial | ❌ (config only) | ✅ |
| Disposable (destroyed on close) | ✅ | ✅ | ✅ | ❌ (persistent VM) |
| Built-in Sysmon + PowerShell logging | ✅ | ❌ | ❌ | partial |
| Multiple domain profiles | ✅ | ❌ | ❌ | ❌ (RE only) |
| Offline malware-analysis mode | ✅ | ❌ | ❌ | ✅ |

## Monitoring & logging

On by default so you can see what software does inside the sandbox:

- Sysmon with SwiftOnSecurity config (built-in optional feature; pinned commit +
  SHA256-verified) — process creation, network connections, file changes
- PowerShell script-block + module logging
- Process creation auditing with command-line capture
- Telemetry and Windows Error Reporting disabled

## Environment tweaks

Dark mode · file extensions, hidden & protected OS files visible · classic context menu (Win 11) ·
long path support · clipboard history · PowerShell/CMD "Open Here" · New Text/PowerShell Script
context-menu entries.

## Sandbox settings

- 12 GB RAM, ProtectedClient enabled
- Networking enabled (required for winget), vGPU/audio/video/printer disabled
- Clipboard sharing with the host is **on** (for convenience); `scripts/` mapped read-only

> "Isolated" means disk/process isolation on a disposable VM — **not** clipboard or network
> isolation. Outbound internet is open and the host clipboard is reachable from inside. For
> hostile software use the `-Offline` mode (or set `<ClipboardRedirection>Disable</ClipboardRedirection>`
> and `<Networking>Disable</Networking>` in the template yourself).

## Adding a tool

1. Find the winget ID: `winget search <name>`
2. Add an entry to `tools.json` under `default` or a profile:
   `{ "name": "...", "wingetId": "...", "enabled": true }`
   (no winget package? use `{ "name": "...", "wingetId": "", "enabled": true, "source": "manual", "url": "..." }`)
3. Disable any tool with `"enabled": false`.

## Files

```text
tools.json             ← default toolchain + opt-in profiles (winget IDs)
setup.ps1              ← run once: resolve profiles → scripts/tools.json + generate sandbox.wsb
install.ps1           ← one-liner bootstrap (irm | iex)
sandbox.wsb.template  ← sandbox config (networking/clipboard toggled for -Offline)
scripts/autostart.ps1 ← runs inside the sandbox: env, hardening, winget installs, Sysmon (-Offline = no-network variant)
scripts/launch.cmd    ← launcher (forwards -Offline to autostart.ps1)
```

Install log inside the sandbox: `%TEMP%\sandbox-install.log`
