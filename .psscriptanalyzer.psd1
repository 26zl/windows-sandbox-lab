@{
    ExcludeRules = @(
        # Write-Host is intentional - we need colored console output in the sandbox
        'PSAvoidUsingWriteHost'
    )
}
