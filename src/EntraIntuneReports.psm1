#Requires -Version 7.2
<#
.SYNOPSIS
    Read-only reporting helpers for Microsoft Entra ID and Microsoft Intune.

.DESCRIPTION
    The report logic (stale users, non-compliant devices, privileged role
    assignments) is written as pure functions that take plain objects, so it can
    be unit tested without a tenant. Data can come from the bundled demo data or
    from Microsoft Graph (read-only scopes only).
#>

Set-StrictMode -Version 1.0

$script:DefaultPrivilegedRoles = @(
    'Global Administrator'
    'Privileged Role Administrator'
    'Security Administrator'
    'Intune Administrator'
    'User Administrator'
    'Application Administrator'
    'Exchange Administrator'
    'Conditional Access Administrator'
)

$script:DemoReferenceDate = [datetime]::new(2026, 10, 1, 0, 0, 0, [DateTimeKind]::Utc)

#region Helpers

function ConvertTo-UtcDate {
    <#
    .SYNOPSIS
        Converts a string or DateTime to a UTC DateTime. Returns $null for empty input.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        $Value
    )

    if ($null -eq $Value -or "$Value" -eq '') { return $null }

    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) {
            return [datetime]::SpecifyKind($Value, [DateTimeKind]::Utc)
        }
        return $Value.ToUniversalTime()
    }

    $styles = [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal
    return [datetime]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, $styles)
}

function Get-DaysBetween {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][datetime]$From,
        [Parameter(Mandatory)][datetime]$To
    )
    return [int][math]::Floor(($To - $From).TotalDays)
}

function Format-IsoDate {
    [CmdletBinding()]
    param([AllowNull()][Nullable[datetime]]$Value)
    if ($null -eq $Value) { return $null }
    return $Value.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
}

#endregion

#region Pure report functions

function Get-StaleUser {
    <#
    .SYNOPSIS
        Returns enabled accounts that have not signed in within the given period.
    .DESCRIPTION
        An account is stale when it is enabled and either its last sign-in is older
        than the cutoff, or it never signed in and was created before the cutoff.
        Disabled accounts are ignored on purpose: they are already handled.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$User,
        [ValidateRange(1, 3650)][int]$StaleDays = 90,
        [datetime]$ReferenceDate = [datetime]::UtcNow
    )

    $reference = ConvertTo-UtcDate $ReferenceDate
    $cutoff = $reference.AddDays(-$StaleDays)

    $result = foreach ($u in $User) {
        if (-not $u.accountEnabled) { continue }

        $lastSignIn = $null
        if ($u.signInActivity) {
            $lastSignIn = ConvertTo-UtcDate $u.signInActivity.lastSignInDateTime
        }

        if ($lastSignIn) {
            $isStale = $lastSignIn -lt $cutoff
            $days = Get-DaysBetween -From $lastSignIn -To $reference
        }
        else {
            $created = ConvertTo-UtcDate $u.createdDateTime
            $isStale = ($null -ne $created) -and ($created -lt $cutoff)
            $days = $null
        }

        if ($isStale) {
            [pscustomobject][ordered]@{
                displayName       = $u.displayName
                userPrincipalName = $u.userPrincipalName
                lastSignInDate    = Format-IsoDate $lastSignIn
                daysSinceSignIn   = $days
                neverSignedIn     = ($null -eq $lastSignIn)
            }
        }
    }

    return @($result | Sort-Object -Property @{ Expression = { if ($null -eq $_.daysSinceSignIn) { [int]::MaxValue } else { $_.daysSinceSignIn } }; Descending = $true })
}

function Get-NonCompliantDevice {
    <#
    .SYNOPSIS
        Returns Intune managed devices whose compliance state is not 'compliant'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Device,
        [datetime]$ReferenceDate = [datetime]::UtcNow
    )

    $reference = ConvertTo-UtcDate $ReferenceDate

    $result = foreach ($d in $Device) {
        if ($d.complianceState -eq 'compliant') { continue }

        $lastSync = ConvertTo-UtcDate $d.lastSyncDateTime
        [pscustomobject][ordered]@{
            deviceName        = $d.deviceName
            operatingSystem   = $d.operatingSystem
            osVersion         = $d.osVersion
            complianceState   = $d.complianceState
            userPrincipalName = $d.userPrincipalName
            lastSyncDate      = Format-IsoDate $lastSync
            daysSinceSync     = if ($lastSync) { Get-DaysBetween -From $lastSync -To $reference } else { $null }
        }
    }

    return @($result | Sort-Object -Property deviceName)
}

