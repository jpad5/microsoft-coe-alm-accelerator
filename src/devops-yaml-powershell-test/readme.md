# Azure DevOps Yaml Pipeline PowerShell

This sample .Net library will extract named powershell blocks from pipeline yaml files.

The extracted powershell or pwsh steps can be placed in powershell file for unit testing

For example with following example

```yml
steps:
- powershell: |
    Write-Host "Test"
  diplayName: Hello World 
```

Using the following powershell to parse and extract script

```powershell
Add-Type -LiteralPath $yamlParser
$loader = New-Object -TypeName AzureDevOps.PowerShell.Test.Loader
$loader.
```
