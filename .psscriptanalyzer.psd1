@{
    ExcludeRules = @(
        # Write-Host is intentional — we need colored console output in the sandbox
        'PSAvoidUsingWriteHost',
        # BOM is unnecessary and can cause issues with some tools
        'PSUseBOMForUnicodeEncodedFile'
    )
}
