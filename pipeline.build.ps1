
[CmdletBinding()]
param (
    [Parameter(Mandatory = $False)]
    [String]$Build = '0.0.1',

    [Parameter(Mandatory = $False)]
    [String]$Configuration = 'Debug',

    [Parameter(Mandatory = $False)]
    [String]$ApiKey,

    [Parameter(Mandatory = $False)]
    [Switch]$CodeCoverage = $False,

    [Parameter(Mandatory = $False)]
    [String]$ArtifactPath = (Join-Path -Path $PWD -ChildPath out/modules)
)

Write-Host -Object "[Pipeline] -- PWD: $PWD" -ForegroundColor Green;
Write-Host -Object "[Pipeline] -- ArtifactPath: $ArtifactPath" -ForegroundColor Green;
Write-Host -Object "[Pipeline] -- BuildNumber: $($Env:BUILD_BUILDNUMBER)" -ForegroundColor Green;
Write-Host -Object "[Pipeline] -- SourceBranch: $($Env:BUILD_SOURCEBRANCH)" -ForegroundColor Green;
Write-Host -Object "[Pipeline] -- SourceBranchName: $($Env:BUILD_SOURCEBRANCHNAME)" -ForegroundColor Green;

if ($Env:SYSTEM_DEBUG -eq 'true') {
    $VerbosePreference = 'Continue';
}

if ($Env:BUILD_SOURCEBRANCH -like '*/tags/*' -and $Env:BUILD_SOURCEBRANCHNAME -like 'v0.*') {
    $Build = $Env:BUILD_SOURCEBRANCHNAME.Substring(1);
}

$version = $Build;
$versionSuffix = [String]::Empty;

if ($version -like '*-*') {
    [String[]]$versionParts = $version.Split('-', [System.StringSplitOptions]::RemoveEmptyEntries);
    $version = $versionParts[0];

    if ($versionParts.Length -eq 2) {
        $versionSuffix = $versionParts[1];
    }
}

Write-Host -Object "[Pipeline] -- Using version: $version" -ForegroundColor Green;
Write-Host -Object "[Pipeline] -- Using versionSuffix: $versionSuffix" -ForegroundColor Green;

if ($Env:coverage -eq 'true') {
    $CodeCoverage = $True;
}

# Copy the PowerShell modules files to the destination path
function CopyModuleFiles {
    param (
        [Parameter(Mandatory = $True)]
        [String]$Path,

        [Parameter(Mandatory = $True)]
        [String]$DestinationPath
    )

    process {
        $sourcePath = Resolve-Path -Path $Path;

        Get-ChildItem -Path $sourcePath -Recurse -File -Include *.ps1,*.psm1,*.psd1,*.ps1xml,*.yaml | Where-Object -FilterScript {
            ($_.FullName -notmatch '(\.(cs|csproj)|(\\|\/)(obj|bin))')
        } | ForEach-Object -Process {
            $filePath = $_.FullName.Replace($sourcePath, $destinationPath);

            $parentPath = Split-Path -Path $filePath -Parent;

            if (!(Test-Path -Path $parentPath)) {
                $Null = New-Item -Path $parentPath -ItemType Directory -Force;
            }

            Copy-Item -Path $_.FullName -Destination $filePath -Force;
        };
    }
}

task VersionModule ModuleDependencies, {
    $modulePath = Join-Path -Path $ArtifactPath -ChildPath PSRule.Requirements;
    $manifestPath = Join-Path -Path $modulePath -ChildPath PSRule.Requirements.psd1;
    Write-Verbose -Message "[VersionModule] -- Checking module path: $modulePath";

    if (![String]::IsNullOrEmpty($Build)) {
        # Update module version
        if (![String]::IsNullOrEmpty($version)) {
            Write-Verbose -Message "[VersionModule] -- Updating module manifest ModuleVersion";
            Update-ModuleManifest -Path $manifestPath -ModuleVersion $version;
        }

        # Update pre-release version
        if (![String]::IsNullOrEmpty($versionSuffix)) {
            Write-Verbose -Message "[VersionModule] -- Updating module manifest Prerelease";
            Update-ModuleManifest -Path $manifestPath -Prerelease $versionSuffix;
        }
    }

    $manifest = Test-ModuleManifest -Path $manifestPath;
    $requiredModules = $manifest.RequiredModules | ForEach-Object -Process {
        if ($_.Name -eq 'PSRule' -and $Configuration -eq 'Release') {
            @{ ModuleName = 'PSRule'; ModuleVersion = '0.12.0' }
        }
        elseif ($_.Name -eq 'Requirements' -and $Configuration -eq 'Release') {
            @{ ModuleName = 'Requirements'; ModuleVersion = '2.3.4' }
        }
        else {
            @{ ModuleName = $_.Name; ModuleVersion = $_.Version }
        }
    };
    Update-ModuleManifest -Path $manifestPath -RequiredModules $requiredModules;
}

