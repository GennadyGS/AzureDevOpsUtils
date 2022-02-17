param (
    $targetBranchName = "master",
    $sourceBranchName = "",
    $remoteName = "origin",
    $watchCiBuild = $true
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

$url = "$baseTfsCollectionUrl/_apis/git/repositories/$repositoryName/pullRequests?api-version=1.0"

$workItems = GetWorkItems `
    -sourceBranchName $sourceBranchName -targetBranchName $remoteName/$targetBranchName
$firstCommitMessage =
    GetCommitMessages -sourceBranchName $sourceBranchName -targetBranchName $remoteName/$targetBranchName `
    | Select-Object -First 1

$workItems
$body = @{
    sourceRefName = "refs/heads/$sourceBranchName";
    targetRefName = "refs/heads/$targetBranchName";
    title = $firstCommitMessage;
    workItemRefs = @(GetWorkItemRefs $workItems)
}

$result = Invoke-RestMethod `
    -Uri $url `
    -Method 'Post' `
    -Body ($body | ConvertTo-Json) `
    -Headers @{Authorization = $authorization; "Content-Type" = "application/json"}
$pullRequestId = $result.pullRequestId
"Pull request id: $pullRequestId"

if ($workItems) {
	$workItemNameList = $workItems | %{ "pbi-$_`: `"$(& $PSScriptRoot/GetWorkItemTitle.ps1 $_ )`""}
    $workItemNames = [string]::Join(", ", $workItemNameList)
    $browseUrl = "$baseTfsCollectionUrl/_git/$repositoryName/pullrequest/$pullRequestId"
    Try {
        Set-Clipboard -Value "Pull request to $repositoryName for $workItemNames`: $browseUrl"
    } Catch {
        Write-Warning $_
    }
}

& $PSScriptRoot/WatchPullRequestById.ps1 `
    -pullRequestId $pullRequestId `
    -repositoryName $repositoryName `
    -remoteName $remoteName `
    -watchCiBuild:$watchCiBuild
