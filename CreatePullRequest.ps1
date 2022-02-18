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
        | % { @{id = $_; url = "$baseTfsInstanceUrl/_apis/wit/workItems/$_"} }
}

if (!$sourceBranchName) { $sourceBranchName = GetCurrentBranch }
$gitRemoteUrl = GetRemoteUrl -remoteName $remoteName
$repositoryName = [regex]::match($gitRemoteUrl, ".*/(.*)$").Groups[1].Value

RunGit "push"

$urlBase = "$baseTfsCollectionUrl/_apis/git/repositories/$repositoryName/pullRequests"

$workItems = GetWorkItems `
    -sourceBranchName $sourceBranchName -targetBranchName $remoteName/$targetBranchName
$workItems

$title =
    @(GetCommitMessages `
        -sourceBranchName $sourceBranchName `
        -targetBranchName $remoteName/$targetBranchName) `
    + @("Merge $sourceBranchName to $targetBranchName") `
    | Select-Object -First 1
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
Write-Host "Pull request created; id: $pullRequestId; title: '$title'"

if ($autoComplete) {
    & $PSScriptRoot/PullRequestSetAutoComplete.ps1 $result
}

if ($workItems) {
    $workItemNameList =
        $workItems | %{ "pbi-$_`: `"$(& $PSScriptRoot/GetWorkItemTitle.ps1 $_ )`"" }
    $workItemNames = [string]::Join(", ", $workItemNameList)
    $browseUrl = "$baseTfsCollectionUrl/_git/$repositoryName/pullrequest/$pullRequestId"
    Try {
        & $PSScriptRoot/PsClipboardUtils/CopyHtmlToClipboard.ps1 `
            -Text "Pull request to $repositoryName for $workItemNames`: $browseUrl" `
            -Html "<span><a href=""$browseUrl"">Pull request $pullRequestId to $repositoryName</a>: $title</span>"`
    } Catch {
        Write-Warning $_
    }
}

& $PSScriptRoot/WatchPullRequestById.ps1 `
    -pullRequestId $pullRequestId `
    -repositoryName $repositoryName `
    -remoteName $remoteName `
    -watchCiBuild:$watchCiBuild
