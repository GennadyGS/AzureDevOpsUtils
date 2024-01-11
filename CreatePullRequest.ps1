param (
    $targetBranchName = "master",
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
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot/GitUtils/gitUtils.ps1

Function EstablishTitle {
    if (!$title) {
        if (IsCurrentRepository $repositoryName $remoteName) {
            $commitMessages = GetCommitMessages $remoteName/$targetBranchName $sourceBranchName
        }
        @("Merge $sourceBranchName to $targetBranchName") + @($commitMessages) `
        | Select-Object -Last 1
    } else {
        $title
    }
}

Function EstablishWorkItems {
    if (!$workItems -and (IsCurrentRepository $repositoryName $remoteName)) {
        GetWorkItems $remoteName/$targetBranchName $sourceBranchName
    } else {
        $workItems
    }
}

Function GetWorkItemRefs {
    param ([int[]] $workItems)
    $workItems `
        | % { @{id = $_; url = "$baseInstanceUrl/_apis/wit/workItems/$_" } }
}

$repositoryName ??= GetCurrentRepositoryName $remoteName
$sourceBranchName = EstablishSourceBranchName $sourceBranchName $repositoryName $remoteName
$title = EstablishTitle
$workItems = EstablishWorkItems

if (IsCurrentRepository $repositoryName $remoteName) {
    RunGit "push"
}

$urlBase = GetPullRequestsUrl $repositoryName
$body = @{
    sourceRefName = "refs/heads/$sourceBranchName"
    targetRefName = "refs/heads/$targetBranchName"
    title = $title
    description = $description
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
    -pullRequestId:$pullRequestId `
    -repositoryName:$repositoryName `
    -remoteName:$remoteName
