param (
    $repositoryName,
    $remoteName = "origin"
)

. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot/GitUtils/gitUtils.ps1

function GetWorkItemId
{
    $currentBranch = GetCurrentBranch
    [regex]::Match($currentBranch, $branchNamePattern).Groups[1].Value
}

Function BrowseWorkItem($id) {
    $browseUrl = "$baseCollectionUrl/_workitems/edit/$id"
    Start-Process $browseUrl
}

$workItemId = GetWorkItemId
if ($workItemId) {
    BrowseWorkItem $workItemId
}
else {
    Write-Host "No workitem is detected"
}

