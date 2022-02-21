param (
    [Parameter(Mandatory=$true)] $buildId,
    [switch]$enableStatusChangeNotifications
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
Import-Module $PSScriptRoot/PowershellModules/BurntToast/BurntToast/BurntToast.psm1

$buildUrl = "$baseTfsCollectionUrl/_apis/build/builds/$buildId"
$buildOpenUrl = "$baseTfsCollectionUrl/_build/index?buildId=$buildId"

$toastButton = New-BTButton -Content 'Open build' -Arguments $buildOpenUrl

$build = Invoke-RestMethod `
    -Uri $buildUrl `
    -Method GET `
    -Body $body `
    -Headers @{ Authorization = $authorization }
$buildName = "$($build.definition.name) $($build.buildNumber)"

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
        $build = Invoke-RestMethod -Uri $buildUrl -Method 'Get' -Body $body -Headers @{Authorization = $authorization }
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
            -Text "Build $buildName status changed to $($build.status)" `
            -Button $toastButton `
            -AppLogo "$PSScriptRoot/Images/StatusInformation_256x.png"
        }
    }
    Write-Host "Build $buildName status: $($build.status)"
}

Write-Host "Build $buildName is finished with status $($build.result)"
If ($build.result -eq "failed") {
    $imageUri = "$PSScriptRoot/Images/StatusCriticalError_256x.png"
} ElseIf ($build.result -eq "succeeded") {
    $imageUri = "$PSScriptRoot/Images/StatusOK_256x.png"
}
$message = "Build $buildName $($build.result)"
New-BurntToastNotification `
    -Text $message `
    -Button $toastButton `
    -AppLogo $imageUri
Try {
    Set-Clipboard -Value $message
} Catch {
    Write-Warning $_
}
