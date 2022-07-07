function ExtractPowerShell($yamlFile, $powerShellFile) {
    $yamlParser = "$PSScriptRoot\..\..\..\src\devops-yaml-powershell-test\bin\Release\net6.0\publish\devops-yaml-powershell-test.dll"

    if ( Test-Path $yamlParser ) {
        Add-Type -LiteralPath $yamlParser
    } else {
        pushd
        Write-Host "$PSScriptRoot\..\..\..\src\devops-yaml-powershell-test"
        cd "$PSScriptRoot\..\..\..\src\devops-yaml-powershell-test"
        dotnet publish -c Release
        popd
        Add-Type -LiteralPath $yamlParser
    }

    $yaml = (Get-Content $yamlFile -Raw)
    
    $loader = New-Object -TypeName AzureDevOps.PowerShell.Test.Loader

    Write-Host  $powerShellFile

    $parent = [System.IO.Path]::GetDirectoryName($powerShellFile)

    if ( ! (Test-Path $parent) ) {
        New-Item -Path $parent -ItemType directory
    }

    $loader.Parse($yaml) | Out-File -FilePath $powerShellFile
}
