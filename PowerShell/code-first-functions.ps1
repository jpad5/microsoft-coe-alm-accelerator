function read-variables-and-generate-snk
{
    param (
        [Parameter(Mandatory)] [String]$buildSourceDirectory,
        [Parameter(Mandatory)] [String]$orgUrl,
        [Parameter(Mandatory)] [String]$projectid,
        [Parameter(Mandatory)] [String]$buildRepositoryName,
        [Parameter(Mandatory)] [String]$variableGroupName
    )
    # Form API authentication Header
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $env:SYSTEM_ACCESSTOKEN")
    $headers.Add("Content-Type", "application/json")

    # Pass Variable Group Name
    # $variableGroupName = "alm-accelerator-variable-group"
    $variableGroupGetUrl = "$orgUrl$projectid/_apis/distributedtask/variablegroups?groupName=$variableGroupName*&queryOrder=IdDescending&api-version=6.0-preview.2"
    Write-Host "pullrequestqueryBodyResourceUrl - $variableGroupGetUrl"
    $queryResponseObject = Invoke-RestMethod -Uri $variableGroupGetUrl -Method GET -Headers $headers

    # Read all the .csproj files from the Repo
    $csProjectFiles = Get-ChildItem -Path $buildSourceDirectory\$buildRepositoryName -Filter *.csproj -Recurse
    foreach($csProjectFile in $csProjectFiles)
    {
        Write-Host ""
        if($csProjectFile.FullName -NotMatch "obj\\Release\\Fakes") #Ignore Fakes Projects
        {
            # Get Project Name
            $projectName = $csProjectFile.Name.Replace(".csproj","")
            Write-Host "projectName - $projectName"

            $xmlString = Get-Content $csProjectFile.FullName
            $xml = New-Object -TypeName System.Xml.XmlDocument
            $xml.LoadXml($xmlString)

            # Reading SNKName and Assembly Name from csproj file content
            $snkName = ""
            $assemblyName = ""
            foreach($assemblyKey in $xml.Project.PropertyGroup.AssemblyName)
            {
                if($assemblyKey)
                {
                    $assemblyName = $assemblyKey
                    break;
                }
            }
            foreach($nodeOriginatorKeyFile in $xml.Project.PropertyGroup.AssemblyOriginatorKeyFile)
            {
                if($nodeOriginatorKeyFile)
                {
                    $snkName = $nodeOriginatorKeyFile
                    break;
                }
            }

            Write-Host "snkName - " $snkName
            Write-Host "assemblyName - " $assemblyName        

            # SNK variable name convention (AssemblyName@SNKName)
            if($snkName -and $assemblyName)
            {
                #$varSNKName = [System.String]::Concat("$","(",$snkName,")")
                $varSNKName = [System.String]::Concat("$assemblyName","@",$snkName)
                Write-Host "varSNKName - $varSNKName"
                #$base64String = (Get-Variable $varSNKName).value
                $base64String = $queryResponseObject.value.variables.$varSNKName.value       
                Write-Host "base64String - " $base64String
                $filename = "$buildSourceDirectory\$buildRepositoryName\$projectName\$snkName"
                Write-Host "SNK File Path - $filename"
                $bytes = [Convert]::FromBase64String("$base64String")
                [IO.File]::WriteAllBytes($filename, $bytes)
            }
        }
    }    
}

function create-mapping-xml
{
    param (
        [Parameter(Mandatory)] [String]$buildSourceDirectory, 
        [Parameter(Mandatory)] [String]$buildRepositoryName
    )

    $csProjectFiles = Get-ChildItem -Path $buildSourceDirectory\$buildRepositoryName -Filter *.csproj -Recurse

    $seperator = ""
    $mappingsjson = "{""PluginMappings"": ["
    foreach($csProjectFile in $csProjectFiles)
    {
        if($csProjectFile.FullName -NotMatch "obj\\Release\\Fakes") #Ignore Fakes Projects
        {
            Write-Host $csProjectFile.FullName
            Write-Host "Project Name - " $csProjectFile.Name

            $projectName = $csProjectFile.Name.Replace(".csproj","")
            $mappingsjson += $seperator+"{""projectName"":"""+$projectName +""","

            $xmlString = Get-Content $csProjectFile.FullName
            $xml = New-Object -TypeName System.Xml.XmlDocument
            $xml.LoadXml($xmlString)
            $dllName = $xml.Project.PropertyGroup.AssemblyName
            $dllName=$dllName.GetValue(0).Trim()
            Write-Host "Dll Name - " $dllName
            $mappingsjson += """dllName"":"""+$dllName+"""}"
            $seperator=","
        }
    }

    $mappingsjson += "] }"

    Write-Host "Mapping json - $mappingsjson"    
    return $mappingsjson
    # Write-Host ("##vso[task.setvariable variable=pluginMappings;]$mappingsjson")
}

