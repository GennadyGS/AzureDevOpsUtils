param (
    $targetBranchName = "master",
    $sourceBranchName,
    $repositoryName,
    $remoteName = "origin",
    [switch] $draft,
    [switch] $autoComplete
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot/GitUtils/gitUtils.ps1

Function GetWorkItemRefs {
    param ([int[]]$workItems)
    return $workItems `
        | % { @{id = $_; url = "$baseInstanceUrl/_apis/wit/workItems/$_" } }
}

$repositoryName = EstablishRepositoryName $repositoryName $remoteName
$sourceBranchName = EstablishSourceBranchName $sourceBranchName $repositoryName $remoteName

if ($repositoryName -eq (GetCurrentRepositoryName $remoteName)) {
    RunGit "push"
}

$urlBase = "$baseCollectionUrl/_apis/git/repositories/$repositoryName/pullRequests"

$workItems = GetWorkItems `
    -sourceBranchName $sourceBranchName -targetBranchName $remoteName/$targetBranchName
$workItems

$title =
    @("Merge $sourceBranchName to $targetBranchName") `
    + @(GetCommitMessages `
        -sourceBranchName $sourceBranchName `
        -targetBranchName $remoteName/$targetBranchName) `
    | Select-Object -Last 1
$body = @{
    sourceRefName = "refs/heads/$sourceBranchName"
    targetRefName = "refs/heads/$targetBranchName"
    title = $title
    description = ""
    workItemRefs = @(GetWorkItemRefs $workItems)
    isDraft = $draft.IsPresent
}

$result = Invoke-RestMethod `
    -Uri $urlBase$apiVersionParam `
    -Method POST `
    -Body ($body | ConvertTo-Json) `
    -Headers @{ Authorization = $authorization; "Content-Type" = "application/json" }
$pullRequestId = $result.pullRequestId
$pullRequestName = GetPullRequestName $repositoryName $pullRequestId
Write-Host "PR $pullRequestName created: '$title'"

if ($autoComplete) {
    SetPullRequestAutoComplete $result
}

CopyPullRequestInfo $result
BrowsePullRequest $repositoryName $pullRequestId

& $PSScriptRoot/WatchPullRequestById.ps1 `
    -pullRequestId $pullRequestId `
    -repositoryName $repositoryName `
    -remoteName $remoteName
