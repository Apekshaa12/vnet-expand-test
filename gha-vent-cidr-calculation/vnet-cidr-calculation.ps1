function vnet-cidr-calc
{ 
    param(
        $subscriptionName,
        $vnetName,
        $vnetRG,
        $expansionType,
        $tenant,
        $jsonFilePath
    )
    
    $jsonData = Get-JsonData -jsonFilePath "$jsonFilePath"
    $setSubsription = Set-AzContext -Subscription "$subscriptionName"
    
    $resultantIP = $Null
    $HubIPs      = @()
    $HubIPsList  = $Null
    $VNetInfo    = $Null
    if ("$subscriptionName" -match "it-hub")
    {
        $HubRG   = $vnetRG
        $HubVNet = $vnetName
    }
    else
    {
        $peeredVNetDetails, $HubVNet, $HubSubID, $HubRG = $Null
        $peeredVNetDetails = (Get-AzVirtualNetworkPeering -VirtualNetwork "$vnetName" -ResourceGroupName "$vnetRG").RemoteVirtualNetwork.Id
        $HubVNet           = ($peeredVNetDetails -split '/')[-1]
        $HubSubID          = ($peeredVNetDetails -split '/')[2]
        $HubRG             = ($peeredVNetDetails -split '/')[4]
        $setHubSubsription = Set-AzContext -Subscription "$HubSubID"
    }
    $VNetInfo   = Get-AzVirtualNetwork -ResourceGroupName "$HubRG" -Name "$HubVNet"
    $HubIPs     = $VNetInfo.virtualNetworkPeerings.remoteVirtualNetworkAddressSpace.AddressPrefixes
    $HubIPsList = $VNetInfo.AddressSpace.AddressPrefixes
    $HubIPs    += $HubIPsList
    $setSubsription = Set-AzContext -Subscription "$subscriptionName"

    $splitVnetName, $scope, $env, $socpeAndEnv = $Null
    $inputIPs      = @()
    $splitVnetName = $vnetName -split '-'
    $scope         = $splitVnetName[0]
    $env           = $splitVnetName[1]
    $socpeAndEnv   = "$scope-$env"
    $inputIPs      = $jsonData.($tenant + "_" + $expansionType + "_ReservedRanges").$socpeAndEnv
    $inIPS         = @()
    $IPhubdetails  = @()

    foreach ($InIP in $inputIPs)
    {
        $InputCIDR, $InputIP, $InputAddPrefix, $InputOcects, $InFirstOct   = $Null
        [int]$InSecOct, [int]$InThirdOct, [int]$InputPrefixCal, [int]$loop = $Null
        $InputCIDR           = ($InIP -split "\/")
        $InputIP             = $InputCIDR[0]
        $InputAddPrefix      = $InputCIDR[1]
        $InputOcects         = ($InputIP -split "\.")
        $InFirstOct          = $InputOcects[0]
        [int]$InSecOct       = $InputOcects[1]
        [int]$InThirdOct     = $InputOcects[2]
        [int]$InputPrefixCal = [math]::Pow(2, (32 - $InputAddPrefix)) / 256
         
        for ($loop = 0; $loop -lt $InputPrefixCal; $loop++)
        {
            [int]$currentThirdOctet = $Null
            $InIPCheck              = $Null
            if ($InThirdOct -eq 256) 
            {
                $InThirdOct = 0
                [int]$InSecOct++
            }
            [int]$currentThirdOctet = $InThirdOct++
            $InIPCheck              = "$InFirstOct.$InSecOct.$currentThirdOctet"
            $inIPS                 += $InIPCheck
            foreach ($hbIP in $HubIPs)
            {
                $HubCIDR, $HubIP, $HubOcects, $HubFirstOct, $HubSecOct = $Null
                [int]$HubThirdOct, [int]$HubPrefix                     = $Null
                $HubCIDR          = ($hbIP -split "\/")
                $HubIP            = $HubCIDR[0]
                [int]$HubPrefix   = $HubCIDR[1]
                $HubOcects        = ($HubIP -split "\.")
                $HubFirstOct      = $HubOcects[0]
                $HubSecOct        = $HubOcects[1]
                [int]$HubThirdOct = $HubOcects[2]
                if (($InFirstOct -eq $HubFirstOct) -and ($InSecOct -eq $HubSecOct) -and ($currentThirdOctet -eq $HubThirdOct))
                {
                    $IPhubdetails += $hbIP
                }
            }
        }
        $inIPS += "break"
    }

    $IPsLoop = @()
    foreach ($detail in $IPhubdetails)
    {
        $detailCIDR, $detailCIDRIP, $detailCIDRIPOcects, $FirstOct, $SecOct = $Null
        [int]$detailCIDRPrefix, [int]$ThirdOct, [int]$resPrefix             = $Null
        $detailCIDR            = ($detail -split "\/")
        $detailCIDRIP          = $detailCIDR[0]
        [int]$detailCIDRPrefix = $detailCIDR[1]
        $detailCIDRIPOcects    = ($detailCIDRIP -split "\.")
        $FirstOct              = $detailCIDRIPOcects[0]
        $SecOct                = $detailCIDRIPOcects[1]
        [int]$ThirdOct         = $detailCIDRIPOcects[2]
        [int]$resPrefix        = 32-$detailCIDRPrefix
        if ($resPrefix -gt 8)
        {
            [int]$powerVal, [int]$endres, [int]$iterate = $Null 
            [int]$powerVal = $resPrefix-8
            [int]$endres   = [math]::Pow(2, $powerVal)
            for ($iterate = 0; $iterate -lt $endres; $iterate++)
            {
                [int]$newThirdOct = $Null
                [int]$newThirdOct = $ThirdOct+$iterate
                $IPsLoop         += "$FirstOct.$SecOct.$newThirdOct"
            }
        }
        if ($resPrefix -le 8)
        {
            $IPsLoop += "$FirstOct.$SecOct.$ThirdOct"
        }
    }

    [int]$indexCount = 0
    :thisloop
    foreach ($ip in $inIPS) 
    {
        $indexCount = $indexCount + 1
        if (($ip -notin $IPsLoop) -and ($ip -ne "break") -and ($inIPS[$indexCount] -ne "break"))
        {
            $finalIP, $ipOct, $firstOct, $secondOct, $newFinalIP = $Null
            [int]$thirdOct, [int]$newCurrentThirdOctet           = $Null
            $finalIP                   = $ip
            $ipOct                     = $ip -split '\.'
            $firstOct                  = $ipOct[0]
            $secondOct                 = $ipOct[1]
            [int]$thirdOct             = $ipOct[2]
            [int]$newCurrentThirdOctet = $thirdOct + 1
            $newFinalIP                = "$firstOct.$secondOct.$newCurrentThirdOctet"
            if (($newFinalIP -notin $IPsLoop) -and ([int]$thirdOct % 2 -eq 0))
            {
                $resOct, $resFirst, $resSec, $resThird, $resultantIP = $Null
                $resOct      = $finalIP -split '\.'
                $resFirst    = $resOct[0]
                $resSec      = $resOct[1]
                $resThird    = $resOct[2]
                $resultantIP = "$resFirst.$resSec.$resThird.0/23"
                break thisloop
            }
        }
    }

    if ([string]::IsNullOrEmpty($resultantIP))
    {
        $resultantIP = "NA"
    }
    write-host "Final IP is: $resultantIP"
    return $resultantIP
}