function create-unpack-xml
{
    param (
        [Parameter(Mandatory)] [String]$buildSourceDirectory, 
        [Parameter(Mandatory)] [String]$artifactStagingDirectory, 
        [Parameter(Mandatory)] [String]$buildRepositoryName,
        [Parameter(Mandatory)] [String]$solutionName
    )
    # Call Create Mapping XML File
    $mappingjson = create-mapping-xml $buildSourceDirectory $buildRepositoryName
    #$pluginsObject = ConvertFrom-Json '$(pluginMappings)'
    $pluginsObject = ConvertFrom-Json "$mappingjson"
    $mapContent="<?xml version=""1.0"" encoding=""utf-8""?><Mapping>"
    if($pluginsObject)
    {
        foreach($plugin in $pluginsObject.PluginMappings)
        {
            Write-Host $plugin.projectName - $plugin.dllName
            $pluginName = $plugin.dllName         
            $pluginNameCleansed = "$pluginName".Replace('.', '')
            $pluginProjectName = $plugin.projectName
            
            # Create a fake dll file; if not exists already
            $file = "$artifactStagingDirectory\$pluginName.dll"
            if(-Not (Test-Path $file))
            {
                New-Item $file -ItemType File -Value "Foo"
            }

            #$plugindllPath = "$artifactStagingDirectory\$buildRepositoryName\$pluginProjectName\bin\Release\$pluginName.dll" # Get the Built .dll path of each project
            $plugindllPath = "$artifactStagingDirectory\$pluginName.dll" # Get the fake dll
            
            $mapContent += "<FileToFile map=""$buildSourceDirectory\$buildRepositoryName\$solutionName\SolutionPackage\PluginAssemblies\**\$pluginNameCleansed.dll"" to=""$plugindllPath"" />"
        }
    }
    else
    {
        Write-Host "pluginMappings variable is either null or blank"
    }

    $mapContent += "</Mapping>"
    Write-Host "Mappings content - $mapContent"
    Set-Content "$buildRepositoryName\map_unpack.xml" $mapContent
}

function create-pack-xml
{
    param (
        [Parameter(Mandatory)] [String]$buildSourceDirectory, 
        [Parameter(Mandatory)] [String]$artifactStagingDirectory, 
        [Parameter(Mandatory)] [String]$buildRepositoryName,
        [Parameter(Mandatory)] [String]$solutionName
    )
    # Call Create Mapping XML File
    $mappingjson = create-mapping-xml $buildSourceDirectory $buildRepositoryName
    #$pluginsObject = ConvertFrom-Json '$(pluginMappings)'
    $pluginsObject = ConvertFrom-Json "$mappingjson"
    $mapContent="<?xml version=""1.0"" encoding=""utf-8""?><Mapping>"
    if($pluginsObject)
    {
        foreach($plugin in $pluginsObject.PluginMappings)
        {
            Write-Host $plugin.projectName - $plugin.dllName
            $pluginName = $plugin.dllName         
            $pluginNameCleansed = "$pluginName".Replace('.', '')
            $pluginProjectName = $plugin.projectName
            
            $plugindllPath = "$buildSourceDirectory\$buildRepositoryName\$pluginProjectName\bin\Release\$pluginName.dll" # Get the Built .dll path of each project
            
            $mapContent += "<FileToFile map=""$buildSourceDirectory\$buildRepositoryName\$solutionName\SolutionPackage\PluginAssemblies\**\$pluginNameCleansed.dll"" to=""$plugindllPath"" />"
        }
    }
    else
    {
        Write-Host "pluginMappings variable is either null or blank"
    }

    $mapContent += "</Mapping>"
    Write-Host "Mappings content - $mapContent"
    Set-Content "$buildRepositoryName\map_pack.xml" $mapContent
}

