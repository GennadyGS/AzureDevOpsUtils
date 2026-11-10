<#
.SYNOPSIS
Watches a build and notifies when its stages or the build complete.
.DESCRIPTION
Stage completion notifications include the result and are sent once per stage.
Stages already completed in the first timeline snapshot do not trigger notifications.
.PARAMETER enableStatusChangeNotifications
Also notifies when the build status changes or an approval is pending.
#>
param (
    [Parameter(Mandatory=$true)] $buildId,
    [switch]$enableStatusChangeNotifications,
    [string[]]$preapprovedStages = @()
)

Function GetBuildName($build) {
    "$($build.definition.name) $($build.buildNumber)"
}

Function GetCurrentJobOrTaskRecord($timeline) {
    $inProgress = $timeline.records | Where-Object { $_.state -eq "inProgress" }
    $task = $inProgress | Where-Object { $_.type -eq "Task" } | Select-Object -First 1
    if ($task) {
        return $task
    }
    $job = $inProgress | Where-Object { $_.type -eq "Job" } | Select-Object -First 1
    if ($job) {
        return $job
    }
    return $null
}

Function GetStageRecord($timeline, $record) {
    $current = $record
    While ($current) {
        If ($current.type -eq "Stage") {
            return $current
        }
        $parentId = $current.parentId
        $current = $timeline.records | Where-Object { $_.id -eq $parentId } | Select-Object -First 1
    }
    return $record
}

Function GetCurrentActivity($timeline, $previousActivity) {
    $jobTask = GetCurrentJobOrTaskRecord $timeline
    $stage = $null
    If ($jobTask) {
        $candidate = GetStageRecord $timeline $jobTask
        If ($candidate.type -eq "Stage" -and $candidate.state -eq "inProgress") {
            $stage = $candidate
        }
    } Else {
        $stage = $timeline.records | Where-Object {
            $_.type -eq "Stage" -and $_.state -eq "inProgress"
        } | Select-Object -First 1
    }

    $jobTaskName = $null
    If ($jobTask) {
        $jobTaskName = $jobTask.name
    } ElseIf ($previousActivity -and $previousActivity.StageId -eq $stage.id) {
        $jobTaskName = $previousActivity.JobTask
    }
    return [pscustomobject]@{
        StageId = $stage.id
        Stage = $stage.name
        JobTask = $jobTaskName
    }
}

Function GetBuildStatusMessage($build, $activity) {
    $details = @()
    If ($activity.Stage) { $details += "Stage: $($activity.Stage)" }
    If ($activity.JobTask) { $details += $activity.JobTask }
    $suffix = if ($details) { " ($($details -join ' - '))" } else { "" }
    return "Build $(GetBuildName($build)) status: $($build.status)$suffix"
}

