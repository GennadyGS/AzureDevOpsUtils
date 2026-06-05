param (
    $targetBranch,
    $sourceBranch,
    $repositoryName,
    $remoteName = "origin",
    $status = "all",
    [switch]$allCreators
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot\gitUtils\gitUtils.ps1

$repositoryName ??= GetCurrentRepositoryName $remoteName
$sourceBranch = EstablishSourceBranchName $sourceBranch $repositoryName $remoteName

$queryParams = @{ status = "$status" }
if ($targetBranch) {
    $queryParams["targetRefName"] = "refs/heads/$targetBranch"
}

if (!$allCreators) {
    $connectionData = Invoke-RestMethod `
        -Uri "$baseInstanceUrl/_apis/connectionData" `
        -Headers @{ Authorization = $authorization }
    $queryParams["creatorId"] = $connectionData.authenticatedUser.id
}

$url = Join-UrlQuery  $(GetPullRequestsUrl $repositoryName) $queryParams
$pullRequests = Invoke-RestMethod -Uri $url -Headers @{ Authorization = $authorization }

$pullRequestId = $pullRequests.value `
    | ? { $_.sourceRefName -Match "^refs/heads/$sourceBranch$" } `
    | ? { !$targetBranch -or ($_.targetRefName -Match "^refs/heads/$targetBranch$") } `
    | % { $_.pullRequestId } `
    | Select-Object -first 1

if (!$pullRequestId) {
    throw "Cannot find PR from branch $sourceBranch to branch $targetBranch"
}

& $PSScriptRoot/WatchPullRequestById.ps1 `
    -pullRequestId $pullRequestId `
    -repositoryName $repositoryName `
    -remoteName $remoteName
