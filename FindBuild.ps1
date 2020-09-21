param (
    $sourceBranchName = "",
    $repositoryName = "",
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

FindBuild -repositoryName $repositoryName -sourceBranchName $sourceBranchName
