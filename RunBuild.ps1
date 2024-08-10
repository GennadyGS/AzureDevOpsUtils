param (
    [Parameter(Mandatory=$true)] $definitionName,
    $repositoryName,
    $remoteName = "origin",
    $sourceBranch
)

. $PSScriptRoot/Utils.ps1
. $PSScriptRoot/GitUtils/gitUtils.ps1
. LoadSettings

$repositoryName ??= GetCurrentRepositoryName $remoteName
$repositoryId = & $PSScriptRoot\FindRepository.ps1 $repositoryName
$repositoryIdParam = $repositoryId ? "&repositoryId=$repositoryId&repositoryType=TfsGit" : ""
$sourceBranch ??=
    ($repositoryName -eq (GetCurrentRepositoryName $remoteName)) ? (GetCurrentBranch) : $null

$buildDefinitionsUrl = "$baseCollectionUrl/_apis/build/definitions" `
    + "?name=$definitionName" + $repositoryIdParam

$buildDefinitions = Invoke-RestMethod -Uri $buildDefinitionsUrl `
    -Method 'Get' -Headers @{Authorization = $authorization}

if ($buildDefinitions.count -eq 0) {
    Write-Error "Build definition $definitionName is not found"
    exit
}

$definitionId = $buildDefinitions.value[0].id

$body = @{
    definition = @{ id = $definitionId }
}

If ($sourceBranch) {
    $body.sourceBranch = $sourceBranch
}

$buildsUrl = "$baseCollectionUrl/_apis/build/builds?api-version=2.0"
$build = Invoke-RestMethod `
    -Uri $buildsUrl `
    -Method 'Post' `
    -body ($body | ConvertTo-Json) `
    -Headers @{ Authorization = $authorization; "Content-Type" = "application/json" }

Start-Sleep -Seconds 5
WatchBuildById.ps1 $build.id
