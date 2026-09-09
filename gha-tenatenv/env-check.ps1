<#
    This script is to fetch the tenant value.
#>
Param (
    [Parameter()]
    [string] $tenant
)
if (($tenant -eq "12a3af23-a769-4654-847f-958f3d479f4a") -or ($tenant -eq "nestle.onmicrosoft.com")) 
{
    $tenant = "nestle.onmicrosoft.com"
    $tenant_value = "NestlePROD"
} 
elseif (($tenant -eq "59d6de52-9304-4f7f-8381-10448bdc6e61") -or ($tenant -eq "nestlew2k.onmicrosoft.com"))
{
    $tenant = "nestlew2k.onmicrosoft.com"
    $tenant_value = "NestleDEV"
}
elseif (($tenant -eq "2e49c969-49c0-4a0b-ba77-4cfd890e9a51") -or ($tenant -eq "nestleint.onmicrosoft.com"))
{
    $tenant = "nestleint.onmicrosoft.com"
    $tenant_value = "NestleINT"
} 
elseif (($tenant -eq "de575837-ebbb-4b6f-9137-e25e8f11e138") -or ($tenant -eq "nestlebj.partner.onmschina.cn"))
{
    $tenant = "nestlebj.partner.onmschina.cn"
    $tenant_value = "NestleCHINA"
}
Write-Host "Provided tenant: $($tenant). and tenant value: $($tenant_value)"
Write-Output "$tenant_value"
