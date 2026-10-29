<#
.SYNOPSIS
Queues a build and watches it through completion.
.PARAMETER PipelineResources
Maps YAML pipeline resource aliases to hashtables with DefinitionName (source
pipeline name in the current project) and BuildNumber (display build number prefix).
Prefixes are resolved to full display build numbers and must match exactly one build.
Missing or ambiguous matches fail before queuing the pipeline; use a more specific
prefix if multiple builds match. Unspecified resources retain their pipeline defaults.
.EXAMPLE
RunBuild.ps1 NGS.Dash.ClaimApi.AKS.DeployImage -PipelineResources @{ ClaimApiBuild = @{ DefinitionName = 'NGS.Dash.ClaimApi.AKS.BuildAndPublish'; BuildNumber = '2026.10.28-preview-releases.27' } }
#>
param (
    [Parameter(Mandatory=$true)] $definitionName,
    $sourceBranch,
    $repositoryName,
    $remoteName = "origin",
    [hashtable] $parameters = @{},
    [string[]]$preapprovedStages = @(),
    [hashtable]$pipelineResources = @{}
)

foreach ($alias in $pipelineResources.Keys) {
    $selection = $pipelineResources[$alias]
    if ([string]::IsNullOrWhiteSpace($alias) -or
        $selection -isnot [hashtable] -or
        $selection.DefinitionName -isnot [string] -or
        [string]::IsNullOrWhiteSpace($selection.DefinitionName) -or
        $selection.BuildNumber -isnot [string] -or
        [string]::IsNullOrWhiteSpace($selection.BuildNumber)) {
        throw "PipelineResources must map non-empty resource aliases to DefinitionName and BuildNumber strings."
    }
}

. $PSScriptRoot/Utils.ps1
. $PSScriptRoot/GitUtils/gitUtils.ps1
. LoadSettings

$repositoryName ??= GetCurrentRepositoryName $remoteName
$repositoryId = & $PSScriptRoot\FindRepository.ps1 $repositoryName
$repositoryIdParam = $repositoryId ? "&repositoryId=$repositoryId&repositoryType=TfsGit" : ""
$sourceBranch ??=
    ($repositoryName -eq (GetCurrentRepositoryName $remoteName)) ? (GetCurrentBranch) : $null

$buildDefinitionsUrl = "$baseCollectionUrl/_apis/build/definitions" `
    + "?name=$definitionName" + $repositoryIdParam

$buildDefinitions = Invoke-RestMethod -Uri $buildDefinitionsUrl `
    -Method 'Get' -Headers @{Authorization = $authorization}

if ($buildDefinitions.count -eq 0) {
    Write-Error "Build definition $definitionName is not found"
    exit
}

$definitionId = $buildDefinitions.value[0].id

$resourceVersions = @{}
foreach ($alias in $pipelineResources.Keys) {
    $selection = $pipelineResources[$alias]
    $resourceDefinitionsUrl = "$baseCollectionUrl/_apis/build/definitions?name=" `
        + [uri]::EscapeDataString($selection.DefinitionName) + "&api-version=6.0"
    $response = Invoke-RestMethod -Uri $resourceDefinitionsUrl -Method Get `
        -Headers @{ Authorization = $authorization } -ErrorAction Stop
    $definitions = @($response.value | Where-Object { $_.name -eq $selection.DefinitionName })
    if ($definitions.Count -ne 1) {
        throw "Expected one pipeline named '$($selection.DefinitionName)' for resource '$alias'; found $($definitions.Count)."
    }

    $resourceBuildsUrl = "$baseCollectionUrl/_apis/build/builds?definitions=$($definitions[0].id)" `
        + "&buildNumber=" + [uri]::EscapeDataString($selection.BuildNumber + '*') + "&`$top=2&api-version=6.0"
    $response = Invoke-RestMethod -Uri $resourceBuildsUrl -Method Get `
        -Headers @{ Authorization = $authorization } -ErrorAction Stop
    $builds = @($response.value | Where-Object {
        $_.buildNumber.StartsWith($selection.BuildNumber, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($builds.Count -eq 0) {
        throw "No build starts with '$($selection.BuildNumber)' in '$($selection.DefinitionName)' for resource '$alias'."
    }
    if ($builds.Count -gt 1) {
        throw "Multiple builds start with '$($selection.BuildNumber)' in '$($selection.DefinitionName)' for resource '$alias'. Specify a more specific prefix."
    }
    $resourceVersions[$alias] = @{ version = [string]$builds[0].buildNumber }
}

$body = @{}
if ($resourceVersions.Count) {
    $body.resources = @{ pipelines = $resourceVersions }
    if ($sourceBranch) {
        $refName = $sourceBranch -like 'refs/*' ? $sourceBranch : "refs/heads/$sourceBranch"
        $body.resources.repositories = @{ self = @{ refName = $refName } }
    }
    $buildsUrl = "$baseCollectionUrl/_apis/pipelines/$definitionId/runs?api-version=6.0-preview.1"
} else {
    $body.definition = @{ id = $definitionId }
    if ($sourceBranch) {
        $body.sourceBranch = $sourceBranch
    }
    $buildsUrl = "$baseCollectionUrl/_apis/build/builds?api-version=2.0"
}
If ($parameters) {
    $body["templateParameters"] = $parameters
}

$build = Invoke-RestMethod `
    -Uri $buildsUrl `
    -Method 'Post' `
    -body ($body | ConvertTo-Json -Depth 10) `
    -ErrorAction Stop `
    -Headers @{ Authorization = $authorization; "Content-Type" = "application/json" }

Start-Sleep -Seconds 5
WatchBuildById.ps1 $build.id -preapprovedStages $preapprovedStages
