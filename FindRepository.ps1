param (
    $repositoryName
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings

$url = "$baseTfsCollectionUrl/_apis/git/repositories"

$resp = Invoke-RestMethod -Uri $url -Headers @{Authorization = $authorization}

$resp.value `
| ? { $_.name -eq $repositoryName } `
| % { $_.id }