function npm-install-pcf-Projects{
    param (
        [Parameter(Mandatory)] [String]$buildSourceDirectory
    )

      $pcfProjectFiles = Get-ChildItem -Path $buildSourceDirectory -Filter *.pcfproj -Recurse
      foreach($pcfProj in $pcfProjectFiles)
      {     
        Write-Host "fullPath - "$pcfProj.FullName
        $fullPath = $pcfProj.FullName
        $pcfProjectRootPath = [System.IO.Path]::GetDirectoryName($fullPath)
              
        Write-Host "Dir Name - "$pcfProjectRootPath
        npm ci $pcfProjectRootPath --prefix $pcfProjectRootPath    
      }   
}

function npm-build-pcf-Projects{
    param (
        [Parameter(Mandatory)] [String]$buildSourceDirectory
    )

      $pcfProjectFiles = Get-ChildItem -Path $buildSourceDirectory -Filter *.pcfproj -Recurse
      foreach($pcfProj in $pcfProjectFiles)
      {     
        Write-Host "fullPath - " $pcfProj.FullName
        $fullPath = $pcfProj.FullName
        $pcfProjectRootPath = [System.IO.Path]::GetDirectoryName($fullPath)
              
        Write-Host "Dir Name - " $pcfProjectRootPath
        Set-Location -Path $pcfProjectRootPath
        # npm run build 
        npm run build -- --mode Release
      } 
}

function drop-pcf-unpacked-elements{
    param (
        [Parameter(Mandatory)] [String]$buildSourceDirectory,
        [Parameter(Mandatory)] [String]$buildRepositoryName,
        [Parameter(Mandatory)] [String]$solutionName
    )

    # Logic to form mappings for Code Components
    $pcfProjectFiles = Get-ChildItem -Path $buildSourceDirectory -Filter *.pcfproj -Recurse
    foreach($pcfProj in $pcfProjectFiles)
    {     
        Write-Host "fullPath - "$pcfProj.FullName
        $fullPath = $pcfProj.FullName
        $pcfProjectRootPath = [System.IO.Path]::GetDirectoryName($fullPath)

        Write-Host "Directory Path - " $pcfProjectRootPath

        if (-not ([string]::IsNullOrEmpty($pcfProjectRootPath)))
        {
            # Get the Control folder format {pub_Name}_{Namespace}.{ControlName}
            $manifestFile = Get-ChildItem -Path $pcfProjectRootPath -Filter ControlManifest.Input.xml -Recurse -ErrorAction SilentlyContinue -Force

            if (-not ([string]::IsNullOrEmpty($manifestFile)))
            {
                [xml]$XmlDocument = Get-Content -Path $manifestFile.FullName

                $nameSpace = $XmlDocument.selectNodes('//control') | select namespace
                $constructor = $XmlDocument.selectNodes('//control') | select constructor

                $controlNameSpace = $nameSpace.namespace
                $controlName = $constructor.constructor

                # Get Publisher name
                $nsControlName = [System.String]::Concat($controlNameSpace,".",$controlName)
                $pcfPublisherName = get-publisher-name "$buildSourceDirectory" "$buildRepositoryName" "$solutionName" "$nsControlName"

                Write-Host "$nsControlName publisher-name is - $pcfPublisherName"

                $controlPackPattern = [System.String]::Concat("$pcfPublisherName","_",$controlNameSpace,".",$controlName) #"_$nameSpace.$constructor"
                $unpackedPCFPath = "$buildSourceDirectory\$buildRepositoryName\$solutionName\SolutionPackage\Controls\$controlPackPattern\"

                # Delete all files except "ControlManifest.xml.data.xml"
                if(Test-Path $unpackedPCFPath)
                {
                    gci $unpackedPCFPath -exclude ControlManifest.xml.data.xml -recurse | foreach ($_) {if(!$_.PSIsContainer){remove-item -Force $_.fullname}}
                    Write-Host "Deleted pcf built files from - $unpackedPCFPath"
                }
                else
                {
                    Write-Host "Unpacked PCF path not found for deletion - $unpackedPCFPath"
                }
            }
        }
    }
}

