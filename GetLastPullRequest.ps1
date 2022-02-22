param (
    $repositoryName,
    $targetBranchName = "master",
    $sourceBranchNameMask = ".*",
    $remoteName = "origin",
    $status = "all"
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings
. $PSScriptRoot\gitUtils\gitUtils.ps1

if (!$repositoryName) {
    $gitRemoteUrl = GetRemoteUrl -remoteName $remoteName
    $repositoryName = [regex]::match($gitRemoteUrl, ".*/(.*)$").Groups[1].Value
}

$url = `
    "$baseCollectionUrl/_apis/git/repositories/$repositoryName/pullRequests" `
    + "?targetRefName=refs/heads/$targetBranchName&status=$status"

$resp = Invoke-RestMethod -Uri $url -Headers @{ Authorization = $authorization }

$resp.value `
    | ? { $_.sourceRefName -Match "refs/heads/$sourceBranchNameMask" } `
    | % { [regex]::match($_.sourceRefName,'refs/heads/(.*)').Groups[1].Value } `
    | Select-Object -first 1
