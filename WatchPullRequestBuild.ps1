param (
    [Parameter(Mandatory=$true)] $pullRequestId,
    $repositoryName,
    $remoteName = "origin",
    $top = 50,
    $pollTimeoutSec = 10
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot/GitUtils/gitUtils.ps1

$repositoryName ??= GetCurrentRepositoryName $remoteName

$pullRequestName = GetPullRequestName $repositoryName $pullRequestId

Function WaitForBuild {
    Do {
        $failures = 0
        Try {
            $pullRequest = GetPullRequest $repositoryName $pullRequestId
            if ($pullRequest.status -ne "active") {
                Write-Host "PR $pullRequestName is finished with result $($pullRequest.status)"
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
            Write-Host "Build is not found for PR $pullRequestName. Waiting for build start."
            Start-Sleep -s $pollTimeoutSec
        }
    }
    Until($buildId)
    Write-Host "Build $buildId is found for PR $pullRequestName"
    $buildId
}

$repositoryName ??= GetCurrentRepositoryName $remoteName

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
