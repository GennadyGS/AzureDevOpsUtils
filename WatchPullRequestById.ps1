param (
    [Parameter(Mandatory=$true)]
    $pullRequestId,
    $repositoryName,
    [switch] $watchCiBuild,
    $remoteName = "origin",
    $pollTimeoutSec = 5
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot/GitUtils/gitUtils.ps1
Import-Module $PSScriptRoot/PowershellModules/BurntToast/BurntToast/BurntToast.psm1

if (!$repositoryName) {
    $gitRemoteUrl = GetRemoteUrl -remoteName $remoteName
    $repositoryName = [regex]::match($gitRemoteUrl, ".*/(.*)$").Groups[1].Value
}

$browseUrl = "$baseTfsCollectionUrl/_git/$repositoryName/pullrequest/$pullRequestId"
Start-Process $browseUrl

Start-Process -LoadUserProfile "PowerShell" "-NoExit $PSScriptRoot/WatchPullRequestBuild.ps1 $pullRequestId -repositoryName $repositoryName -remoteName $remoteName"

$url = "$baseTfsCollectionUrl/_apis/git/repositories/$repositoryName/pullRequests/$pullRequestId"
$pullRequestOpenUrl = "$baseTfsCollectionUrl/_git/$repositoryName/pullrequest/$pullRequestId"
$toastButton = New-BTButton -Content 'Open pull request' -Arguments $pullRequestOpenUrl
$activeComments = 0
$approvalCount = 0
$rejectCount = 0
$failures = 0
Do {
    Try {
        $pullRequest = Invoke-RestMethod -Uri $url -Method 'Get' -Body $body -Headers @{Authorization = $authorization } 
        $pullRequestThreads = Invoke-RestMethod -Uri $url/threads -Method 'Get' -Body $body -Headers @{Authorization = $authorization } 
        $pullRequestReviewers = Invoke-RestMethod -Uri $url/reviewers -Method 'Get' -Body $body -Headers @{Authorization = $authorization } 
        $failures = 0
    } Catch {
        If (++$failures -le $maxWatchFailures) {
            Write-Warning $_
        } Else {
            Throw;
        } 
    }
    $newActiveComments = @($pullRequestThreads.value | ?{ !$_.isDeleted -and $_.status -eq "active" }).count
    If ($newActiveComments -gt $activeComments) {
        New-BurntToastNotification -Text "$($newActiveComments - $activeComments) new comments on pull request $pullRequestId" -Button $toastButton -AppLogo "$PSScriptRoot/Images/StatusInformation_256x.png"
    }
    $activeComments = $newActiveComments
    
    $newApprovalCount = @($pullRequestReviewers.value | ?{$_.vote -gt 0}).count
    If ($newApprovalCount -gt $approvalCount) {
        New-BurntToastNotification -Text "$($newApprovalCount - $approvalCount) new approvals on pull request $pullRequestId" -Button $toastButton -AppLogo "$PSScriptRoot/Images/StatusOK_256x.png"
    }
    $approvalCount = $newApprovalCount

    $newRejectCount = @($pullRequestReviewers.value | ?{$_.vote -lt 0}).count
    If ($newRejectCount -gt $rejectCount) {
        New-BurntToastNotification -Text "$($newRejectCount - $rejectCount) new rejects on pull request $pullRequestId" -Button $toastButton -AppLogo "$PSScriptRoot/Images/StatusWarning_256x.png"
    }
    $rejectCount = $newRejectCount

    Write-Host "Pull request $pullRequestId status: $($pullRequest.status)" 
    if ($pullRequest.status -eq "active") {
        Start-Sleep -s $pollTimeoutSec
    }
}
Until($pullRequest.status -ne "active")

Write-Host "Pull request $pullRequestId finished with result $($pullRequest.status)"
If ($pullRequest.status -eq "abandoned") {
    $imageUri = "$PSScriptRoot/Images/StatusCriticalError_256x.png"
} ElseIf ($pullRequest.status -eq "completed") {
    $imageUri = "$PSScriptRoot/Images/StatusOK_256x.png"
}
New-BurntToastNotification -Text "Pull request $pullRequestId $($pullRequest.status)" -Button $toastButton -AppLogo $imageUri

if ($watchCiBuild -and ($pullRequest.status -eq "completed")) {
    "Pull request is complete; watching CI build..."
    $targetBranchName = [regex]::match($pullRequest.targetRefName, ".*/(.*)$").Groups[1].Value
    "Target branch: $targetBranchName"
    & $PSScriptRoot/WatchBuild.ps1 -sourceBranchName $targetBranchName -repositoryName $repositoryName -remoteName $remoteName
}