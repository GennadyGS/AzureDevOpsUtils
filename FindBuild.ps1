param (
    $sourceBranchName,
    $repositoryName,
    $remoteName = "origin",
    $reason,
    $parameter,
    $definitionNamePattern,
    $fromId,
    $top = 10
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot/GitUtils/gitUtils.ps1

$repositoryName = EstablishRepositoryName $repositoryName $remoteName
$sourceBranchName = EstablishSourceBranchName $sourceBranchName $repositoryName $remoteName

FindBuild `
    -repositoryName:$repositoryName `
    -sourceBranchName:$sourceBranchName `
    -reason:$reason `
    -parameter:$parameter `
    -definitionNamePattern:$definitionNamePattern `
    -fromId:$fromId `
    -top:$top
