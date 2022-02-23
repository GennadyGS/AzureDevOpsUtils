@{
    Rules = @{
        PSAvoidUsingCmdletAliases = @{
            allowlist = @('%', '?')
        }
    }
    ExcludeRules = @('PSAvoidUsingWriteHost', 'PSAvoidUsingInvokeExpression')
}