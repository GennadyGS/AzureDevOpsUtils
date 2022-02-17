@{
    Rules = @{
        PSAvoidUsingCmdletAliases = @{
            allowlist = @('%', '?')
        }
    }
    ExcludeRules = @('PSAvoidUsingWriteHost')
}