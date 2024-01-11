param (
    $targetBranchName = "master",
    $sourceBranchName,
    $repositoryName,
    $remoteName = "origin",
    $status = "all"
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot\gitUtils\gitUtils.ps1

$repositoryName ??= GetCurrentRepositoryName $remoteName
$sourceBranchName = EstablishSourceBranchName $sourceBranchName $repositoryName $remoteName

$url = $(GetPullRequestsUrl $repositoryName) `
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
    -remoteName $remoteName
