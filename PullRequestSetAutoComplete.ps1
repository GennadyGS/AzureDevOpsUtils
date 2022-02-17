param (
    $pullRequest,
    $deleteSourceBranch = $true
)

$setAutoCompleteBody = @{
    autoCompleteSetBy = @{ id = $pullRequest.createdBy.id }
    completionOptions = @{
        deleteSourceBranch = $deleteSourceBranch
        mergeCommitMessage = $pullRequest.title
    }
}

Invoke-RestMethod `
    -Uri "$($pullRequest.url)$apiVersionParam" `
    -Method PATCH `
    -Body ($setAutoCompleteBody | ConvertTo-Json) `
    -Headers @{ Authorization = $authorization; "Content-Type" = "application/json" } `
| Out-Null

Write-Host "Pull request $($pullRequest.pullRequestId) is set to autoComplete"
