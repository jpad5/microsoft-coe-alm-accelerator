# Azure DevOps Yaml Pipeline PowerShell

This sample .Net library will extract named powershell blocks from pipeline yaml files.

The extracted powershell or pwsh steps can be placed in powershell file for unit testing

For example with following example

```yml
steps:
- powershell: |
    Write-Host "Test"
  displayName: Hello World 
```

Using the following PowerShell to parse and extract script

```powershell
dotnet publish -c Release
$yamlParser = "./bin/Release/net6.0/publish/devops-yaml-powershell-test.dll"
Add-Type -LiteralPath $yamlParser
$loader = New-Object -TypeName AzureDevOps.PowerShell.Test.Loader
$yaml = "
steps:
- powershell: |
    Write-Host 'Test'
  displayName: Hello World 
"
$loader.Parse($yaml) | Out-File -Name test.ps1
```