function get-publisher-name{
    param (
    [Parameter(Mandatory)] [String]$buildSourceDirectory,
    [Parameter(Mandatory)] [String]$buildRepositoryName,
    [Parameter(Mandatory)] [String]$solutionName,
    [Parameter(Mandatory)] [String]$codeComponentName
)
        $solutionFilePath = "$buildSourceDirectory\$buildRepositoryName\$solutionName\SolutionPackage\Other\Solution.xml"

        Write-Host "get-publisher-name solutionFilePath - $solutionFilePath"

        if(Test-path $solutionFilePath){        
            [xml]$xmlAttr = Get-Content -Path $solutionFilePath

            $listSchemas = New-Object -TypeName 'System.Collections.ArrayList';
            $pcfSchemaDetails = $xmlAttr.ImportExportXml.SolutionManifest.RootComponents.RootComponent | Where-Object type -eq 66 |  ForEach-Object {
                $listSchemas.Add($_.schemaName);
            }                     

            foreach ($schemaName in $listSchemas){ 
                if($schemaName -like "*$codeComponentName"){
                    return "$schemaName".Split("_")[0]
                }
            }
        }

        return ""
}

function copy-pcf-build-elements{
    param (
        [Parameter(Mandatory)] [String]$buildSourceDirectory,
        [Parameter(Mandatory)] [String]$buildRepositoryName,
        [Parameter(Mandatory)] [String]$solutionName
    )

    # Logic to form mappings for Code Components
    $pcfProjectFiles = Get-ChildItem -Path $buildSourceDirectory -Filter *.pcfproj -Recurse
    foreach($pcfProj in $pcfProjectFiles)
    {     
        Write-Host "fullPath - "$pcfProj.FullName
        $fullPath = $pcfProj.FullName
        $pcfProjectRootPath = [System.IO.Path]::GetDirectoryName($fullPath)

        Write-Host "Directory Path - " $pcfProjectRootPath

        if (-not ([string]::IsNullOrEmpty($pcfProjectRootPath)))
        {
            # Get the Control folder format {pub_Name}_{Namespace}.{ControlName}
            $manifestFile = Get-ChildItem -Path $pcfProjectRootPath -Filter ControlManifest.Input.xml -Recurse -ErrorAction SilentlyContinue -Force
            Write-Host $manifestFile.FullName

            Write-Host "ManifestFile.Input.xml path - "$manifestFile.FullName
            if (-not ([string]::IsNullOrEmpty($manifestFile)))
            {
                [xml]$XmlDocument = Get-Content -Path $manifestFile.FullName

                $nameSpace = $XmlDocument.selectNodes('//control') | select namespace
                $constructor = $XmlDocument.selectNodes('//control') | select constructor

                $controlNameSpace = $nameSpace.namespace
                $controlName = $constructor.constructor

                # Get Publisher name
                $nsControlName = [System.String]::Concat($controlNameSpace,".",$controlName)
                $pcfPublisherName = get-publisher-name "$buildSourceDirectory" "$buildRepositoryName" "$solutionName" "$nsControlName"

                Write-Host "$nsControlName publisher-name is - $pcfPublisherName"

                $controlPackPattern = [System.String]::Concat("$pcfPublisherName","_",$controlNameSpace,".",$controlName) #"_$nameSpace.$constructor"

                # Built bundle.js path ($buildSourceDirectory/Project_Name/out/controls/appname)
                $builtBundlePath = "$pcfProjectRootPath\out\controls\$controlName\bundle.js"
                $builtManifestxmlPath = "$pcfProjectRootPath\out\controls\$controlName\ControlManifest.xml"

                Write-Host "builtBundlePath - " $builtBundlePath
                Write-Host "builtManifestxmlPath - " $builtManifestxmlPath

                # Unpacked bundle.js and Manifest files path
                $unpackedPath = "$buildSourceDirectory\$buildRepositoryName\$solutionName\SolutionPackage\Controls\$controlPackPattern\"

                # Copy all files from Out folder except "ControlManifest.xml.data.xml"
                $pcfBuiltOutPath = "$pcfProjectRootPath\out\controls\$controlName"
                if((Test-Path $pcfBuiltOutPath) -and (Test-Path $unpackedPath))
                {
                    foreach($file in Get-ChildItem $pcfBuiltOutPath) 
                    {
                        if($file.Name -ne "ControlManifest.xml.data.xml")
                        {
                            Copy-Item -Path $file.FullName -Destination $unpackedPath -PassThru
                            Write-Host "Copied " $file.FullName " to $unpackedPath"
                        }
                    }
                }
                else
                {
                    Write-Host "PCF Out path not found for copy - $pcfBuiltOutPath"
                }
            }
        }
    }
}

