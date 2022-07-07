BeforeAll {
    Import-module "$(Get-Location)\..\testHelper.ps1" -Force
    ExtractPowerShell "$(Get-Location)\..\..\..\..\Pipelines\Templates\activate-flows.yml" "$(Get-Location)\..\temp\activate-flows.ps1"
}

Describe 'ActivateFlowUnit' {
    It 'Happy Path' {  
        $env:POWERSHELLPATH = [System.IO.Path]::GetFullPath("$(Get-Location)\..\..\..")
        function EnvironmentId() { return "Test1" }

        . "$env:POWERSHELLPATH/activate-flows.ps1"
       
        . "..\temp\activate-flows.ps1"

        Mock 'Invoke-ActivateFlows' { } -Verifiable
        
        ActivateFlows

        Assert-MockCalled -CommandName 'Invoke-ActivateFlows'
    }

    It 'Error' {  
        $env:POWERSHELLPATH = [System.IO.Path]::GetFullPath("$(Get-Location)\..\..\..")
        function EnvironmentId() { return "Test1" }

        . "$env:POWERSHELLPATH/activate-flows.ps1"
       
        . "..\temp\activate-flows.ps1"

        $global:customExit = $true
        $global:customExitCode = 0

        Mock 'Invoke-ActivateFlows' {throw "Error" } -Verifiable
        
        ActivateFlows

        Assert-MockCalled -CommandName 'Invoke-ActivateFlows'
        $customExitCode | Should -Be 1
    }
}