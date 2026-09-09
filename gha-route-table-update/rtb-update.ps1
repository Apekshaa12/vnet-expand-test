function name-generator
{
    param (
        [string]$routeTableName,
	[string]$resourceGroupName,
	[string]$routeNamePattern
    )
    $routeNames = @()
    $routeNames = (Get-AzRouteTable -Name "$routeTableName" -ResourceGroupName "$resourceGroupName").Routes.Name
    if(-not ([string]::IsNullOrEmpty($routeNames)))
    {
        $pattern        = "$routeNamePattern(\d+)$"
        $numericNumbers = @()
	foreach ($routeName in $routeNames) 
	{
	    if ($routeName -match $pattern)
	    {
		$numericNumbers += $matches[1]
	    }
	}
	$missingNums = @()
	$lastNum     = 0
	foreach ($numb in $numericNumbers) 
	{
	    $currentNum = [int]$numb
	    if ($currentNum -ne ($lastNum + 1)) 
	    {
		for ($y = $lastNum + 1; $y -lt $currentNum; $y++) 
		{
		    $missingNums += $y
		}
	    }
	    $lastNum = $currentNum
        }
	if ($missingNums.Count -ne 0) 
	{
	    $final = $missingNums[0]
	}
	if ($missingNums.Count -eq 0) 
	{
	    $lastNum = [int]$numericNumbers[-1]
	    $newNum  = ($lastNum + 1)
	    $final   = $newNum
	}
	$routeName = "$routeNamePattern$final"
    }
    else
    {
        $routeName = "$routeNamePattern" + "1"
    }
    return $routeName
}

