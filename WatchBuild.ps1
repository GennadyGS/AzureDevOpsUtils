param (
    $sourceBranchName,
    $repositoryName,
    $definitionNamePattern,
    $remoteName = "origin",
    $top = 10
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot/GitUtils/gitUtils.ps1

$repositoryName ??= GetCurrentRepositoryName $remoteName
$sourceBranchName = EstablishSourceBranchName $sourceBranchName $repositoryName $remoteName

$buildId = FindBuild `
    -sourceBranch:$sourceBranchName `
    -repositoryName:$repositoryName `
    -definitionNamePattern:$definitionNamePattern `
    -top:$top

if (!$buildId) {
    Write-Warning "Build is not found for source branch $sourceBranchName and repository $repositoryName"
    return
}
Write-Host "Build $buildId is found"

& $PSScriptRoot/WatchBuildById.ps1 $buildId
