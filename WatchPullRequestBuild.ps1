param (
    [Parameter(Mandatory=$true)]
    $pullRequestId,
    $repositoryName = "",
    $remoteName = "origin",
    $top = 10,
    $pollTimeoutSec = 10
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot/GitUtils/gitUtils.ps1

$pullRequestUrl = `
    "$baseTfsCollectionUrl/_apis/git/repositories/$repositoryName/pullRequests/$pullRequestId"

Function WaitForBuild {
    Do {
        $failures = 0
        Try {
            $pullRequest = Invoke-RestMethod `
                -Uri $pullRequestUrl `
                -Method GET `
                -Body $body `
                -Headers @{ Authorization = $authorization }
            if ($pullRequest.status -ne "active") {
                Write-Host `
                    "Pull request $pullRequestId is finished with result $($pullRequest.status)"
                Return
            }

            $buildId = FindBuild `
                -repositoryName $repositoryName `
                -reason "pullRequest" `
                -parameter "`"system.pullRequest.pullRequestId`":`"$pullRequestId`"" `
                -fromId $lastBuidId `
                -top $top
        } Catch {
            If (++$failures -le $maxWatchFailures) {
                Write-Warning $_
            } Else {
                Throw;
            }
        }

        if (!$buildId) {
            Write-Host "Build is not found for pull request $pullRequestId. Waiting for build start."
            Start-Sleep -s $pollTimeoutSec
        }
    }
    Until($buildId)
    Write-Host "Build is found for pull request $pullRequestId with id $buildId"
    $buildId
}

if (!$repositoryName) {
    $gitRemoteUrl = GetRemoteUrl -remoteName $remoteName
    $repositoryName = [regex]::match($gitRemoteUrl, ".*/(.*)$").Groups[1].Value
}

Do {
    $lastBuidId = WaitForBuild
    if (!$lastBuidId) {
        Return
    }

    $buildResult = & $PSScriptRoot/WatchBuildById.ps1 $lastBuidId
    Write-Host "Build $lastBuidId is finished with result $buildResult. Waining for next build."
    Start-Sleep -s $pollTimeoutSec
}
Until($False)
