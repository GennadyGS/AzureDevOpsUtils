param (
    $pullRequest
)

$setAutoCompleteBody = @{
    autoCompleteSetBy = @{ id = $pullRequest.createdBy.id }
    completionOptions = @{
        deleteSourceBranch = $true
        mergeCommitMessage = $pullRequest.title
    }
}

Invoke-RestMethod `
    -Uri "$($pullRequest.url)$apiVersionParam" `
    -Method PATCH `
    -Body ($setAutoCompleteBody | ConvertTo-Json) `
    -Headers @{ Authorization = $authorization; "Content-Type" = "application/json" } `
| Out-Null

Write-Host "Pull request $($pullRequest.id) is set to autoComplete"