Function WriteStageCompletionNotifications($timeline, $build, $seenStageIds, $initialize, $toastButton, $imageRoot) {
    $completedStages = $timeline.records | Where-Object { $_.type -eq "Stage" -and $_.state -eq "completed" }
    foreach ($stage in $completedStages) {
        If (!$stage.id) {
            throw "A completed stage has no timeline record ID: $($stage.name)"
        }
        If ($seenStageIds.ContainsKey($stage.id)) {
            continue
        }
        If (!$initialize) {
            $result = if ($stage.result) { $stage.result } else { "completed" }
            $imageName = switch ($result) {
                "succeeded" { "StatusOK_256x.png" }
                "failed" { "StatusCriticalError_256x.png" }
                default { "StatusWarning_256x.png" }
            }
            New-BurntToastNotification `
                -Text "Build $(GetBuildName($build)): stage $($stage.name) $result" `
                -Button $toastButton `
                -AppLogo (Join-Path $imageRoot $imageName)
        }
        $seenStageIds[$stage.id] = $true
    }
}

Function IsPreapprovedStage($stageName) {
    foreach ($pattern in $preapprovedStages) {
        If ($stageName -like $pattern) {
            return $true
        }
    }
    return $false
}

Function GetPendingApprovals($timeline) {
    $records = @($timeline.records `
        | Where-Object { $_.type -eq "Checkpoint.Approval" -and $_.state -eq "inProgress" })
    If (!$records) {
        return @()
    }
    $approvalIds = ($records | ForEach-Object { $_.id }) -join ","
    $approvals = Invoke-RestMethod `
        -Uri "$approvalsUrl`?approvalIds=$approvalIds&`$expand=steps&api-version=$approvalsApiVersion" `
        -Method GET `
        -Headers @{ Authorization = $authorization }
    # Stage order from the timeline follows the pipeline definition; name keeps ties stable
    $approvals.value `
        | Where-Object { $_.status -eq "pending" } `
        | ForEach-Object {
            $approval = $_
            $approvers = @($approval.steps | ForEach-Object { $_.assignedApprover.displayName }) -join ", "
            $stage = GetStageRecord $timeline ($records | Where-Object { $_.id -eq $approval.id })
            [pscustomobject]@{
                Id = $approval.id
                Stage = $stage.name
                StageOrder = [int]$stage.order
                Approvers = $approvers
                Instructions = $approval.instructions
            }
        } `
        | Sort-Object StageOrder, Stage
}

Function Limit-Text($text, $maxLength) {
    If ($text.Length -le $maxLength) {
        return $text
    }
    return $text.Substring(0, $maxLength - 3) + "..."
}

Function WriteApprovals($approvals) {
    Write-Host "Pending approvals:" -ForegroundColor Yellow
    For ($i = 0; $i -lt $approvals.Count; $i++) {
        $approval = $approvals[$i]
        $details = @()
        If ($approval.Approvers) { $details += "approvers: $(Limit-Text $approval.Approvers 60)" }
        If ($approval.Instructions) { $details += Limit-Text $approval.Instructions 60 }
        $suffix = if ($details) { " ($($details -join '; '))" } else { "" }
        Write-Host "  [$($i + 1)] Stage $($approval.Stage)$suffix" -ForegroundColor Yellow
    }
    Write-Host "Type <number> and press Enter to approve, R then <number> and Enter to reject" -ForegroundColor Yellow
}

Function ReadKeyChar($timeoutSeconds) {
    $deadline = [DateTime]::UtcNow.AddSeconds($timeoutSeconds)
    Try {
        While ([DateTime]::UtcNow -lt $deadline) {
            If ([Console]::KeyAvailable) {
                return [Console]::ReadKey($true).KeyChar
            }
            Start-Sleep -Milliseconds 100
        }
    } Catch [System.InvalidOperationException] {
        # Input is redirected: keyboard is not available
        Start-Sleep -Seconds ([Math]::Max(0, ($deadline - [DateTime]::UtcNow).TotalSeconds))
    }
    return $null
}

Function SetApprovalStatus($approval, $status) {
    $body = ConvertTo-Json -AsArray -InputObject @{
        approvalId = $approval.Id
        status = $status
        comment = "$status via WatchBuildById"
    }
    Try {
        Invoke-RestMethod `
            -Uri "$approvalsUrl`?api-version=$approvalsApiVersion" `
            -Method PATCH `
            -Body $body `
            -Headers @{ Authorization = $authorization; "Content-Type" = "application/json" } `
        | Out-Null
        Write-Host "Stage $($approval.Stage) is $status" -ForegroundColor Green
        return $true
    } Catch {
        Write-Warning "Failed to set approval for stage $($approval.Stage) to ${status}: $_"
        return $false
    }
}

Function ReadApprovalNumber($firstChar, $max) {
    $text = "$firstChar"
    Write-Host $firstChar -NoNewline
    While ($true) {
        $char = ReadKeyChar 15
        If ($null -eq $char -or $char -eq [char]27) {
            Write-Host " (cancelled)"
            return $null
        }
        If ($char -eq "`r" -or $char -eq "`n") { break }
        If ($char -eq [char]8) {
            If ($text.Length -gt 0) {
                $text = $text.Substring(0, $text.Length - 1)
                Write-Host "`b `b" -NoNewline
            }
        } ElseIf ($char -match "^\d$") {
            $text += $char
            Write-Host $char -NoNewline
        }
    }
    Write-Host ""
    $number = 0
    If ([int]::TryParse($text, [ref]$number) -and $number -ge 1 -and $number -le $max) {
        return $number
    }
    Write-Host "Invalid approval number" -ForegroundColor Yellow
    return $null
}

Function HandleApprovalKey($keyChar, $approvals) {
    $status = "approved"
    If ("$keyChar" -eq "r" -or "$keyChar" -eq "R") {
        Write-Host "Reject: enter approval number and press Enter (Esc to cancel): " -ForegroundColor Yellow -NoNewline
        $keyChar = ReadKeyChar 10
        $status = "rejected"
    }
    If ($null -eq $keyChar -or "$keyChar" -notmatch "^\d$") {
        Write-Host ""
        return $false
    }
    $number = ReadApprovalNumber $keyChar $approvals.Count
    If ($number) {
        $null = SetApprovalStatus $approvals[$number - 1] $status
        return $true
    }
    return $false
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
Write-Host "Repository name: $($build.repository.name)"
Write-Host "Press B to open the build in browser" -ForegroundColor Cyan

$projectUrl = $build.url -replace "/_apis/build/.*$", ""
$approvalsUrl = "$projectUrl/_apis/pipelines/approvals"
$approvalsApiVersion = "7.1"
$pendingApprovals = @()
$shownApprovalIds = ""
$preapprovalAttemptedIds = @{}

$currentStatus = ""
$currentActivity = $null
$seenCompletedStageIds = @{}
$stageNotificationsInitialized = $false
$firstPoll = $true
$failures = 0
While ($build.status -ne "completed") {
    $keyChar = if ($firstPoll) { $null } else { ReadKeyChar 5 }
    $firstPoll = $false
    If ("$keyChar" -eq "b" -or "$keyChar" -eq "B") {
        Start-Process $buildOpenUrl
    } ElseIf ($keyChar -and $pendingApprovals) {
        If (HandleApprovalKey $keyChar $pendingApprovals) {
            $shownApprovalIds = ""
        }
    }
    $timelineUpdated = $false
    Try {
        $updatedBuild = Invoke-RestMethod `
            -Uri $buildUrl `
            -Method 'Get' `
            -Body $body `
            -Headers @{Authorization = $authorization }
        $updatedTimeline = Invoke-RestMethod `
            -Uri $timelineUrl `
            -Method 'Get' `
            -Headers @{Authorization = $authorization }
        $build = $updatedBuild
        $timeline = $updatedTimeline
        $timelineUpdated = $true
        $failures = 0
    } Catch {
        If (++$failures -le $maxWatchFailures) {
            Write-Warning $_
        } Else {
            Throw;
        }
    }
    If ($timelineUpdated) {
        WriteStageCompletionNotifications $timeline $build $seenCompletedStageIds (!$stageNotificationsInitialized) `
            $toastButton (Join-Path $PSScriptRoot "Images")
        $stageNotificationsInitialized = $true
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
    Try {
        $pendingApprovals = @(GetPendingApprovals $timeline)
    } Catch {
        Write-Warning "Failed to get approvals: $($_.Exception.Message)"
        $pendingApprovals = @()
    }
    $pendingApprovals = @($pendingApprovals | Where-Object {
        If ((IsPreapprovedStage $_.Stage) -and !$preapprovalAttemptedIds.ContainsKey($_.Id)) {
            $preapprovalAttemptedIds[$_.Id] = $true
            Write-Host "Stage $($_.Stage) is preapproved" -ForegroundColor Green
            return !(SetApprovalStatus $_ "approved")
        }
        return $true
    })
    $approvalIds = ($pendingApprovals | ForEach-Object { $_.Id }) -join ","
    If ($approvalIds -ne $shownApprovalIds) {
        $shownApprovalIds = $approvalIds
        If ($pendingApprovals) {
            WriteApprovals $pendingApprovals
            If ($enableStatusChangeNotifications) {
                New-BurntToastNotification `
                    -Text "Build $(GetBuildName($build)) is waiting for approval" `
                    -Button $toastButton `
                    -AppLogo "$PSScriptRoot/Images/StatusWarning_256x.png"
            }
        }
    }
    $currentActivity = GetCurrentActivity $timeline $currentActivity
    Write-Host (GetBuildStatusMessage $build $currentActivity)
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
