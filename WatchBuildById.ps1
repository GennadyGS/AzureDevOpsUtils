param (
    [Parameter(Mandatory=$true)] $buildId,
    [switch]$enableStatusChangeNotifications
)

Function GetBuildName($build) {
    "$($build.definition.name) $($build.buildNumber)"
}

Function GetCurrentJobOrTaskName($timeline) {
    $inProgress = $timeline.records | Where-Object { $_.state -eq "inProgress" }
    $task = $inProgress | Where-Object { $_.type -eq "Task" } | Select-Object -First 1
    if ($task) {
        return $task.name
    }
    $job = $inProgress | Where-Object { $_.type -eq "Job" } | Select-Object -First 1
    if ($job) {
        return $job.name
    }
    return $null
}

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
Import-Module $PSScriptRoot/PowershellModules/BurntToast/BurntToast/BurntToast.psm1

$buildUrl = "$baseCollectionUrl/_apis/build/builds/$buildId"
$timelineUrl = "$baseCollectionUrl/_apis/build/builds/$buildId/timeline"
$buildOpenUrl = "$baseCollectionUrl/_build/index?buildId=$buildId"

$toastButton = New-BTButton -Content 'Open build' -Arguments $buildOpenUrl

$build = Invoke-RestMethod `
    -Uri $buildUrl `
    -Method GET `
    -Headers @{ Authorization = $authorization }

Write-Host "Build id: $($build.id)"
Write-Host "Definition name: $($build.definition.name)"
Write-Host "Build number: $($build.buildNumber)"
Write-Host "Start time: $($build.startTime)"
Write-Host "Requested for: $($build.requestedFor.displayName)"
Write-Host "Branch: $($build.sourceBranch)"

$currentStatus = ""
$currentJobTask = ""
$failures = 0
While ($build.status -ne "completed") {
    Start-Sleep -s 5
    Try {
        $build = Invoke-RestMethod `
            -Uri $buildUrl `
            -Method 'Get' `
            -Body $body `
            -Headers @{Authorization = $authorization }
        $timeline = Invoke-RestMethod `
            -Uri $timelineUrl `
            -Method 'Get' `
            -Headers @{Authorization = $authorization }
        $failures = 0
    } Catch {
        If (++$failures -le $maxWatchFailures) {
            Write-Warning $_
        } Else {
            Throw;
        }
    }
    if ($build.status -ne $currentStatus) {
        $currentStatus = $build.status
        if ($enableStatusChangeNotifications) {
            New-BurntToastNotification `
            -Text "Build $(GetBuildName($build)) status changed to $($build.status)" `
            -Button $toastButton `
            -AppLogo "$PSScriptRoot/Images/StatusInformation_256x.png"
        }
    }
    $jobTask = GetCurrentJobOrTaskName $timeline
    if ($jobTask -and $jobTask -ne $currentJobTask) {
        $currentJobTask = $jobTask
    }
    $jobTaskSuffix = if ($currentJobTask) { " ($currentJobTask)" } else { "" }
    Write-Host "Build $(GetBuildName($build)) status: $($build.status)$jobTaskSuffix"
}

Write-Host "Build $(GetBuildName($build)) is finished with status $($build.result)"
Write-Output $build.result
If ($build.result -eq "failed") {
    $imageUri = "$PSScriptRoot/Images/StatusCriticalError_256x.png"
} ElseIf ($build.result -eq "succeeded") {
    $imageUri = "$PSScriptRoot/Images/StatusOK_256x.png"
}
$message = "Build $(GetBuildName($build)) $($build.result)"
New-BurntToastNotification `
    -Text $message `
    -Button $toastButton `
    -AppLogo $imageUri
Try {
    Set-Clipboard -Value $message
} Catch {
    Write-Warning $_
}
