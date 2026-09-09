# Function to get the next consecutive IP address by incrementing the last octet of the given IP address
function Calculate-NextConsecutiveIP
{
    param (
        [String]$CurrentIP
    )
    $OctetsOfCurrentIP     = $CurrentIP -split '\.'
    $LastOctetOfCurrentIP  = [int]$OctetsOfCurrentIP[3]
    if ($LastOctetOfCurrentIP -le "255") 
    {
        $OctetsOfCurrentIP[3] = ($LastOctetOfCurrentIP + 1).ToString()
    } 
    else
    {
        $OctetsOfCurrentIP[3] = "0"
    }
    $NextConsecutiveIP = $OctetsOfCurrentIP -join '.'
    return $NextConsecutiveIP
}

# Function to group consecutive IP addresses into ranges and return a list of ranges in the format "startIP - endIP"
function Calculate-IPRangeGroups
{
    param (
        [string[]]$RemainingIPsList
    )
    $ipRanges          = @()
    $currentRangeStart = $RemainingIPsList[0]
    $currentRangeEnd   = $RemainingIPsList[0]
    for ($GroupIpIndex = 1; $GroupIpIndex -lt $RemainingIPsList.Count; $GroupIpIndex++) 
    {
        $nextIPAddress = Calculate-NextConsecutiveIP -CurrentIP $currentRangeEnd
        if ($RemainingIPsList[$GroupIpIndex] -eq $nextIPAddress) 
        {
            $currentRangeEnd = $RemainingIPsList[$GroupIpIndex]
        } 
        else 
        {
            $ipRanges          += "$currentRangeStart - $currentRangeEnd"
            $currentRangeStart  = $RemainingIPsList[$GroupIpIndex]
            $currentRangeEnd    = $RemainingIPsList[$GroupIpIndex]
        }
    }
    $ipRanges     += "$currentRangeStart - $currentRangeEnd"
    return $ipRanges
}

# Function to returns a list of IP ranges from VNet Address Ranges as per the specific Network (Standard, FiT, DataBricks_Routable, DataBricks_NonRoutable) Reserved Address Ranges
function Get-NetworkTypeIpRanges
{
    param (
        [String[]]$SpecificIPAddresses,
        [String]$NetworkType,
        [String[]]$ReservedRanges
    )
    $SpecificIpAddressList = @()
    foreach ($ReservedIPRange in $ReservedRanges)
    {
        $ReservedRangeIP, [int]$ReservedRangePrefix = ($ReservedIPRange -split ('\/')).trim()
        $FirstOctReservedRangeIP, $SecondOctReservedRangeIP, $ThirdOctReservedRangeIP, $FourthOctReservedRangeIP = ($ReservedRangeIP -split ('\.')).trim()
        [int]$ResultReserved = [math]::Pow(2, (32 - $ReservedRangePrefix))
        $counter = 0
        while ($ResultReserved -ge 256) 
        {
            [int]$ResultReserved /= 256
            $counter++
        }
        if ((($counter -eq 0) -or ($counter -eq $null)) -and ($ResultReserved -lt 256))
        {
            $fourth_octs_range = @($FourthOctReservedRangeIP..$ResultReserved)
            $third_octs_range  = @($ThirdOctReservedRangeIP)
            $second_octs_range = @($SecondOctReservedRangeIP)
            $first_octs_range  = @($FirstOctReservedRangeIP)           
        }
        else
        {
            [int]$ResultReserved = $ResultReserved - 1
            $fourth_octs_range = @(0..255)
            if ($counter -eq 1)
            {
                [int]$MThirdOctReservedRangeIP = [int]$ThirdOctReservedRangeIP + [int]$ResultReserved
                $third_octs_range  = @($ThirdOctReservedRangeIP..$MThirdOctReservedRangeIP)
                $second_octs_range = @($SecondOctReservedRangeIP)
                $first_octs_range  = @($FirstOctReservedRangeIP)
            }
            if  ($counter -eq 2)
            {
                $third_octs_range  = @(0..255)
                [int]$MSecondOctReservedRangeIP = [int]$SecondOctReservedRangeIP + [int]$ResultReserved
                $second_octs_range  = @($SecondOctReservedRangeIP..$MSecondOctReservedRangeIP)
                $first_octs_range  = @($FirstOctReservedRangeIP)
            }
            if ($counter -eq 3)
            {
                $third_octs_range  = @(0..255)
                $second_octs_range = @(0..255)
                [int]$MFirstOctReservedRangeIP = [int]$FirstOctReservedRangeIP + [int]$ResultReserved
                $first_octs_range  = @($FirstOctReservedRangeIP..$MFirstOctReservedRangeIP)
            }
            if  ($counter -eq 4)
            {
                $third_octs_range  = @(0..255)
                $second_octs_range = @(0..255)
                $first_octs_range  = @(0..255)
            }

            foreach ($SpecificIPAdd in $SpecificIPAddresses)
            {
                $SpecificIP, $SpecificIPPrefix = $SpecificIPAdd -split ('\/').trim()
                $FirstOctSpecificIP, $SecondOctSpecificIP, $ThirdOctSpecificIP, $FourthOctSpecificIP = $SpecificIP -split ('\.').trim()
                if (($FirstOctSpecificIP -in $first_octs_range) -and ($SecondOctSpecificIP -in $second_octs_range) -and ($ThirdOctSpecificIP -in $third_octs_range) -and ($FourthOctSpecificIP -in $fourth_octs_range))
                {
                    $SpecificIpAddressList += $SpecificIPAdd                  
                }
            }
        }
    }
    return $SpecificIpAddressList
}

