param (
    [Parameter(Mandatory=$true)] $buildId,
    [switch]$enableStatusChangeNotifications
)

Function GetBuildName($build) {
    "$($build.definition.name) $($build.buildNumber)"
}

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
Import-Module $PSScriptRoot/PowershellModules/BurntToast/BurntToast/BurntToast.psm1

$buildUrl = "$baseCollectionUrl/_apis/build/builds/$buildId"
$buildOpenUrl = "$baseCollectionUrl/_build/index?buildId=$buildId"

$toastButton = New-BTButton -Content 'Open build' -Arguments $buildOpenUrl

$build = Invoke-RestMethod `
    -Uri $buildUrl `
    -Method GET `
    -Body $body `
    -Headers @{ Authorization = $authorization }

Write-Host "Build id: $($build.id)"
Write-Host "Definition name: $($build.definition.name)"
Write-Host "Build number: $($build.buildNumber)"
Write-Host "Start time: $($build.startTime)"
Write-Host "Requested for: $($build.requestedFor.displayName)"

$currentStatus = ""
$failures = 0
While ($build.status -ne "completed") {
    Start-Sleep -s 5
    Try {
        $build = Invoke-RestMethod `
            -Uri $buildUrl `
            -Method 'Get' `
            -Body $body `
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
    Write-Host "Build $(GetBuildName($build)) status: $($build.status)"
}

Write-Host "Build $(GetBuildName($build)) is finished with status $($build.result)"
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
