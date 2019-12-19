# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#
# Unit tests for core PSRule.Requirements cmdlets
#

[CmdletBinding()]
param (

)

# Setup error handling
$ErrorActionPreference = 'Stop';
Set-StrictMode -Version latest;

if ($Env:SYSTEM_DEBUG -eq 'true') {
    $VerbosePreference = 'Continue';
}

# Setup tests paths
$rootPath = $PWD;

Import-Module (Join-Path -Path $rootPath -ChildPath out/modules/PSRule.Requirements) -Force;

$here = (Resolve-Path $PSScriptRoot).Path;
$outputPath = Join-Path -Path $rootPath -ChildPath out/tests/PSRule.Requirements.Tests/Common;
Remove-Item -Path $outputPath -Force -Recurse -Confirm:$False -ErrorAction Ignore;
$Null = New-Item -Path $outputPath -ItemType Directory -Force;

## Add tests
