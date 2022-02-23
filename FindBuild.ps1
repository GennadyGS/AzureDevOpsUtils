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

if (!$repositoryName) { $repositoryName = GetCurrentRepositoryName $remoteName }
if (!$sourceBranchName) { $sourceBranchName = GetCurrentBranch }

FindBuild -repositoryName $repositoryName -sourceBranchName $sourceBranchName
