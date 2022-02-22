param (
    $targetBranchName = "master",
    $sourceBranchName = "",
    $remoteName = "origin",
    $watchCiBuild = $true,
    [switch]$draft,
    [switch]$autoComplete
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot/GitUtils/gitUtils.ps1

Function GetWorkItemRefs {
    param ([int[]]$workItems)
    return $workItems `
        | % { @{id = $_; url = "$baseInstanceUrl/_apis/wit/workItems/$_"} }
}

if (!$sourceBranchName) { $sourceBranchName = GetCurrentBranch }
$gitRemoteUrl = GetRemoteUrl -remoteName $remoteName
$repositoryName = [regex]::match($gitRemoteUrl, ".*/(.*)$").Groups[1].Value

RunGit "push"

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
$pullRequestName = "$pullRequestId to $repositoryName"
Write-Host "PR $pullRequestName created: '$title'"

if ($autoComplete) {
    & $PSScriptRoot/PullRequestSetAutoComplete.ps1 $result
}

CopyPullRequestInfo $result

BrowsePullRequest -repositoryName $repositoryName -pullRequestId $pullRequestId

& $PSScriptRoot/WatchPullRequestById.ps1 `
    -pullRequestId $pullRequestId `
    -repositoryName $repositoryName `
    -remoteName $remoteName `
    -watchCiBuild:$watchCiBuild
