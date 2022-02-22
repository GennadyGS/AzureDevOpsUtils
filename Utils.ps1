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

Function FindBuild {
    param (
        [Parameter(Mandatory=$true)] $repositoryName,
        $sourceBranchName,
        $reason,
        $parameter,
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
        | %  { $_.id } `
        | Select-Object -First 1
}

Function GetPullRequestBrowseUrl {
    param (
        [Parameter(Mandatory=$true)] $repositoryName,
        [Parameter(Mandatory=$true)] $pullRequestId
    )
    "$baseCollectionUrl/_git/$repositoryName/pullrequest/$pullRequestId"
}

Function BrowsePullRequest {
    param (
        [Parameter(Mandatory=$true)] $repositoryName,
        [Parameter(Mandatory=$true)] $pullRequestId
    )
    $browseUrl = `
        GetPullRequestBrowseUrl -repositoryName $repositoryName -pullRequestId $pullRequestId
    Start-Process $browseUrl
}

Function CopyPullRequestInfo {
    param (
        [Parameter(Mandatory=$true)] $pullRequest
    )

    $pullRequestName = "$($pullRequest.pullRequestId) to $($pullRequest.repository.name)"
    $browseUrl = GetPullRequestBrowseUrl `
        -repositoryName $pullRequest.repository.name `
        -pullRequestId $pullRequest.pullRequestId
    $encodedTitle = [System.Net.WebUtility]::HtmlEncode($pullRequest.title)
    $html = "<span><a href=""$browseUrl"">PR $pullRequestName</a>: $encodedTitle</span>"
    $text = [System.Net.WebUtility]::HtmlDecode(($html -replace "<(.|\n)*?>", ""))

    & $PSScriptRoot/PsClipboardUtils/CopyHtmlToClipboard.ps1 -Html $html -Text $text
}