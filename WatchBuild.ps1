param (
    $sourceBranchName,
    $repositoryName,
    $remoteName = "origin",
    $top = 10
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot/GitUtils/gitUtils.ps1

if (!$repositoryName) {
    $gitRemoteUrl = GetRemoteUrl -remoteName $remoteName
    $repositoryName = [regex]::match($gitRemoteUrl, ".*/(.*)$").Groups[1].Value
}

if (!$sourceBranchName) {
    if (!$sourceBranchName) { $sourceBranchName = GetCurrentBranch }
}

$buildId = FindBuild `
    -sourceBranch $sourceBranchName `
    -repositoryName $repositoryName `
    -top $top

if (!$buildId) {
    Write-Warning "Build is not found for source branch $sourceBranchName and repository $repositoryName"
    return
}
Write-Host "Build $buildId is found"

& $PSScriptRoot/WatchBuildById.ps1 $buildId