function Get-PrivilegedRoleAssignment {
    <#
    .SYNOPSIS
        Filters role assignments down to the roles considered privileged.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$RoleAssignment,
        [string[]]$PrivilegedRole = $script:DefaultPrivilegedRoles
    )

    $result = foreach ($a in $RoleAssignment) {
        if ($a.roleName -in $PrivilegedRole) {
            [pscustomobject][ordered]@{
                roleName      = $a.roleName
                principalName = $a.principalName
                principalType = $a.principalType
            }
        }
    }

    return @($result | Sort-Object -Property roleName, principalName)
}

function New-EntraIntuneReport {
    <#
    .SYNOPSIS
        Builds the combined report object that is written to JSON.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$User,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Device,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$RoleAssignment,
        [ValidateRange(1, 3650)][int]$StaleDays = 90,
        [datetime]$ReferenceDate = [datetime]::UtcNow,
        [ValidateSet('demo', 'live')][string]$Mode = 'live'
    )

    $reference = ConvertTo-UtcDate $ReferenceDate

    $stale = @(Get-StaleUser -User $User -StaleDays $StaleDays -ReferenceDate $reference)
    $nonCompliant = @(Get-NonCompliantDevice -Device $Device -ReferenceDate $reference)
    $privileged = @(Get-PrivilegedRoleAssignment -RoleAssignment $RoleAssignment)

    $devicesByOs = [ordered]@{}
    foreach ($group in ($Device | Group-Object -Property operatingSystem | Sort-Object Name)) {
        $devicesByOs[$group.Name] = $group.Count
    }

    $enabledUsers = @($User | Where-Object { $_.accountEnabled }).Count

    return [pscustomobject][ordered]@{
        schemaVersion       = 1
        generatedAt         = Format-IsoDate $reference
        mode                = $Mode
        staleDays           = $StaleDays
        summary             = [pscustomobject][ordered]@{
            users           = [pscustomobject][ordered]@{
                total    = @($User).Count
                enabled  = $enabledUsers
                disabled = @($User).Count - $enabledUsers
                stale    = $stale.Count
            }
            devices         = [pscustomobject][ordered]@{
                total        = @($Device).Count
                nonCompliant = $nonCompliant.Count
                byOs         = [pscustomobject]$devicesByOs
            }
            privilegedRoles = [pscustomobject][ordered]@{
                assignments      = $privileged.Count
                uniquePrincipals = @($privileged | Select-Object -ExpandProperty principalName -Unique).Count
            }
        }
        staleUsers          = $stale
        nonCompliantDevices = $nonCompliant
        privilegedRoles     = $privileged
    }
}

function ConvertTo-ReportMarkdown {
    <#
    .SYNOPSIS
        Renders the report object as a short Markdown summary.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][object]$Report)

    $s = $Report.summary
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Entra ID and Intune report')
    $lines.Add('')
    $lines.Add("Generated: $($Report.generatedAt) (mode: $($Report.mode))")
    $lines.Add('')
    $lines.Add('| Area | Total | Needs attention |')
    $lines.Add('|---|---:|---:|')
    $lines.Add("| Users (enabled: $($s.users.enabled)) | $($s.users.total) | $($s.users.stale) stale (>$($Report.staleDays) days) |")
    $lines.Add("| Devices | $($s.devices.total) | $($s.devices.nonCompliant) not compliant |")
    $lines.Add("| Privileged role assignments | $($s.privilegedRoles.assignments) | $($s.privilegedRoles.uniquePrincipals) unique principals |")
    $lines.Add('')

    $lines.Add('## Stale users')
    $lines.Add('')
    if (@($Report.staleUsers).Count -eq 0) { $lines.Add('None.') }
    else {
        $lines.Add('| User | Last sign-in | Days |')
        $lines.Add('|---|---|---:|')
        foreach ($u in $Report.staleUsers) {
            $last = if ($u.neverSignedIn) { 'never' } else { $u.lastSignInDate }
            $days = if ($null -eq $u.daysSinceSignIn) { '-' } else { $u.daysSinceSignIn }
            $lines.Add("| $($u.userPrincipalName) | $last | $days |")
        }
    }
    $lines.Add('')

    $lines.Add('## Non-compliant devices')
    $lines.Add('')
    if (@($Report.nonCompliantDevices).Count -eq 0) { $lines.Add('None.') }
    else {
        $lines.Add('| Device | OS | State | Days since sync |')
        $lines.Add('|---|---|---|---:|')
        foreach ($d in $Report.nonCompliantDevices) {
            $lines.Add("| $($d.deviceName) | $($d.operatingSystem) $($d.osVersion) | $($d.complianceState) | $($d.daysSinceSync) |")
        }
    }
    $lines.Add('')

    $lines.Add('## Privileged role assignments')
    $lines.Add('')
    if (@($Report.privilegedRoles).Count -eq 0) { $lines.Add('None.') }
    else {
        $lines.Add('| Role | Principal | Type |')
        $lines.Add('|---|---|---|')
        foreach ($r in $Report.privilegedRoles) {
            $lines.Add("| $($r.roleName) | $($r.principalName) | $($r.principalType) |")
        }
    }

    return ($lines -join [Environment]::NewLine) + [Environment]::NewLine
}

