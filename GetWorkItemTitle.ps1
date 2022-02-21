param (
    [Parameter(Mandatory=$true)] $id
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings

$url = "$baseTfsInstanceUrl/_apis/wit/workItems/$id"

$workItem = Invoke-RestMethod -Uri $url -Method 'Get' -Headers @{Authorization = $authorization }

$workItem.fields."System.Title"
