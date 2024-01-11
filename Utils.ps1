Function LoadSettings {
    . $PSScriptRoot/Settings.ps1
    If (Test-Path "$PSScriptRoot/Settings.private.ps1") {
        . $PSScriptRoot/Settings.private.ps1
    }
    $baseCollectionUrl = "$baseInstanceUrl/$collection"
    $encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$pat"))
    $authorization = "Basic $encodedPat"
    $apiVersion = "6.0"
    $apiVersionParam = "?api-version=$apiVersion"
}

Function EstablishSourceBranchName {
    param (
        $sourceBranchName,
        $repositoryName,
        $remoteName
    )

    if (!$sourceBranchName) {
        if (!(IsCurrentRepository $repositoryName $remoteName)) {
            throw "SourceBranchName must be specified in case repositoryName is not current one"
        }
        GetCurrentBranch
    } else {
        $sourceBranchName
    }
}

Function FindBuild {
    param (
        [Parameter(Mandatory=$true)] $repositoryName,
        $sourceBranchName,
        $reason,
        $parameter,
        $definitionNamePattern,
        $fromId,
        $top = 10
    )

    . LoadSettings
    . $PSScriptRoot/GitUtils/gitUtils.ps1

    $reasonArg = if ($reason) { "&reasonFilter=$reason" }
    $buildsUrl = `
        "$baseCollectionUrl/_apis/build/builds?`$top=$top$reasonArg&QueryOrder=startTimeDescending"
    $builds = Invoke-RestMethod `
        -Uri $buildsUrl `
        -Method GET `
        -Headers @{ Authorization = $authorization }

    $builds.value `
        | ?  { $_.repository.name -eq $repositoryName } `
        | ?  { !($parameter) -or ($_.parameters -and $_.parameters.Contains($parameter)) } `
        | ?  { !($sourceBranchName) -or ($_.sourceBranch -eq "refs/heads/$sourceBranchName") } `
        | ?  { !($fromId) -or ($_.id -gt $fromId) } `
        | ?  { !($definitionNamePattern) -or ($_.definition.name -match $definitionNamePattern) } `
        | %  { $_.id } `
        | Select-Object -First 1
}

Function GetPullRequestsUrl {
    param ([Parameter(Mandatory=$true)] $repositoryName)
    "$baseCollectionUrl/_apis/git/repositories/$repositoryName/pullRequests"
}

Function GetPullRequestUrl {
    param (
        [Parameter(Mandatory=$true)] $repositoryName,
        [Parameter(Mandatory=$true)] $id
    )
    "$(GetPullRequestsUrl $repositoryName)/$id"
}

Function GetPullRequest {
    param (
        [Parameter(Mandatory=$true)] $repositoryName,
        [Parameter(Mandatory=$true)] $id
    )
    $url = GetPullRequestUrl -repositoryName $repositoryName -id $id
    Invoke-RestMethod `
        -Uri $url `
        -Method GET `
        -Body $body `
        -Headers @{ Authorization = $authorization }
}

Function GetPullRequestName {
    param (
        [Parameter(Mandatory=$true)] $repositoryName,
        [Parameter(Mandatory=$true)] $id
    )
    "$id to $repositoryName"
}

Function GetPullRequestBrowseUrl {
    param (
        [Parameter(Mandatory=$true)] $repositoryName,
        [Parameter(Mandatory=$true)] $id
    )
    "$baseCollectionUrl/_git/$repositoryName/pullrequest/$id"
}

Function BrowsePullRequest {
    param (
        [Parameter(Mandatory=$true)] $repositoryName,
        [Parameter(Mandatory=$true)] $id
    )
    $browseUrl = GetPullRequestBrowseUrl $repositoryName $id
    Start-Process $browseUrl
}

Function CopyPullRequestInfo {
    param (
        [Parameter(Mandatory=$true)] $pullRequest
    )

    $pullRequestName = GetPullRequestName $pullRequest.repository.name $pullRequest.pullRequestId
    $browseUrl = GetPullRequestBrowseUrl $pullRequest.repository.name $pullRequest.pullRequestId
    $encodedTitle = [System.Net.WebUtility]::HtmlEncode($pullRequest.title)
    $html = "<span><a href=""$browseUrl"">PR $pullRequestName</a>: $encodedTitle</span>"
    $text = [System.Net.WebUtility]::HtmlDecode(($html -replace "<(.|\n)*?>", ""))

    & $PSScriptRoot/PsClipboardUtils/CopyHtmlToClipboard.ps1 -Html $html -Text $text
    Write-Host "PR $pullRequestName info is copied to clipboard"
}

Function SetPullRequestAutoComplete {
    param (
        [Parameter(Mandatory=$true)] $pullRequest,
        $deleteSourceBranch = $true
    )

    $body = @{
        autoCompleteSetBy = @{ id = $pullRequest.createdBy.id }
        completionOptions = @{
            deleteSourceBranch = $deleteSourceBranch
            mergeCommitMessage = $pullRequest.title
        }
    }
    Invoke-RestMethod `
        -Uri "$($pullRequest.url)$apiVersionParam" `
        -Method PATCH `
        -Body ($body | ConvertTo-Json) `
        -Headers @{ Authorization = $authorization; "Content-Type" = "application/json" } `
    | Out-Null

    $pullRequestName = GetPullRequestName $pullRequest.pullRequestId $pullRequest.repository.name
    Write-Host "PR $pullRequestName is set to auto complete"
}