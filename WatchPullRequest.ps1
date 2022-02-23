param (
    $targetBranchName = "master",
    $sourceBranchName,
    $repositoryName,
    $remoteName = "origin",
    $status = "all",
    [switch] $noWatchCiBuild
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot\gitUtils\gitUtils.ps1

if (!$repositoryName) {
    $gitRemoteUrl = GetRemoteUrl -remoteName $remoteName
    $repositoryName = [regex]::match($gitRemoteUrl, ".*/(.*)$").Groups[1].Value
}

if (!$sourceBranchName) { $sourceBranchName = GetCurrentBranch }

$url = "$baseCollectionUrl/_apis/git/repositories/$repositoryName/pullRequests" `
    + "?targetRefName=refs/heads/$targetBranchName&status=$status"
$pullRequests = Invoke-RestMethod -Uri $url -Headers @{ Authorization = $authorization }

$pullRequestId = $pullRequests.value `
    | ? { $_.sourceRefName -Match "refs/heads/$sourceBranchName" } `
    | ? { $_.targetRefName -Match "refs/heads/$targetBranchName" } `
    | % { $_.pullRequestId} `
    | Select-Object -first 1

if (!$pullRequestId) {
    throw "Cannot find PR from branch $sourceBranchName to branch $targetBranchName"
}

& $PSScriptRoot/WatchPullRequestById.ps1 `
    -pullRequestId $pullRequestId `
    -repositoryName $repositoryName `
    -remoteName $remoteName `
    -noWatchCiBuild:$noWatchCiBuild
