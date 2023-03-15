param (
    [Parameter(Mandatory=$true)] $definition,
    $repositoryName,
    $remoteName = "origin"
)

. $PSScriptRoot/Utils.ps1
. $PSScriptRoot/GitUtils/gitUtils.ps1
. LoadSettings

if ($repositoryName = TryEstablishRepositoryName $repositoryName $remoteName) {
    $repositoryId = & $PSScriptRoot\FindRepository.ps1 $repositoryName
    $repositoryIdParam = $repositoryId ? "&repositoryId=$repositoryId&repositoryType=TfsGit" : ""
}

$buildDefinitionsUrl = "$baseCollectionUrl/_apis/build/definitions" `
    + "?name=$definition" + $repositoryIdParam

$buildDefinitions = Invoke-RestMethod -Uri $buildDefinitionsUrl `
    -Method 'Get' -Headers @{Authorization = $authorization}

if ($buildDefinitions.count -eq 0) {
    Write-Error "Build definition $definition is not found"
    exit
}

$definitionId = $buildDefinitions.value[0].id

$body = @{definition = @{id=$definitionId}}
$buildsUrl = "$baseCollectionUrl/_apis/build/builds?api-version=2.0"
$build = Invoke-RestMethod -Uri $buildsUrl -Method 'Post' -body ($body | ConvertTo-Json) -Headers @{Authorization = $authorization; "Content-Type" = "application/json"}

WatchBuildById.ps1 $build.id
