# Windows Sandbox — Fast & Secure Software Testing

Disposable Windows Sandbox for fast and secure testing of software you'd rather not install on your main machine. Every session starts clean, runs isolated from your host, and is destroyed on close — nothing persists. One config file, one command, plug and play.

## Prerequisites

- Windows 10/11 Pro or Enterprise
- [Windows Sandbox](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-overview) enabled

## Quick Start

```powershell
git clone https://github.com/26zl/windows-sandbox.git
cd windows-sandbox
.\setup.ps1         # generate sandbox.wsb (instant)
start sandbox.wsb   # launch sandbox — winget installs everything automatically
```

> Setup takes a few minutes inside the sandbox. A PowerShell window shows progress — wait until it says **"Sandbox ready"** before you start.

## Tools

Configured in `tools.json`. Disable any tool with `"enabled": false`. Add new tools with their [winget ID](https://winget.run/).

| Category | Tools |
| -------- | ----- |
| **Editor** | Notepad++ |
| **Languages** | Go, Rust, Python 3.13, Amazon Corretto (JDK 21), Node.js LTS, Ruby 3.3, PHP 8.4, Zig |
| **Build tools** | Visual Studio Build Tools (C++ workload), CMake |
| **Utilities** | 7-Zip, Git, Sysinternals Suite |
| **Runtime** | VC++ Redist x64+x86, .NET 9 Desktop Runtime, .NET 9 SDK, PowerShell 7 |

All tools are installed via **winget** — always latest versions, no URLs to maintain.

## Security Hardening

Applied automatically on sandbox startup:

- Sysmon with SwiftOnSecurity config
- PowerShell script block + module logging
- Process creation auditing with command-line capture
- Telemetry and Windows Error Reporting disabled

## Environment Tweaks

- Dark mode
- File extensions, hidden files, and protected OS files visible
- Classic context menu (Windows 11)
- Long path support, clipboard history
- PowerShell/CMD "Open Here" context menu entries
- New Text Document / PowerShell Script in context menu

## Sandbox Settings

- 12 GB RAM, ProtectedClient enabled
- Networking enabled (required for winget), vGPU/audio/video/printer disabled
- `scripts/` mapped read-only

## Adding a Tool

1. Find the winget ID: `winget search <name>`
2. Add entry in `tools.json`: `{ "name": "...", "wingetId": "...", "enabled": true }`
3. Update this README

## Files

```text
tools.json               ← all tools (winget IDs)
setup.ps1                ← run once: generate sandbox.wsb
sandbox.wsb.template     ← sandbox config template
scripts/autostart.ps1    ← runs inside sandbox automatically
```

Install log inside sandbox: `%TEMP%\sandbox-install.log`