#Get all VNet IPs and existing Subnet IPs
function Get-TotalIps
{
    param (
        [String[]]$Cidrs
    )
    $TotalIPsList = @()
    foreach ($Cidr in $Cidrs) 
    {
        $SeperateWithSlash = $Cidr -split '\/'
        $StartIP           = $SeperateWithSlash[0] 
        $AddressPrefix     = $SeperateWithSlash[1] 
        $TotalIPs          = [math]::Pow(2, (32 - [int]$AddressPrefix))
        $IPOctets          = $StartIP -split '\.' | ForEach-Object { [int]$_ }

        for ($IpIndex = 0; $IpIndex -lt $TotalIPs; $IpIndex++) 
        {
            $TotalIPsList += "$($IPOctets[0]).$($IPOctets[1]).$($IPOctets[2]).$($IPOctets[3])"
            $IPOctets[3]++
            if ($IPOctets[3] -eq 256) 
            {
                $IPOctets[3] = 0
                $IPOctets[2]++
                if ($IPOctets[2] -eq 256) 
                {
                    $IPOctets[2] = 0
                    $IPOctets[1]++
                    if ($IPOctets[1] -eq 256) 
                    {
                        $IPOctets[1] = 0
                        $IPOctets[0]++
                    }
                }
            }
        }
    }
    return $TotalIPsList
}

