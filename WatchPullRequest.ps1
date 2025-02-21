param (
    $targetBranch = "master",
    $sourceBranch,
    $repositoryName,
    $remoteName = "origin",
    $status = "all"
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot\gitUtils\gitUtils.ps1

$repositoryName ??= GetCurrentRepositoryName $remoteName
$sourceBranch = EstablishSourceBranchName $sourceBranch $repositoryName $remoteName

$url = $(GetPullRequestsUrl $repositoryName) `
    + "?targetRefName=refs/heads/$targetBranch&status=$status"
$pullRequests = Invoke-RestMethod -Uri $url -Headers @{ Authorization = $authorization }

$pullRequestId = $pullRequests.value `
    | ? { $_.sourceRefName -Match "^refs/heads/$sourceBranch$" } `
    | ? { $_.targetRefName -Match "^refs/heads/$targetBranch$" } `
    | % { $_.pullRequestId} `
    | Select-Object -first 1

if (!$pullRequestId) {
    throw "Cannot find PR from branch $sourceBranch to branch $targetBranch"
}

& $PSScriptRoot/WatchPullRequestById.ps1 `
    -pullRequestId $pullRequestId `
    -repositoryName $repositoryName `
    -remoteName $remoteName
