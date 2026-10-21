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

Function GetStageName($timeline, $record) {
    $current = $record
    While ($current) {
        If ($current.type -eq "Stage") {
            return $current.name
        }
        $parentId = $current.parentId
        $current = $timeline.records | Where-Object { $_.id -eq $parentId } | Select-Object -First 1
    }
    return $record.name
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
    $approvals.value `
        | Where-Object { $_.status -eq "pending" } `
        | ForEach-Object {
            $approval = $_
            $approvers = @($approval.steps | ForEach-Object { $_.assignedApprover.displayName }) -join ", "
            [pscustomobject]@{
                Id = $approval.id
                Stage = GetStageName $timeline ($records | Where-Object { $_.id -eq $approval.id })
                Approvers = $approvers
                Instructions = $approval.instructions
            }
        }
}

Function WriteApprovals($approvals) {
    Write-Host "Pending approvals:" -ForegroundColor Yellow
    For ($i = 0; $i -lt $approvals.Count; $i++) {
        $approval = $approvals[$i]
        $details = @()
        If ($approval.Approvers) { $details += "approvers: $($approval.Approvers)" }
        If ($approval.Instructions) { $details += $approval.Instructions }
        $suffix = if ($details) { " ($($details -join '; '))" } else { "" }
        Write-Host "  [$($i + 1)] Stage $($approval.Stage)$suffix" -ForegroundColor Yellow
    }
    Write-Host "Type <number> to approve (Enter to confirm multi-digit), R then <number> to reject" -ForegroundColor Yellow
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
    } Catch {
        Write-Warning "Failed to set approval for stage $($approval.Stage) to ${status}: $_"
    }
}

Function ReadApprovalNumber($firstChar, $max) {
    $text = "$firstChar"
    Write-Host $firstChar -NoNewline
    # Commit as soon as no further digit could form a valid number, on Enter, or after a short idle
    While (("$text" -match "^\d+$") -and ([int]$text * 10 -le $max)) {
        $char = ReadKeyChar 1.5
        If ($null -eq $char -or $char -eq "`r" -or $char -eq "`n") { break }
        If ($char -notmatch "^\d$") {
            Write-Host " (cancelled)"
            return $null
        }
        $text += $char
        Write-Host $char -NoNewline
    }
    Write-Host ""
    $number = 0
    If ([int]::TryParse($text, [ref]$number) -and $number -ge 1 -and $number -le $max) {
        return $number
    }
    return $null
}

Function HandleApprovalKey($keyChar, $approvals) {
    $status = "approved"
    If ("$keyChar" -eq "r" -or "$keyChar" -eq "R") {
        Write-Host "Reject: enter approval number (any other key to cancel): " -ForegroundColor Yellow -NoNewline
        $keyChar = ReadKeyChar 10
        $status = "rejected"
    }
    If ($null -eq $keyChar -or "$keyChar" -notmatch "^\d$") {
        Write-Host ""
        return $false
    }
    $number = ReadApprovalNumber $keyChar $approvals.Count
    If ($number) {
        SetApprovalStatus $approvals[$number - 1] $status
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

$projectUrl = $build.url -replace "/_apis/build/.*$", ""
$approvalsUrl = "$projectUrl/_apis/pipelines/approvals"
$approvalsApiVersion = "7.1"
$pendingApprovals = @()
$shownApprovalIds = ""

$currentStatus = ""
$currentJobTask = ""
$failures = 0
While ($build.status -ne "completed") {
    $keyChar = ReadKeyChar 5
    If ($keyChar -and $pendingApprovals) {
        If (HandleApprovalKey $keyChar $pendingApprovals) {
            $shownApprovalIds = ""
        }
    }
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
    Try {
        $pendingApprovals = @(GetPendingApprovals $timeline)
    } Catch {
        Write-Warning "Failed to get approvals: $($_.Exception.Message)"
        $pendingApprovals = @()
    }
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
