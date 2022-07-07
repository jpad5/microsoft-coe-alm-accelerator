// Copyright (c) .Microsoft Copoeration. All rights reserved.
// Licensed under the MIT License, Version 2.0. See License.txt in the project root for license information.

using System.Dynamic;
using YamlDotNet.Core.Events;
using YamlDotNet.RepresentationModel;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.NamingConventions;
using YamlDotNet.Serialization.NodeTypeResolvers;
using System.Text;

namespace AzureDevOps.PowerShell.Test;

/// <summary>
/// Load Azure DevOps Pipeline yaml pipeline files
/// </summary>
public class Loader
{
    /// <summary>
    /// Parse yaml and return PowerShell functions for named steps
    /// </summary>
    /// <param name="yaml">The Azure DevOps pipeline to parse</param>
    /// <returns>The PowerShell script that represents named PowerShell pipeline task steps</returns>
    public string Parse(string yaml)
    {   
        using ( var textStream = new StringReader(yaml)) {
            var deserializer = new DeserializerBuilder().Build(); 
            var yamlObject = deserializer.Deserialize(textStream); 

            StringBuilder results = new StringBuilder();
            results.AppendLine("# ----------------------------------------------------------------------------");
            results.AppendLine("# Generated PowerShell");
            results.AppendLine("# ----------------------------------------------------------------------------");

            dynamic yamlData = (dynamic)yamlObject;

            dynamic steps = yamlData["steps"] as dynamic;
           
            foreach ( dynamic child in steps) {
                string powershell = "";
                string displayName = "";
                try {
                    
                    if ( child.ContainsKey("displayName") && ! String.IsNullOrEmpty(child["powershell"]) ) {
                        displayName = child["displayName"];
                        powershell = child["powershell"];
                    }
                } catch {

                }

                try {
                    if ( child.ContainsKey("displayName") && ! String.IsNullOrEmpty(child["pwsh"]) ) {
                        displayName = child["displayName"];
                        powershell = child["pwsh"];
                    }
                } catch {

                }

                if ( !string.IsNullOrEmpty("displayName") && ! String.IsNullOrEmpty(powershell) ) {
                    results.AppendLine(CreateFunctionName(displayName, powershell) + " {");
                    results.AppendLine(powershell);
                    results.AppendLine("}");
                }
            }


            return results.ToString();
        }
    }

    static string CreateFunctionName(string name, string powershell) {
        StringBuilder results = new StringBuilder();
        results.Append(name.Substring(0,1).ToUpper());
        for ( var i = 1; i < name.Length; i++ ) {
            if ( name.Substring(i,1) == " " ) {
                continue;
            }
            if ( name.Substring(i-1) == " " ) {
                results.Append(name.Substring(i,1).ToUpper());
            } else {
                results.Append(name.Substring(i,1));
            }
        }
        return "function " + results.ToString() + "()";
    }

    static void FindNodes(YamlMappingNode node, Action<YamlNode> action)
    {
        action(node);
    }
}
