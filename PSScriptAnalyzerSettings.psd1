@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # The entry script prints a short console summary for interactive use.
        'PSAvoidUsingWriteHost'
        # New-EntraIntuneReport only builds an in-memory object; it changes no system state.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
