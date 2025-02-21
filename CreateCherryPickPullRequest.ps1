param (
    $toTargetBranchName,
    $fromTargetBranchName = "master",
    $sourceBranch,
    $repositoryName,
    $remoteName = "origin",
    $title = "",
    $description = "",
    [int[]] $workItems = @(),
    [switch] $draft,
    [switch] $autoComplete
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/GitUtils/gitUtils.ps1

& $PSScriptRoot/GitUtils/gitCreateCherryPickBranch.ps1 `
    -toTargetBranchName $toTargetBranchName `
    -fromTargetBranchName $fromTargetBranchName `
    -sourceBranch $sourceBranch `
    -remoteName $remoteName

& $PSScriptRoot/CreatePullRequest.ps1 `
    -targetBranch $toTargetBranchName `
    -repositoryName $repositoryName `
    -remoteName $remoteName `
    -title $title `
    -description $description `
    -workItems $workItems `
    -draft:$draft `
    -autoComplete:$autoComplete
