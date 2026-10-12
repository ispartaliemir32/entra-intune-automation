#Requires -Version 7.2
<#
.SYNOPSIS
    Generates a read-only Entra ID and Intune report (JSON + Markdown).

.PARAMETER DemoData
    Use the bundled fictional demo data instead of connecting to a tenant.

.PARAMETER StaleDays
    Enabled accounts without a sign-in for this many days are reported as stale.

.PARAMETER OutputPath
    Folder for report.json and report.md. Created when missing.

.EXAMPLE
    ./scripts/Invoke-Reports.ps1 -DemoData

.EXAMPLE
    ./scripts/Invoke-Reports.ps1 -StaleDays 60 -OutputPath ./reports
#>
[CmdletBinding()]
param(
    [switch]$DemoData,
    [ValidateRange(1, 3650)][int]$StaleDays = 90,
    [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'reports')
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'src' | Join-Path -ChildPath 'EntraIntuneReports.psm1') -Force

if ($DemoData) {
    $data = Import-DemoData
    $mode = 'demo'
}
else {
    $scopes = @(
        'User.Read.All'
        'AuditLog.Read.All'
        'DeviceManagementManagedDevices.Read.All'
        'RoleManagement.Read.Directory'
    )

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw 'Install the Microsoft.Graph.Authentication module first: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser'
    }

    if (-not (Get-MgContext)) {
        Connect-MgGraph -Scopes $scopes -NoWelcome
    }

    $data = Get-GraphReportData
    $mode = 'live'
}

$report = New-EntraIntuneReport `
    -User $data.User `
    -Device $data.Device `
    -RoleAssignment $data.RoleAssignment `
    -StaleDays $StaleDays `
    -ReferenceDate $data.ReferenceDate `
    -Mode $mode

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$jsonPath = Join-Path -Path $OutputPath -ChildPath 'report.json'
$mdPath = Join-Path -Path $OutputPath -ChildPath 'report.md'

$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8
ConvertTo-ReportMarkdown -Report $report | Set-Content -LiteralPath $mdPath -Encoding utf8

Write-Host "Report written to:"
Write-Host "  $((Resolve-Path -LiteralPath $jsonPath).Path)"
Write-Host "  $((Resolve-Path -LiteralPath $mdPath).Path)"
Write-Host ("Stale users: {0} | Non-compliant devices: {1} | Privileged assignments: {2}" -f `
        $report.summary.users.stale, $report.summary.devices.nonCompliant, $report.summary.privilegedRoles.assignments)