# Synopsis: Publish to PowerShell Gallery
task ReleaseModule VersionModule, {
    $modulePath = (Join-Path -Path $ArtifactPath -ChildPath PSRule.Requirements);
    Write-Verbose -Message "[ReleaseModule] -- Checking module path: $modulePath";

    if (!(Test-Path -Path $modulePath)) {
        Write-Error -Message "[ReleaseModule] -- Module path does not exist";
    }
    elseif (![String]::IsNullOrEmpty($ApiKey)) {
        Publish-Module -Path $modulePath -NuGetApiKey $ApiKey;
    }
}

# Synopsis: Install NuGet provider
task NuGet {
    if ($Null -eq (Get-PackageProvider -Name NuGet -ErrorAction Ignore)) {
        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser;
    }
}

# Synopsis: Install Pester module
task Pester NuGet, {
    if ($Null -eq (Get-InstalledModule -Name Pester -MinimumVersion 4.9.0 -ErrorAction Ignore)) {
        Install-Module -Name Pester -MinimumVersion 4.9.0 -Scope CurrentUser -Force -SkipPublisherCheck;
    }
    Import-Module -Name Pester -Verbose:$False;
}

# Synopsis: Install PSScriptAnalyzer module
task PSScriptAnalyzer NuGet, {
    if ($Null -eq (Get-InstalledModule -Name PSScriptAnalyzer -MinimumVersion 1.18.3 -ErrorAction Ignore)) {
        Install-Module -Name PSScriptAnalyzer -MinimumVersion 1.18.3 -Scope CurrentUser -Force;
    }
    Import-Module -Name PSScriptAnalyzer -Verbose:$False;
}

# Synopsis: Install PSRule
task PSRule NuGet, {
    if ($Null -eq (Get-InstalledModule -Name PSRule -MinimumVersion 0.12.0 -ErrorAction Ignore)) {
        Install-Module -Name PSRule -Repository PSGallery -MinimumVersion 0.12.0 -Scope CurrentUser -Force;
    }
    Import-Module -Name PSRule -Verbose:$False;
}

# Synopsis: Install PlatyPS module
task platyPS {
    if ($Null -eq (Get-InstalledModule -Name PlatyPS -MinimumVersion 0.14.0 -ErrorAction Ignore)) {
        Install-Module -Name PlatyPS -Scope CurrentUser -MinimumVersion 0.14.0 -Force;
    }
    Import-Module -Name PlatyPS -Verbose:$False;
}

task Requirements {
    if ($Null -eq (Get-InstalledModule -Name Requirements -MinimumVersion 2.3.4 -ErrorAction Ignore)) {
        Install-Module -Name Requirements -Scope CurrentUser -MinimumVersion 2.3.4 -Force;
    }
    Import-Module -Name Requirements -Verbose:$False;
}

# Synopsis: Install module dependencies
task ModuleDependencies NuGet, PSRule, Requirements, {
}

task CopyModule {
    CopyModuleFiles -Path src/PSRule.Requirements -DestinationPath out/modules/PSRule.Requirements;
}

# Synopsis: Build modules only
task BuildModule CopyModule

task TestRules PSRule, Pester, PSScriptAnalyzer, {
    # Run Pester tests
    $pesterParams = @{ Path = (Join-Path -Path $PWD -ChildPath tests/PSRule.Requirements.Tests); OutputFile = 'reports/pester-unit.xml'; OutputFormat = 'NUnitXml'; PesterOption = @{ IncludeVSCodeMarker = $True }; PassThru = $True; };

    if ($CodeCoverage) {
        $pesterParams.Add('CodeCoverage', (Join-Path -Path $PWD -ChildPath 'out/modules/**/*.psm1'));
        $pesterParams.Add('CodeCoverageOutputFile', (Join-Path -Path $PWD -ChildPath reports/pester-coverage.xml));
    }

    if (!(Test-Path -Path reports)) {
        $Null = New-Item -Path reports -ItemType Directory -Force;
    }

    $results = Invoke-Pester @pesterParams;

    # Throw an error if pester tests failed
    if ($Null -eq $results) {
        throw 'Failed to get Pester test results.';
    }
    elseif ($results.FailedCount -gt 0) {
        throw "$($results.FailedCount) tests failed.";
    }
}

# Synopsis: Run script analyzer
task Analyze Build, PSScriptAnalyzer, {
    Invoke-ScriptAnalyzer -Path out/modules/PSRule.Requirements;
}

# Synopsis: Build help
task BuildHelp BuildModule, PlatyPS, {
}

task ScaffoldHelp Build, {
    Import-Module (Join-Path -Path $PWD -ChildPath out/modules/PSRule.Requirements) -Force;
    Update-MarkdownHelp -Path '.\docs\commands\PSRule.Requirements\en-US';
}

# Synopsis: Add shipit build tag
task TagBuild {
    if ($Null -ne $Env:BUILD_DEFINITIONNAME) {
        Write-Host "`#`#vso[build.addbuildtag]shipit";
    }
}

# Synopsis: Remove temp files.
task Clean {
    Remove-Item -Path out,reports -Recurse -Force -ErrorAction SilentlyContinue;
}

task Build Clean, BuildModule, VersionModule, BuildHelp

task Test Build, TestRules

task Release ReleaseModule, TagBuild

task . Build, Test
