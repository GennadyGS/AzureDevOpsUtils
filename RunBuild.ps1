param (
    [Parameter(Mandatory=$true)]
    $definition,
    $repositoryName,
    $remoteName = "origin"
)

. $PSScriptRoot/Utils.ps1
. $PSScriptRoot/GitUtils/gitUtils.ps1
. LoadSettings

if (!$repositoryName) {
    $gitRemoteUrl = GetRemoteUrl -remoteName $remoteName
    $repositoryName = [regex]::match($gitRemoteUrl, ".*/(.*)$").Groups[1].Value
}
$repositoryId = & $PSScriptRoot\FindRepository.ps1 $repositoryName
if (!$repositoryId) {
    throw "Repository $repositoryName is not found"
}

$buildDefinitionsUrl = "$baseTfsCollectionUrl/_apis/build/definitions?name=$definition&repositoryId=$repositoryId&repositoryType=TfsGit"

$buildDefinitions = Invoke-RestMethod -Uri $buildDefinitionsUrl `
    -Method 'Get' -Headers @{Authorization = $authorization}

if ($buildDefinitions.count -eq 0) {
    Write-Error "Build definition $definition is not found"
    exit
}

$definitionId = $buildDefinitions.value[0].id

$body = @{definition = @{id=$definitionId}}
$buildsUrl = "$baseTfsCollectionUrl/_apis/build/builds?api-version=2.0"
$build = Invoke-RestMethod -Uri $buildsUrl -Method 'Post' -body ($body | ConvertTo-Json) -Headers @{Authorization = $authorization; "Content-Type" = "application/json"}

WatchBuildById.ps1 $build.id