# Function to calculate and return the available subnet CIDR for a new subnet based on given inputs and existing network configuration
function Calculate-NewSubnetCIDR
{
    param(
        [string]$SubscriptionName,
        [string]$VnetName,
        [string]$VnetRGName,
        [ValidateRange(23, 29)][int]$SubnetPrefix,
        [string]$NetworkType,
        [string]$SourceDirectory,
        [string]$Tenant
    )

    $setSubsription = Set-AzContext -Subscription "$SubscriptionName"
    
    Import-Module "$source_directory\gha-vnet-expansion\reusable-functions.ps1"
    $FinalCIDR = "NA"

    # Define a hashtable ($Inputs) to store all the necessary input values
    $Inputs = @{
        "Subnet Prefix"         = $SubnetPrefix
        "Subscription Name"     = $SubscriptionName
        "VNet Name"             = $VnetName
        "Network Type"          = $NetworkType
        "Tenant"                = "$Tenant"
        "Source Directory Path" = "$SourceDirectory"
    }

    # Call the Ensure-MandatoryInputs function to check if all mandatory inputs are provided
    if ((Ensure-MandatoryInputs -inputs $Inputs) -eq "Empty") 
    {
        Write-Error "`nMandatory inputs not provided. Pipeline will fail."
        exit 1
    }
    else
    {
        Write-Host "`nAll mandatory inputs provided"
    }

    # Load subnet configuration data from the subnet-rtb-configuration.json file
    $ReservedRanges = @()
    $JsonData  = Get-JsonData -jsonFilePath "$SourceDirectory\gha-subnet-cidr-calculation\subnet-configuration.json"
    $Reserved  = $JsonData.($Tenant + "_ReservedIPRanges").'ReservedIPRanges'.$NetworkType
    $Scope     = ("$VnetName" -split '-')[0]
    if ($NetworkType -eq "FiT")
    {
        $ReservedRanges = $Reserved.$Scope
    }
    else
    {
        $ReservedRanges = $Reserved.'IP_Range'
    }

    Write-Host "`nReserved IP Ranges for $NetworkType Network Type"
    Write-Host $ReservedRanges

    #Gather VNet IP ranges which are in scope of input networkType i.e Standard or FiT
    $VnetDetails       = Get-ResourceDetails -ResourceType "vnet" -Action "details" -ResourceGroupName "$VnetRGName" -ResourceName "$VnetName"

    #Fetch the VNet ips as per the Address Space
    $VnetIPAddresses   = @()
    $VnetIPAddresses   = $VnetDetails.AddressSpace.AddressPrefixes
    $VnetIPAddressList = Get-NetworkTypeIpRanges -SpecificIPAddresses $VnetIPAddresses -NetworkType $NetworkType -ReservedRanges $ReservedRanges
    $ReservedVnetCount = $VnetIPAddressList.Count
    Write-Host "`nScoped VNet Address Ranges Count"
    Write-Host $ReservedVnetCount
    if ($ReservedVnetCount -eq "0")
    {
       $FinalCIDR = "Not a Scoped VNet"
       Write-Host "Not a Scoped VNet, not included the scoped ranges during the initial VNet creation."
    }
    else
    {
        $VnetIPsList       = Get-TotalIps -Cidrs $VnetIPAddressList
        $VnetCount         = $VnetIPsList.Count
        Write-Host "`nTotal Specific VNet IPs count"
        Write-Host $VnetCount
        foreach ($VnetIPAddressLt in $VnetIPAddressList)
        {
            write-host "$VnetIPAddressLt"
        }
    
        #Fetch the existing subnet ips as per the Address Space
        $SubnetIPAddress = @()
        foreach ($subnet in $VnetDetails.Subnets) 
        {
           $SubnetIPAddress += $subnet.addressPrefix[0]
        }
        $SubnetIPAddressList = Get-NetworkTypeIpRanges -SpecificIPAddresses $SubnetIPAddress -NetworkType $NetworkType -ReservedRanges $VnetIPAddressList
        $ReservedSubnetCount = $SubnetIPAddressList.Count
        Write-Host "`nScoped Subnets Address Ranges Count"
        Write-Host $ReservedSubnetCount
        $SubnetIPsList   = Get-TotalIps -Cidrs $SubnetIPAddressList
        Write-Host "`nTotal Specific Subnets IPs count" 
        Write-Host $SubnetIPsList.Count
    
        #Remaining IPs list i.e VNet - Subnet IPs
        $RemainingIPsList = $VnetIPsList | Where-Object { $_ -notin $SubnetIPsList }
        Write-Host "`nRemaining IPs, i.e VNet - Subnets" 
        Write-Host $RemainingIPsList.Count
    
        # This script identifies the first available IP address for subnet allocation based on the CIDR size
        if ($RemainingIPsList.Count -gt 0) 
        {
            $IpGroupsList = Calculate-IPRangeGroups -RemainingIPsList $RemainingIPsList
            $GroupsCount  = $IpGroupsList.Count
            Write-Host "`nIP Groups Count"
            Write-Host $GroupsCount
            foreach ($IpGroupsLst in $IpGroupsList)
            {
                Write-Host $IpGroupsLst
            }
            $ShortListedGroups  = @()
            $StartValue         = 0
            $StartingIpLastOcts = @()
            $SubnetPrefixCal    = [math]::Pow(2, (32 - $SubnetPrefix))
            while ($StartValue -lt 256) 
            {
                $StartingIpLastOcts += $StartValue
                $StartValue         += $SubnetPrefixCal
            }
            Write-Host "`nStarting IP Last Octets are"
            Write-Host $StartingIpLastOcts
    
            $FinalCIDR = $null
            :outsideloop
            foreach ($IpGroupslt in $IpGroupsList)
            {
                $GroupStartingIP, $GroupEndingIP = ($IpGroupslt -split '\-').Trim()
                $FirstOctofStartingIP, $SecondOctofStartingIP, $ThirdOctofStartingIP, [int]$FourthOctofStartingIP = ($GroupStartingIP -split '\.')
                $FirstOctofEndingIP, $SecondOctofEndingIP, $ThirdOctofEndingIP, [int]$FourthOctofEndingIP         = ($GroupEndingIP -split '\.')
                [int]$FourthOctofEndingIP = ([int]$FourthOctofEndingIP) + 1
                $ExpectedEndingIP         = [int]$FourthOctofStartingIP + [int]$SubnetPrefixCal
    
                if(($FirstOctofStartingIP -eq $FirstOctofEndingIP) -and ($SecondOctofStartingIP -eq $SecondOctofEndingIP) -and ($ThirdOctofStartingIP -eq $ThirdOctofEndingIP)) 
                {
                    foreach ($octLoop in $StartingIpLastOcts)
                    {
                        $checkforcidr = $octLoop+$SubnetPrefixCal
                        if (($SubnetPrefix -ne "23") -and 
                           ([int]$octLoop -ge [int]$FourthOctofStartingIP) -and ([int]$octLoop -le [int]$FourthOctofEndingIP) -and 
                           ($checkforcidr -ge [int]$FourthOctofStartingIP) -and ($checkforcidr -le [int]$FourthOctofEndingIP))
                        {
                            $DifferenceofLastOcts = $FourthOctofEndingIP - $FourthOctofStartingIP
                            $ShortListedGroups    = $IpGroupslt+" = " +$DifferenceofLastOcts
                            $FinalRange           = ($FirstOctofStartingIP.Trim()+"."+$SecondOctofStartingIP.Trim()+"."+$ThirdOctofStartingIP.Trim()+"."+$octLoop)
                            $FinalCIDR            = $FinalRange+"/"+$SubnetPrefix
                            break outsideloop
                        }
                        if (($SubnetPrefix -eq "23") -and ($ExpectedEndingIP -eq "512") -and ($FourthOctofStartingIP -eq "0") -and ($FourthOctofEndingIP -eq "256"))
                        {
                            $DifferenceofLastOcts = $FourthOctofEndingIP - $FourthOctofStartingIP
                            $ShortListedGroups   += $IpGroupslt+" = " +$DifferenceofLastOcts
                        }
                    }
                }
            }
    
            if (($SubnetPrefix -eq "23") -and ([int]$ShortListedGroups.count -ge 2))
            {
                $FilteredList = $ShortListedGroups | ForEach-Object { if (($_.Split('\=')[-1]).Trim() -eq "256") { $_ } }
                if ($FilteredList)
                {
                    $PrefixIncrement = 24 - [int]$SubnetPrefix
                    :outerloop12
                    foreach ($ModifiedIPs in $FilteredList)
                    {
                        $ModifiedIP = ($ModifiedIPs -split '\=')[0].Trim().Split('\-')[0].Trim()
                        $FirstOctofModifiedIP, $SecondOctofModifiedIP, $ThirdOctofModifiedIP, $FourthOctofModifiedIP = $ModifiedIP.Split('\.')
    
                        $ModifiedIPThirdOct = [int]$ThirdOctofModifiedIP + 1
                        foreach ($FilteredIPs in $FilteredList)
                        {
                            $FilteredIP = ((($FilteredIPs  -split '\=')[0]).Trim()).Split('\-')[0].Trim()
                            $FirstOctofFilteredIP, $SecondOctofFilteredIP, $ThirdOctofFilteredIP, $FourthOctofFilteredIP = $FilteredIP.Split('\.')
    
                            if (($FirstOctofModifiedIP -eq $FirstOctofFilteredIP) -and ($SecondOctofModifiedIP -eq $SecondOctofFilteredIP) -and ($ModifiedIPThirdOct -eq $ThirdOctofFilteredIP))
                            {
                                foreach ($VnetIPAddressRange in $VnetIPAddressList)
                                {
                                    $VNetIPRange, $VNetRangePrefix = $VnetIPAddressRange -split ('\/').Trim()
                                    $FirstOctofVNet, $SecOctofVNet, $ThirdOctofVNet, $FourthOctofVNet = $VNetIPRange -split ('\.').Trim() 
                                    $ThirdOctIncrement = [Math]::Pow(2, (24 - [int]$VNetRangePrefix))
                                    $AddressList       = @()
                                    for ($inc = 0; $inc -lt $ThirdOctIncrement; $inc++)
                                    {
                                        $AddressList += "$FirstOctofVNet.$SecOctofVNet.$ThirdOctofVNet.$FourthOctofVNet"
                                        [int]$ThirdOctofVNet = [int]$ThirdOctofVNet+1
                                    }
                                    if (($ModifiedIP -in $AddressList) -and ($FilteredIP -in $AddressList))
                                    {
                                        $ThirdOctof23 = ($ModifiedIP -split ('\.').Trim())[2]
                                        if (($ThirdOctof23 -eq 0) -or ($ThirdOctof23 % 2 -eq 0)) 
                                        {
                                            $FinalRange   = $ModifiedIP
                                            $FinalCIDR    = $FinalRange+"/"+$SubnetPrefix
                                            break outerloop12
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if ($FinalCIDR -eq $null)
            {
                $FinalCIDR = $null
                $FinalCIDR = "noAddressSpace"
            }
        }    
        else
        {
            $FinalCIDR = $null
            $FinalCIDR = "noAddressSpace"
        }
    }
    return $FinalCIDR
}
