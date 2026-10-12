# Entra & Intune Automation

[![CI](https://github.com/ispartaliemir32/entra-intune-automation/actions/workflows/ci.yml/badge.svg)](https://github.com/ispartaliemir32/entra-intune-automation/actions/workflows/ci.yml)
![PowerShell](https://img.shields.io/badge/PowerShell-7.2%2B-5391FE?logo=powershell&logoColor=white)
![Microsoft Graph](https://img.shields.io/badge/Microsoft%20Graph-read--only-0078D4)

Read-only PowerShell reporting for **Microsoft Entra ID** and **Microsoft Intune**. It answers three questions I keep running into in Microsoft environments:

1. Which enabled accounts have not signed in for a long time?
2. Which managed devices are not compliant, and how long since they last synced?
3. Who holds privileged directory roles?

The output is a `report.json` (consumed by [identity-device-dashboard](https://github.com/ispartaliemir32/identity-device-dashboard)) and a short `report.md`.

> All sample data in this repo is fictional (`example.com`). The project contains no employer code, tenant IDs or real user data.

## Quick start (no tenant needed)

```powershell
./scripts/Invoke-Reports.ps1 -DemoData
```

This runs against the bundled demo data in [`data/sample`](data/sample) and writes `reports/report.json` and `reports/report.md`.

## Run against your own tenant

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
./scripts/Invoke-Reports.ps1 -StaleDays 90
```

The script signs in interactively with **read-only** delegated scopes only. See [`docs/permissions.md`](docs/permissions.md). It never creates, changes or deletes anything.

## How it is built

```text
.
├── src/EntraIntuneReports.psm1   # report logic as pure, testable functions + Graph data access
├── scripts/Invoke-Reports.ps1    # entry point (demo or live)
├── data/sample/                  # fictional demo data
├── tests/                        # Pester 5 unit tests
└── .github/workflows/ci.yml      # PSScriptAnalyzer + Pester on Linux and Windows
```

Design choices:

- **Logic is separated from data access.** `Get-StaleUser`, `Get-NonCompliantDevice` and `Get-PrivilegedRoleAssignment` take plain objects, so they can be unit tested without a tenant.
- **Read-only by design.** Only `GET` calls and `*.Read.*` scopes.
- **Disabled accounts are ignored** in the stale-user report, because they are already handled.
- **Never-signed-in accounts** are only flagged when they are older than the stale window, so new joiners do not show up as noise.
- **Deterministic demo mode.** Demo data uses a fixed reference date, so the output and the tests never drift.

## Example output

```text
| Area                        | Total | Needs attention        |
|-----------------------------|------:|------------------------|
| Users (enabled: 11)         |    12 | 5 stale (>90 days)     |
| Devices                     |    10 | 5 not compliant        |
| Privileged role assignments |     6 | 6 unique principals    |
```

## Tests

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester ./tests
```

## Limitations

- Live mode is built against the documented Microsoft Graph v1.0 endpoints, but I have only exercised the report logic through the demo data and unit tests. Check the output against your own tenant before relying on it.
- `signInActivity` requires Entra ID P1 or higher. Without it, every account looks like it never signed in.
- Role assignments cover active directory role assignments. Eligible (PIM) assignments are not included yet.
- Interactive sign-in only. App-only (certificate) authentication for scheduled runs is on the list.

## Roadmap

- [ ] PIM eligible role assignments
- [ ] App-only authentication for scheduled runs
- [ ] Conditional Access policy summary
- [ ] Intune app and configuration profile assignment report

MIT licensed.
