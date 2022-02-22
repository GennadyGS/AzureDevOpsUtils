param (
    [Parameter(Mandatory=$true)] $id
)

$ErrorActionPreference = "Stop"
. $PSScriptRoot/Utils.ps1
. LoadSettings

$url = "$baseInstanceUrl/_apis/wit/workItems/$id"

$workItem = Invoke-RestMethod `
    -Uri $url `
    -Method GET `
    -Headers @{ Authorization = $authorization }

$workItem.fields."System.Title"