function rtb-udr-update {

    param (
        [string]$subscriptionName,
        [string]$vnetName,
        [string]$tenant,
        [string]$vnetIP,
        [string]$vnetType,
        [string]$jsonFilePath
    )

    #---------------------------------------------------------
    # Set Context (with retry)
    #---------------------------------------------------------
    for ($i = 1; $i -le 3; $i++) {
        try {
            Set-AzContext -Subscription $subscriptionName -ErrorAction Stop
            break
        }
        catch {
            Write-Host "Set-AzContext failed (Main Context). Attempt $i of 3"
            if ($i -eq 3) {
                throw "Failed to set context for subscription : $subscriptionName"
            }
            Start-Sleep 3
        }
    }

    Import-Module "$source_directory\gha-vnet-expansion\reusable-functions.ps1"

    $jsonData   = Get-JsonData -jsonFilePath "$jsonFilePath"
    $vnetIPCIDR = $vnetIP -replace '[./]', '_'

    #---------------------------------------------------------
    # Determine VNet type (Hub / Spoke)
    #---------------------------------------------------------
    $HubSubscriptionsMatchKeywords = $jsonData.($tenant + '_HubSubscriptionsMatchKeywords').'HubSubscriptionsMatchKeywords'
    $typeofVNet = if ($subscriptionName -match ($HubSubscriptionsMatchKeywords -join '|')) { "Hub" } else { "Spoke" }
    Write-Host "Type of VNet : $typeofVNet"

    #---------------------------------------------------------
    # Basic VNet details
    #---------------------------------------------------------
    $vnetDetails = Get-AzVirtualNetwork -Name $vnetName
    $vnetParts   = ($vnetDetails.Id -split '/')

    $selfVNetSubID  = $vnetParts[2]
    $selfVNetRGName = $vnetParts[4]
    $deptShortname  = ($selfVNetRGName -split '-')[3]

    $peeringDetails = $vnetDetails.virtualNetworkPeerings.RemoteVirtualNetwork.Id
    $peeredInfo     = @("$selfVNetSubID = $selfVNetRGName")

    foreach ($peer in $peeringDetails) {
        $parts = $peer -split '/'
        $peeredInfo += "$($parts[2]) = $($parts[4])"
    }

    $peeredUnique = $peeredInfo | Select-Object -Unique

    Write-Host "Route Tables RGs Count : $($peeredInfo.Count)"
    Write-Host "Unique Route Tables RGs Count : $($peeredUnique.Count)"

    #---------------------------------------------------------
    # Prepare lists
    #---------------------------------------------------------
    $completeRTBsList = @()
    $missedRTBNames   = @()

    $excludedRTBs     = $jsonData.($tenant + "_RTB_ExclusionList").'RTB_ExclusionList'
    $HubRGsMatchKeywords = $jsonData.($tenant + "_HubRGsMatchKeywords").'HubRGsMatchKeywords'

    $loop = 0

    #---------------------------------------------------------
    # Process each peered subscription + RG
    #---------------------------------------------------------
    foreach ($peerInfo in $peeredUnique) {

        $loop++
        Write-Host "`n----------- Loop $loop -----------"

        $split      = $peerInfo -split '='
        $peerSubID  = $split[0].Trim()
        $peerRGName = $split[1].Trim()

        #---------------------------------------------------------
        # Set context with retry
        #---------------------------------------------------------
        for ($i = 1; $i -le 3; $i++) {
            try {
                Set-AzContext -SubscriptionId $peerSubID -ErrorAction Stop
                break
            }
            catch {
                Write-Host "Set-AzContext failed for peer subscription. Attempt $i of 3"
                if ($i -eq 3) { continue 2 }
                Start-Sleep 3
            }
        }

        #-----------------------------------------------------
        # Fetch RTBs
        #-----------------------------------------------------
        $rtList = (Get-AzRouteTable -ResourceGroupName $peerRGName).Name | Select-Object -Unique

        $filteredRTBs = $rtList | Where-Object {
            $rtb = $_
            -not ($excludedRTBs | Where-Object { $rtb -like "*$_*" })
        }

        Write-Host "RTBs Found  : $($rtList.Count) | After exclusion : $($filteredRTBs.Count)"

        $completeRTBsList += $filteredRTBs

        # Determine RTB type
        if (
            (($typeofVNet -eq "Spoke") -and ($peerRGName -notmatch ($HubRGsMatchKeywords -join '|'))) -or
            (($typeofVNet -eq "Hub")   -and ($peerRGName -match ($HubRGsMatchKeywords -join '|')))
        ) {
            $rtbType = "Self"
        }
        else {
            $rtbType = "Peering"
        }

        Write-Host "RTB Type : $rtbType"

        #-----------------------------------------------------
        # Process EACH RTB
        #-----------------------------------------------------
        foreach ($rtb in $filteredRTBs) {

            $attempt    = 0
            $maxRetries = 3

            while ($attempt -lt $maxRetries) {

                try {
                    Write-Host "`nProcessing RTB : $rtb (Attempt : $($attempt+1))"
                    Start-Sleep 5

                    #-----------------------------------------------------
                    # Region & Firewall logic
                    #-----------------------------------------------------
                    $rgLocation = (Get-AzResourceGroup -Name $peerRGName).Location
                    $subObj     = Get-AzSubscription -SubscriptionId $peerSubID
                    $subParts   = $subObj.Name -split '-'

                    $scopeAndEnv = "$($subParts[0])-$($subParts[1])"
                    $scopedData  = $jsonData.($tenant + "_Scoped_Regions")

                    # direct scope
                    if ($scopeAndEnv -in $scopedData.'scoped-scopeandenvironment') {
                        $internalFirewallIp = $jsonData.($tenant + "_Internal_Firewall_IPs").("$scopeAndEnv-internal")
                        $internetFirewallIp = $jsonData.($tenant + "_Internet_Firewall_IPs").("$scopeAndEnv-internet")
                    }
                    # regional scope
                    elseif (($rgLocation -in $scopedData.'scoped-location') -and ($subParts[1] -in $scopedData.'scoped-environments')) {
                        $scopeEnv           = $scopedData."$rgLocation-$($subParts[1])"
                        $internalFirewallIp = $jsonData.($tenant + "_Internal_Firewall_IPs").("$scopeEnv-internal")
                        $internetFirewallIp = $jsonData.($tenant + "_Internet_Firewall_IPs").("$scopeEnv-internet")
                    }
                    else {
                        $missedRTBNames += $rtb
                        break
                    }

                    #-----------------------------------------------------
                    # Determine NextHop
                    #-----------------------------------------------------
                    $fitRTBs     = $jsonData.($tenant + "_FiT_RTBsList").'FiT_RTBsList'
                    $specialRTBs = $jsonData.($tenant + "_Internet_UDR_RTBsList").'Internet_UDR_RTBsList'

                    $routePrefix = $jsonData.($tenant + '_Route_Names').($typeofVNet + '_' + $rtbType + '_' + $vnetType + '_Route_Name')

                    if ($routePrefix -in @("RT", "RT_FiT")) {
                        $routePrefix = "${routePrefix}_${deptShortname}"
                    }

                    $routeName = "${routePrefix}_${vnetIPCIDR}"
                    Write-Host "Route name : $routeName"

                    if ($fitRTBs | Where-Object { $rtb -like "*$_*" }) {
                        Write-Host "FiT RTB"

                        if ($rtbType -eq "Self" -and $typeofVNet -eq "Spoke" -and $vnetType -eq "FiT") {
                            $routeName = $routeName -replace "RTInside", "RTLocal"
                        }

                        $nextHopType = $jsonData.($tenant + "_UDR_Details").($vnetType + "_FiT_RTBs").'Next Hop Type'
                        $nextHopIP   = $jsonData.($tenant + "_UDR_Details").($vnetType + "_FiT_RTBs").'Next Hop IP Address'
                    }
                    elseif ($specialRTBs | Where-Object { $rtb -like "*$_*" }) {
                        Write-Host "Special RTB"

                        $nextHopType = $jsonData.($tenant + "_UDR_Details").($vnetType + "_Special_RTBs").'Next Hop Type'
                        $nextHopIP   = $jsonData.($tenant + "_UDR_Details").($vnetType + "_Special_RTBs").'Next Hop IP Address'
                    }
                    else {
                        Write-Host "Standard RTB"

                        $nextHopType = $jsonData.($tenant + "_UDR_Details").($vnetType + "_Standard_RTBs").'Next Hop Type'
                        $nextHopIP   = $jsonData.($tenant + "_UDR_Details").($vnetType + "_Standard_RTBs").'Next Hop IP Address'
                    }

                    if ($nextHopIP -eq "Internal Firewall IP") { $nextHopIP = $internalFirewallIp }
                    if ($nextHopIP -eq "Internet Firewall IP") { $nextHopIP = $internetFirewallIp }

                    #-----------------------------------------------------
                    # Remove existing → add new UDR
                    #-----------------------------------------------------
                    $rtbObj   = Get-AzRouteTable -Name $rtb -ResourceGroupName $peerRGName
                    $existing = $rtbObj.Routes | Where-Object { $_.AddressPrefix -eq $vnetIP }

                    if ($existing) {
                        Write-Host "Existing UDR found → removing..."
                        $rtbObj | Remove-AzRouteConfig -Name $existing.Name | Out-Null
                        $rtbObj | Set-AzRouteTable     | Out-Null
                        $rtbObj = Get-AzRouteTable -Name $rtb -ResourceGroupName $peerRGName
                    }

                    Write-Host "Adding new UDR..."
                    Add-AzRouteConfig `
                        -Name $routeName `
                        -AddressPrefix $vnetIP `
                        -NextHopType $nextHopType `
                        -NextHopIpAddress $nextHopIP `
                        -RouteTable $rtbObj | Out-Null

                    $rtbObj | Set-AzRouteTable | Out-Null

                    $verify = (Get-AzRouteTable -Name $rtb -ResourceGroupName $peerRGName).Routes |
                              Where-Object { $_.AddressPrefix -eq $vnetIP }

                    if ($verify) {
                        Write-Host "UDR Added Successfully."
                    }
                    else {
                        Write-Host "UDR Add Failed."
                        $missedRTBNames += $rtb
                    }

                    break # success
                }
                catch {
                    Write-Warning "Error processing $rtb : $_"
                    $attempt++

                    if ($attempt -ge $maxRetries) {
                        Write-Warning "Max retries reached for RTB : $rtb"
                        $missedRTBNames += $rtb
                    }
                    else {
                        Write-Host "Retrying in 120 seconds..."
                        Start-Sleep 120
                    }
                }
            }
        }
    }

    #---------------------------------------------------------
    # Summary
    #---------------------------------------------------------
    $total   = $completeRTBsList.Count
    $failed  = $missedRTBNames.Count
    $success = $total - $failed

    # restore context
    for ($i = 1; $i -le 3; $i++) {
        try {
            Set-AzContext -Subscription $subscriptionName -ErrorAction Stop
            break
        }
        catch {
            Start-Sleep 3
        }
    }

    return @{
        TotalRTBCount   = $total
        FailedRTBCount  = $failed
        MissedRTBNames  = $missedRTBNames
        SuccessRTBCount = $success
        SuccessRTBs     = $completeRTBsList
    }
}
