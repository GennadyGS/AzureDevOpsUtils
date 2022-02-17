Function LoadSettings {
    . $PSScriptRoot/Settings.ps1
    If (Test-Path "$PSScriptRoot/Settings.private.ps1") {
        . $PSScriptRoot/Settings.private.ps1
    }
    $baseTfsCollectionUrl = "$baseTfsInstanceUrl/$collection"
    $encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$pat"))
    $authorization = "Basic $encodedPat"
    $apiVersion = "6.0"
    $apiVersionParam = "?api-version=$apiVersion"
}
Function FindBuild {
    param (
        [Parameter(Mandatory=$true)]
        $repositoryName,
        $sourceBranchName,
        $reason,
        $parameter,
        $fromId, 
        $top = 10
    )

    . LoadSettings
    . $PSScriptRoot/GitUtils/gitUtils.ps1

    $repositoryId = & $PSScriptRoot\FindRepository.ps1 $repositoryName

    if (!$repositoryId) {
        throw "Repository $repositoryName is not found"
    }

    $reasonArg = if ($reason) { "&reasonFilter=$reason" }
    $minTime=[DateTime]::UtcNow.AddHours(-1).ToString("s")
    $buildsUrl = "$baseTfsCollectionUrl/_apis/build/builds?`$top=$top$reasonArg&minTime=$minTime"
    $builds = Invoke-RestMethod -Uri $buildsUrl -Method 'Get' -Headers @{Authorization = $authorization}

    $builds.value `
        | ?  { $_.repository.id -eq $repositoryId } `
        | ?  { !($parameter) -or ($_.parameters -and $_.parameters.Contains($parameter)) } `
        | ?  { !($sourceBranchName) -or ($_.sourceBranch -eq "refs/heads/$sourceBranchName") } `
        | ?  { !($fromId) -or ($_.id -gt $fromId) } `
        | %  { $_.id } `
        | Select-Object -first 1
}
