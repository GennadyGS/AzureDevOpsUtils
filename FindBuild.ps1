param (
    $sourceBranch,
    $repositoryName,
    $remoteName = "origin",
    $reason,
    $parameter,
    $definitionNamePattern,
    $fromId,
    $top = 50
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot/GitUtils/gitUtils.ps1

$repositoryName ??= GetCurrentRepositoryName $remoteName
$sourceBranch = EstablishSourceBranchName $sourceBranch $repositoryName $remoteName

FindBuild `
    -repositoryName:$repositoryName `
    -sourceBranch:$sourceBranch `
    -reason:$reason `
    -parameter:$parameter `
    -definitionNamePattern:$definitionNamePattern `
    -fromId:$fromId `
    -top:$top