function set-assembly-version{
    param (
    [Parameter(Mandatory)] [String]$buildSourceDirectory,
    [Parameter(Mandatory)] [String]$buildRepositoryName,
    [Parameter(Mandatory)] [String]$version
)
    $AssemblyFiles = Get-ChildItem -Path "$buildSourceDirectory\$buildRepositoryName" -Filter AssemblyInfo.cs -Recurse
    foreach ($file in $AssemblyFiles) {
        $path = $file.FullName
        $ignorePattern = "// [assembly: AssemblyVersion(""1.0.*"")]"
        $pattern = '\[assembly: AssemblyVersion\("(.*)"\)\]'
        (Get-Content $path) | ForEach-Object{
             if($_ -ne $ignorePattern)
             {
                if($_ -match $pattern){
                    $dateStamp = Get-Date -format "MMdd"
                    $fileVersion = [version]$matches[1]
                    $newVersion = "{0}.{1}.{2}.{3}" -f $fileVersion.Major, $fileVersion.Minor, $dateStamp, ($fileVersion.Revision + 1)
                    Write-Host "newVersion - " $newVersion
                    '[assembly: AssemblyVersion("{0}")]' -f $newVersion
                } else {
                    # Output line as is
                    $_
                }
              }
        } | Set-Content $path
    }
}

function assemblyinfo_file_clone
{
    param (
        [Parameter(Mandatory)] [String]$buildSourceDirectory,
        [Parameter(Mandatory)] [String]$buildRepositoryName,
        [Parameter(Mandatory)] [String]$artifactStagingDirectory
    )

    $csProjectFiles = Get-ChildItem -Path $buildSourceDirectory\$buildRepositoryName -Filter *.csproj -Recurse
    foreach($csProjectFile in $csProjectFiles)
    {
        if($csProjectFile.FullName -NotMatch "obj\\Release\\Fakes") #Ignore Fakes Projects
        {
            # Get Project Name
            $projectName = $csProjectFile.Name.Replace(".csproj","")
            $currentFilePath = "$buildSourceDirectory\$buildRepositoryName\$projectName\Properties\AssemblyInfo.cs"
            $cloneFilePath = "$artifactStagingDirectory\$projectName_AssemblyInfo.cs"     
            # Copy Assembly Info files to ArtifactStagingDirectory; Will be copied back post build
            Copy-Item -Path $currentFilePath -Destination $cloneFilePath -Force
        }
    }
}

function assemblyinfo_file_restore
{
    param (
        [Parameter(Mandatory)] [String]$buildSourceDirectory,
        [Parameter(Mandatory)] [String]$buildRepositoryName,
        [Parameter(Mandatory)] [String]$artifactStagingDirectory
    )

    $csProjectFiles = Get-ChildItem -Path $buildSourceDirectory\$buildRepositoryName -Filter *.csproj -Recurse
    foreach($csProjectFile in $csProjectFiles)
    {
        if($csProjectFile.FullName -NotMatch "obj\\Release\\Fakes") #Ignore Fakes Projects
        {
            # Get Project Name
            $projectName = $csProjectFile.Name.Replace(".csproj","")
            $currentFilePath = "$buildSourceDirectory\$buildRepositoryName\$projectName\Properties\AssemblyInfo.cs"
            $cloneFilePath = "$artifactStagingDirectory\$projectName_AssemblyInfo.cs"     
            # Restore original Assembly Info files from ArtifactStagingDirectory
            Copy-Item -Path $cloneFilePath -Destination $currentFilePath -Force
        }
    }
}