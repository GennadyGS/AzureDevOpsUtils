param (
    [Parameter(Mandatory = $true)] $pullRequestId,
    $repositoryName,
    $remoteName = "origin",
    $pollTimeoutSec = 5
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot/GitUtils/gitUtils.ps1
Import-Module $PSScriptRoot/PowershellModules/BurntToast/BurntToast/BurntToast.psm1

$repositoryName ??= GetCurrentRepositoryName $remoteName

$pullRequestName = GetPullRequestName $repositoryName $pullRequestId

Start-Process `
    "$hostShell" `
    "$hostShellArgs $PSScriptRoot/WatchPullRequestBuild.ps1 $pullRequestId -repositoryName $repositoryName -remoteName $remoteName" `
    -WindowStyle Minimized

$browseUrl = GetPullRequestBrowseUrl $repositoryName $pullRequestId
$toastButton = New-BTButton -Content 'Open PR' -Arguments $browseUrl

$activeComments = 0
$approvalCount = 0
$rejectCount = 0
$failures = 0
$host.UI.RawUI.FlushInputBuffer()
Do {
    Try {
        $pullRequest = GetPullRequest $repositoryName $pullRequestId
        $url = GetPullRequestUrl $repositoryName $pullRequestId
        $pullRequestThreads = Invoke-RestMethod `
            -Uri $url/threads `
            -Method GET `
            -Body $body `
            -Headers @{ Authorization = $authorization }
        $pullRequestReviewers = Invoke-RestMethod `
            -Uri $url/reviewers `
            -Method GET `
            -Body $body `
            -Headers @{ Authorization = $authorization }
        $failures = 0
    }
    Catch {
        If (++$failures -le $maxWatchFailures) {
            Write-Warning $_
        }
        Else {
            Throw;
        }
    }
    $newActiveComments =
    @($pullRequestThreads.value | ? { !$_.isDeleted -and $_.status -eq "active" }).count
    If ($newActiveComments -gt $activeComments) {
        New-BurntToastNotification `
            -Text "$($newActiveComments - $activeComments) new comments on PR $pullRequestName" `
            -Button $toastButton `
            -AppLogo "$PSScriptRoot/Images/StatusInformation_256x.png"
    }
    $activeComments = $newActiveComments

    $newApprovalCount = @($pullRequestReviewers.value | ? { $_.vote -gt 0 }).count
    If ($newApprovalCount -gt $approvalCount) {
        New-BurntToastNotification `
            -Text "$($newApprovalCount - $approvalCount) new approvals on PR $pullRequestName" `
            -Button $toastButton `
            -AppLogo "$PSScriptRoot/Images/StatusOK_256x.png"
    }
    $approvalCount = $newApprovalCount

    $newRejectCount = @($pullRequestReviewers.value | ? { $_.vote -lt 0 }).count
    If ($newRejectCount -gt $rejectCount) {
        New-BurntToastNotification `
            -Text "$($newRejectCount - $rejectCount) new rejects on PR $pullRequestName" `
            -Button $toastButton `
            -AppLogo "$PSScriptRoot/Images/StatusWarning_256x.png"
    }
    $rejectCount = $newRejectCount

    $message = "PR $pullRequestName status: $($pullRequest.status)"
    if ($activeComments -gt 0) { $message += "; $activeComments active comments" }
    if ($approvalCount -gt 0) { $message += "; $approvalCount approvals" }
    if ($rejectCount -gt 0) { $message += "; $rejectCount rejections" }
    Write-Host $message

    if ($pullRequest.status -ne "active") {
        break;
    }

    $key = WaitForKey $pollTimeoutSec
    switch ($key) {
        'a' { SetPullRequestAutoComplete $pullRequest }
        'b' { BrowsePullRequest $repositoryName $pullRequestId }
        'i' { CopyPullRequestInfo $pullRequest }
    }
    $host.ui.RawUI.FlushInputBuffer()
}
Until($pullRequest.status -ne "active")

Write-Host "PR $pullRequestName is finished with result $($pullRequest.status)"
If ($pullRequest.status -eq "abandoned") {
    $imageUri = "$PSScriptRoot/Images/StatusCriticalError_256x.png"
}
ElseIf ($pullRequest.status -eq "completed") {
    $imageUri = "$PSScriptRoot/Images/StatusOK_256x.png"
}
New-BurntToastNotification `
    -Text "PR $pullRequestName $($pullRequest.status)" `
    -Button $toastButton `
    -AppLogo $imageUri

if ($pullRequest.status -eq "completed") {
    Write-Host "PR is completed; watching CI build..."
    Start-Sleep -Seconds 10
    $targetBranchName = [regex]::match($pullRequest.targetRefName, ".*/(.*)$").Groups[1].Value
    & $PSScriptRoot/WatchBuild.ps1 `
        -sourceBranchName:$targetBranchName `
        -repositoryName:$repositoryName `
        -remoteName:$remoteName `
        -definitionNamePattern:$ciBuildNamePattern
}
