param (
    [Parameter(Mandatory=$true)] $teamName
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings

$url = "$baseTfsCollectionUrl/$teamName/_apis/work/TeamSettings/Iterations?timeframe=current"

$resp = Invoke-RestMethod -Uri $url -Headers @{Authorization = $authorization}

$currentDate = Get-Date
$resp.value `
    | ? { $_.attributes.startDate } `
    | ? { $currentDate -ge [DateTime]::Parse($_.attributes.startDate) `
        -and $currentDate -le [DateTime]::Parse($_.attributes.finishDate).AddDays(1) } `
     | % { $_.name }
