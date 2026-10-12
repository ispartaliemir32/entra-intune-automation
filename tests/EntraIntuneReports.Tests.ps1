#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'src' | Join-Path -ChildPath 'EntraIntuneReports.psm1'
    Import-Module $modulePath -Force
    $script:demo = Import-DemoData
}

Describe 'ConvertTo-UtcDate' {
    It 'returns $null for empty input' {
        ConvertTo-UtcDate $null | Should -BeNullOrEmpty
        ConvertTo-UtcDate '' | Should -BeNullOrEmpty
    }

    It 'parses ISO strings as UTC' {
        $d = ConvertTo-UtcDate '2026-05-14T09:12:00Z'
        $d.Kind | Should -Be ([DateTimeKind]::Utc)
        $d.Year | Should -Be 2026
        $d.Hour | Should -Be 9
    }

    It 'treats unspecified DateTime values as UTC' {
        $d = ConvertTo-UtcDate ([datetime]::new(2026, 1, 1, 12, 0, 0, [DateTimeKind]::Unspecified))
        $d.Kind | Should -Be ([DateTimeKind]::Utc)
        $d.Hour | Should -Be 12
    }
}

Describe 'Get-StaleUser' {
    BeforeAll {
        $script:stale = @(Get-StaleUser -User $demo.User -StaleDays 90 -ReferenceDate $demo.ReferenceDate)
    }

    It 'finds the five stale accounts in the demo data' {
        $stale.Count | Should -Be 5
    }

    It 'ignores disabled accounts' {
        $stale.userPrincipalName | Should -Not -Contain 'morgan.patel@example.com'
    }

    It 'does not flag accounts created inside the window that never signed in' {
        $stale.userPrincipalName | Should -Not -Contain 'robin.shaw@example.com'
    }

    It 'flags old accounts that never signed in' {
        $never = $stale | Where-Object neverSignedIn
        @($never).Count | Should -Be 1
        $never.userPrincipalName | Should -Be 'taylor.brooks@example.com'
    }

    It 'respects the boundary (89 days is fine, 92 days is stale)' {
        $stale.userPrincipalName | Should -Not -Contain 'quinn.adams@example.com'
        $stale.userPrincipalName | Should -Contain 'devon.park@example.com'
    }

    It 'sorts never-signed-in first, then oldest sign-in first' {
        $stale[0].userPrincipalName | Should -Be 'taylor.brooks@example.com'
        $stale[1].userPrincipalName | Should -Be 'casey.kim@example.com'
    }

    It 'returns an empty array for no users' {
        @(Get-StaleUser -User @() -ReferenceDate $demo.ReferenceDate).Count | Should -Be 0
    }
}

Describe 'Get-NonCompliantDevice' {
    BeforeAll {
        $script:bad = @(Get-NonCompliantDevice -Device $demo.Device -ReferenceDate $demo.ReferenceDate)
    }

    It 'returns every device that is not compliant' {
        $bad.Count | Should -Be 5
        $bad.complianceState | Should -Not -Contain 'compliant'
    }

    It 'calculates days since last sync' {
        ($bad | Where-Object deviceName -eq 'WIN-CASEY-03').daysSinceSync | Should -Be 121
    }
}

Describe 'Get-PrivilegedRoleAssignment' {
    BeforeAll {
        $script:priv = @(Get-PrivilegedRoleAssignment -RoleAssignment $demo.RoleAssignment)
    }

    It 'keeps only privileged roles' {
        $priv.Count | Should -Be 6
        $priv.roleName | Should -Not -Contain 'Helpdesk Administrator'
        $priv.roleName | Should -Not -Contain 'Directory Readers'
    }

    It 'accepts a custom list of privileged roles' {
        $custom = @(Get-PrivilegedRoleAssignment -RoleAssignment $demo.RoleAssignment -PrivilegedRole 'Helpdesk Administrator')
        $custom.Count | Should -Be 1
    }
}

Describe 'New-EntraIntuneReport' {
    BeforeAll {
        $script:report = New-EntraIntuneReport `
            -User $demo.User -Device $demo.Device -RoleAssignment $demo.RoleAssignment `
            -StaleDays 90 -ReferenceDate $demo.ReferenceDate -Mode demo
    }

    It 'builds a consistent summary' {
        $report.schemaVersion | Should -Be 1
        $report.mode | Should -Be 'demo'
        $report.summary.users.total | Should -Be 12
        $report.summary.users.enabled | Should -Be 11
        $report.summary.users.disabled | Should -Be 1
        $report.summary.users.stale | Should -Be 5
        $report.summary.devices.total | Should -Be 10
        $report.summary.devices.nonCompliant | Should -Be 5
        $report.summary.privilegedRoles.assignments | Should -Be 6
        $report.summary.privilegedRoles.uniquePrincipals | Should -Be 6
    }

    It 'counts devices per operating system' {
        $report.summary.devices.byOs.Windows | Should -Be 5
        $report.summary.devices.byOs.macOS | Should -Be 2
    }

    It 'survives a JSON round trip' {
        $json = $report | ConvertTo-Json -Depth 10
        $back = $json | ConvertFrom-Json
        $back.summary.users.stale | Should -Be 5
        @($back.staleUsers).Count | Should -Be 5
    }

    It 'renders Markdown with all sections' {
        $md = ConvertTo-ReportMarkdown -Report $report
        $md | Should -Match '## Stale users'
        $md | Should -Match '## Non-compliant devices'
        $md | Should -Match '## Privileged role assignments'
        $md | Should -Match 'taylor\.brooks@example\.com'
    }
}

Describe 'Demo data hygiene' {
    It 'only uses example.com addresses' {
        $addresses = @($demo.User.userPrincipalName) + @($demo.Device.userPrincipalName)
        foreach ($a in $addresses) { $a | Should -Match '@example\.com$' }
    }
}
