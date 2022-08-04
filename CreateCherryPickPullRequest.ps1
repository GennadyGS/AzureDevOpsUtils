param (
    $toTargetBranchName,
    $fromTargetBranchName = "master",
    $sourceBranchName,
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
    -sourceBranchName $sourceBranchName `
    -remoteName $remoteName

& $PSScriptRoot/CreatePullRequest.ps1 `
    -targetBranchName $toTargetBranchName `
    -sourceBranchName $sourceBranchName `
    -repositoryName $repositoryName `
    -remoteName $remoteName `
    -title $title `
    -description $description `
    -workItems $workItems `
    -draft:$draft `
    -autoComplete:$autoComplete