#endregion

#region Data sources

function Import-DemoData {
    <#
    .SYNOPSIS
        Loads the bundled, fictional demo data.
    #>
    [CmdletBinding()]
    param(
        [string]$Path = (Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'data' | Join-Path -ChildPath 'sample')
    )

    $read = {
        param($directory, $name)
        $file = Join-Path -Path $directory -ChildPath $name
        if (-not (Test-Path -LiteralPath $file)) { throw "Demo data file not found: $file" }
        @(Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -Depth 10)
    }

    return [pscustomobject]@{
        User           = & $read $Path 'users.json'
        Device         = & $read $Path 'devices.json'
        RoleAssignment = & $read $Path 'role-assignments.json'
        ReferenceDate  = $script:DemoReferenceDate
    }
}

function Invoke-GraphPaged {
    <#
    .SYNOPSIS
        GET a Microsoft Graph collection and follow @odata.nextLink. Read-only.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri)

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $page = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject
        if ($page.value) { $items.AddRange(@($page.value)) }
        $next = $page.'@odata.nextLink'
    }
    return $items.ToArray()
}

function Get-GraphReportData {
    <#
    .SYNOPSIS
        Reads users, managed devices and directory role assignments from Microsoft Graph.
    .DESCRIPTION
        Requires an existing Connect-MgGraph session with these read-only scopes:
        User.Read.All, AuditLog.Read.All, DeviceManagementManagedDevices.Read.All,
        RoleManagement.Read.Directory. signInActivity needs Entra ID P1 or higher.
    #>
    [CmdletBinding()]
    param()

    $users = Invoke-GraphPaged -Uri '/v1.0/users?$select=id,displayName,userPrincipalName,accountEnabled,createdDateTime,signInActivity&$top=999'

    $devices = Invoke-GraphPaged -Uri '/v1.0/deviceManagement/managedDevices?$select=id,deviceName,operatingSystem,osVersion,complianceState,lastSyncDateTime,userPrincipalName'

    $definitions = Invoke-GraphPaged -Uri '/v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName'
    $roleNames = @{}
    foreach ($def in $definitions) { $roleNames[$def.id] = $def.displayName }

    $assignments = Invoke-GraphPaged -Uri '/v1.0/roleManagement/directory/roleAssignments?$expand=principal'
    $roleAssignments = foreach ($a in $assignments) {
        $type = ([string]$a.principal.'@odata.type') -replace '^#microsoft\.graph\.', ''
        [pscustomobject]@{
            roleName      = $roleNames[$a.roleDefinitionId]
            principalName = if ($a.principal.userPrincipalName) { $a.principal.userPrincipalName } else { $a.principal.displayName }
            principalType = $type
        }
    }

    return [pscustomobject]@{
        User           = @($users)
        Device         = @($devices)
        RoleAssignment = @($roleAssignments)
        ReferenceDate  = [datetime]::UtcNow
    }
}

#endregion

Export-ModuleMember -Function @(
    'ConvertTo-UtcDate'
    'Get-StaleUser'
    'Get-NonCompliantDevice'
    'Get-PrivilegedRoleAssignment'
    'New-EntraIntuneReport'
    'ConvertTo-ReportMarkdown'
    'Import-DemoData'
    'Get-GraphReportData'
)
