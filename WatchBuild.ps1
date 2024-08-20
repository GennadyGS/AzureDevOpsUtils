param (
    $definitionNamePattern,
    $sourceBranch = "master",
    $repositoryName,
    $remoteName = "origin",
    $top = 50
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot/GitUtils/gitUtils.ps1

$repositoryName ??= GetCurrentRepositoryName $remoteName
$sourceBranch = EstablishSourceBranchName $sourceBranch $repositoryName $remoteName

$buildId = FindBuild `
    -sourceBranch:$sourceBranch `
    -repositoryName:$repositoryName `
    -definitionNamePattern:$definitionNamePattern `
    -top:$top

if (!$buildId) {
    Write-Warning "Build is not found for source branch $sourceBranch and repository $repositoryName"
    return
}
Write-Host "Build $buildId is found"

& $PSScriptRoot/WatchBuildById.ps1 $buildId
