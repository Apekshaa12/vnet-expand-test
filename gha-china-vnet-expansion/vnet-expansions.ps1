function vnet-expansion 
{
    param (
        [string]$adoPat,
        [string]$service_account_user,
        [string]$service_account_password,
        [string]$source_directory,
        [string]$tenant,
        $port,
        [string]$smtp_server,
        [string]$run_number
    )
    
   try
   {
        # Load configuration data from the vnet-expansion-configurations.json file 
        # New dummy change
        Import-Module "$source_directory\gha-china-vnet-expansion\reusable-functions.ps1"
        Import-Module "$source_directory\gha-vnet-cidr-calculation\vnet-cidr-calculation.ps1"
        Import-Module "$source_directory\gha-vnet-range-update\gha-vnet-range-update.ps1"
        Import-Module "$source_directory\gha-vnet-sync\vnet-sync.ps1"
        Import-Module "$source_directory\gha-route-table-update\rtb-update.ps1"
        Import-Module "$source_directory\gha-china-nsg-update\nsg-rule-update.ps1"
        Import-Module "$source_directory\gha-email-notification\email-notification.ps1"
        
        $jsonFilePath = "$source_directory\gha-china-vnet-expansion\vnet-expansion-configurations.json"
        $jsonData     = Get-JsonData -jsonFilePath "$jsonFilePath"
        $data         = @()
        $emailSubject = $jsonData.($tenant + "_Email_Information").'Subject'
        
        # Finalize the scoped subscriptions
        $managementGroup = @()
        $managementGroup = $jsonData.($tenant + "_ManagementGroupList").'ManagementGroupList'
        Write-Host "Scoped Managed Groups: "
        $managementGroup
        Write-Host "`n"
        
        $excludedSubscriptions = @()
        $excludedSubscriptions = @($jsonData."${tenant}_Excluded_Subscriptions".Excluded_Subscriptions)
        Write-Host "Out of Scoped Subscriptions: "
        $excludedSubscriptions
        Write-Host "`n"
        
        $subscriptionsList = Search-AzGraph -Query "ResourceContainers | where type=='microsoft.resources/subscriptions' 
                             | mv-expand managementGroupParent = properties.managementGroupAncestorsChain 
                             | where managementGroupParent.displayName == '$managementGroup'"
        $subscriptionsList.count
        
        $finalSubscriptionsList = $subscriptionsList | Where-Object { $name = $_; -not ($excludedSubscriptions | Where-Object {$name.name -match $_ }) }
        $subscriptionNamesList  = $($finalSubscriptionsList.name)
        $subscriptionsCount     = $subscriptionNamesList.count
        Write-Host "Scoped Subscriptions count is:"
        $subscriptionsCount
        Write-Host "`n"
        
        $loopNumber       = 0
        $VNetExpandReq    = @()
        $failedTable      = @()
        $successVNetTable = @()

        # Loop across all the scoped Subscriptions

        foreach ($subscriptionName in $subscriptionNamesList)
        {
            cd "$source_directory"
            # Print the loop details
            $loopNumber = $loopNumber+1
            write-host "Subscription Loop Number : $loopNumber - $subscriptionName"
    
            # Set the subscription
            #Set-AzContext -Subscription "$subscriptionName"
            $retry = 0
            while ($retry -lt 3) {
                 try {
                     $setSubsription = Set-AzContext -Subscription $subscriptionName -ErrorAction Stop
                     break
                 } catch {
                     Write-Host "Set-AzContext failed. Attempt $($retry+1) of 3"
                     Start-Sleep -Seconds 3
                 $retry++
                     if ($retry -eq 3) {
                        throw "Failed to set context for subscription: $subscriptionName"
                     }
               }
             }
            try
            {
                $response = $null
                $vnetName = $null
                $vnetRG   = $null
                $url      = "https://iacapi.nestle.com/azure/chvnet/lookup?subscription=$subscriptionName"
                $response = Invoke-RestMethod -Uri $url -Method Get
                $vnetName = $response.vnet
                $vnetRG   = $response.vnetrg 
                Write-Host "VNet for the subscription $subscriptionName is $vnetName"
                Write-Host "VNet RG for the subscription $subscriptionName is $vnetRG"
            } # End of VNet Existence Try Block
            catch
            {
                $vnetName = $null
            } # End of VNet Existence Catch Block
            
            if ([string]::IsNullOrEmpty($vnetName))
            {
                Write-Host "The network VNet is not being retrieved through the API or the VNet fetched via the API is not present in the Azure portal."
            } # End of empty VNet if Condition
           
            # Check the VNet Existence
            if (-not([string]::IsNullOrEmpty($vnetName)) -and ((Get-AzVirtualNetwork -ResourceGroupName "$vnetRG" -Name "$vnetName" -ErrorAction SilentlyContinue).ProvisioningState -eq "Succeeded"))
            {
                Write-Host "The VNet name provided by the API, $vnetName, is present in the Azure portal."
                $expansionTypeList = @()
                $expansionTypeList = $jsonData.($tenant + "_VNet_Expansion_Types").'VNet_Expansion_Types'
                :typeloop
                foreach ($expansionType in $expansionTypeList)
                {
                    Write-Host "Expansion Type - $expansionType"
                    $fitDeScopedSubscriptions = @()
                    $fitDeScopedSubscriptions = $jsonData.($tenant + "_" + $expansionType + "_Excluded_Subscriptions").'Excluded_Subscriptions'
                    $matchFound               = $fitDeScopedSubscriptions | Where-Object { $subscriptionName -match $_ }
                    if (($expansionType -eq "FiT") -and ($matchFound -ne $Null) -and ($subscriptionName -match $matchFound))
                    {
                        Write-Host "VNet expansion on the $subscriptionName is not within the scope for $expansionType."
                    }
                    else
                    {
                        [int]$prefix = $jsonData.($tenant + "_" + $expansionType + "_NetworkPrefix").'NetworkPrefix'
                        $finalIP     = $Null
                        Write-Host "Network Prefix is $prefix"
                        . ./gha-china-subnet-cidr-calculation/subnet-cidr-calculation.ps1
                        $finalIP = Calculate-NewSubnetCIDR -SubscriptionName "$subscriptionName" -VnetName "$vnetName" -VnetRGName "$vnetRG" -SubnetPrefix $prefix -NetworkType "$expansionType" -SourceDirectory "$source_directory" -Tenant "$tenant"
                        $finalIP = $finalIP.Trim()
                        Write-Host "IP: $finalIP"

                        $vnetExpansionList = @()
                        # Address space initially not added, no need of VNet Expansion
                        if ($finalIP -eq "Not a Scoped VNet")
                        {
                            Write-Host "$subscriptionName - $vnetName does not have a scoped address range initially; hence, VNet expansion is not required."   
                        }

                        # Address space present, no need of VNet Expansion
                        if (($finalIP -ne "noAddressSpace") -and ($finalIP -ne "Not a Scoped VNet"))
                        {
                            Write-Host "$subscriptionName - $vnetName has $prefix CIDR range is available ($finalIP), hence no need of VNet Expansion"
                            $vnetExpansionList += "No Need"
                        } # end of vnet expansion not needed
                        
                        # Address space not present, VNet Expansion required
                        if ($finalIP -eq "noAddressSpace")
                        {
                            Write-Host "$subscriptionName - $vnetName has $prefix CIDR range is not available, hence need of VNet Expansion"
                            $vnetExpansionList += "Required"
                            
                            # Get the peered VNet details
                            $peeredVNetNames = @()
                            $peeredVNetNames = Get-PeeredVNetDetails -vnetName "$vnetName" -vnetRG "$vnetRG"
                            Write-Host "Peered VNet Name is $peeredVNetNames"
                            if (-not $peeredVNetNames)
                            {
                                Write-Host "Peering not present"
                            }
                            if (($peeredVNetNames) -and ((($subscriptionName -notmatch "-it-hub-") -and ($peeredVNetNames | Where-Object { $_ -like "*-it.hub-*" })) -or ($subscriptionName -match "-it-hub-")))
                            { 
                                Write-Host "Peering present"
                                #$vnetIP = $Null
                                #$vnetIP = vnet-cidr-calc -subscriptionName "$subscriptionName" -vnetName "$vnetName" -vnetRG "$vnetRG" -expansionType "$expansionType" `
                                #-tenant "$tenant" -jsonFilePath "$jsonFilePath"
                                #$vnetIP = $vnetIP.Trim()

#############
                                # Parameters for retry
                                $maxRetries = 3
                                $retryDelay = 40  # seconds
                                $retryCount = 0
                                $vnetIP = $null
                                $success = $false

                                while (-not $success -and $retryCount -lt $maxRetries) {
                                    try {
                                        Write-Host "➡️ Attempt $($retryCount + 1): Calling vnet-cidr-calc..."

                                        $vnetIP = vnet-cidr-calc -subscriptionName "$subscriptionName" -vnetName "$vnetName" -vnetRG "$vnetRG" -expansionType "$expansionType" `
                                        -tenant "$tenant" -jsonFilePath "$jsonFilePath"


                                        if ([string]::IsNullOrWhiteSpace($vnetIP)) {
                                            throw "❌ vnet-cidr-calc returned empty/null value."
                                        }

                                        $vnetIP = $vnetIP.Trim()
                                        Write-Host "✅ Successfully fetched VNet IP: $vnetIP"
                                        $success = $true
                                    }
                                    catch {
                                        $retryCount++
                                        Write-Warning "⚠️ Attempt $retryCount failed: $($_.Exception.Message)"
                                        if ($retryCount -lt $maxRetries) {
                                            Write-Host "⏳ Retrying in $retryDelay seconds..."
                                            Start-Sleep -Seconds $retryDelay
                                        }
                                        else {
                                            Write-Error "❌ All $maxRetries attempts failed. Could not fetch VNet IP."
                                        }
                                    }
                                }


###############
                                
                                if ($vnetIP -eq "NA")
                                {
                                    $data += [PSCustomObject]@{"VNet Name" = "$vnetName"; "CIDR" = "$expansionType : Failed - Reserved IPs Exhausted"; "Sync" = "-"; "RTB UDR" = "-"; "NSG Rule" = "-"} 
                                }
                                if (($vnetIP -ne "NA") -and ($vnetIP))
                                {
                                    $vnetUpdateStatus = $Null
                                    $vnetUpdateStatus = vnet-range-update -vnetIP "$vnetIP" -subscriptionName "$subscriptionName" -vnetName "$vnetName" -vnetRG "$vnetRG"
    
                                    if ($vnetUpdateStatus -eq "vnetIP already Present")
                                    {
                                        $data += [PSCustomObject]@{"VNet Name" = "$vnetName"; "CIDR" = "$expansionType : Failed - Wrong range picked by automation - $vnetIP"; "Sync" = "-"; "RTB UDR" = "-"; "NSG Rule" = "-"}                                  
                                    }
                                    if ($vnetUpdateStatus -eq "Not Added")
                                    {
                                        $data += [PSCustomObject]@{"VNet Name" = "$vnetName"; "CIDR" = "$expansionType : Failed to add - $vnetIP"; "Sync" = "-"; "RTB UDR" = "-"; "NSG Rule" = "-"}   
                                    }
                                    if ($vnetUpdateStatus -eq "Added")
                                    {
                                        # VNet Sync Process
                                        Write-Host "$vnetIP added to $vnetName Successfully"
                                        $syncUpdate             = Get-SyncStatus -subscriptionName "$subscriptionName" -vnetName "$vnetName" -vnetRG "$vnetRG"
                                        $peeredSyncStatus       = @()
                                        $failedSyncVNets        = @()
                                        $peeredSyncStatus       = $syncUpdate.peeredSyncStatus | Select-Object -Unique
                                        $failedSyncVNets        = $syncUpdate.failedSyncVNets | Select-Object -Unique
                                        $failedSyncVNetsDetails = @()
                                        if ($failedSyncVNets)
                                        {
                                            $syncFailedCount         = $failedSyncVNets.Count
                                            $failedSyncVNetsDetails  = "Failed - $syncFailedCount`n"
                                            $failedSyncVNetsDetails += ($failedSyncVNets -join ", ")
                                        }
                                        else
                                        {
                                            $failedSyncVNetsDetails = "Fully Synchronized"
                                        }
                                        
                                        # Route Table UDR Update
                                         $UDRUpdateResult = rtb-udr-update -subscriptionName "$subscriptionName" -vnetName "$vnetName" -tenant "$tenant" -vnetIP "$vnetIP" -vnetType "$expansionType" -jsonFilePath "$jsonFilePath"
                                         $TotalRTBCount   = $UDRUpdateResult.TotalRTBCount
                                         $SuccessRTBCount = $UDRUpdateResult.SuccessRTBCount
                                         $FailedRTBCount  = $UDRUpdateResult.FailedRTBCount
                                         $MissedRTBNames  = $UDRUpdateResult.MissedRTBNames
                                        write-host "total RTB $TotalRTBCount"
                                        write-host "success RTB $SuccessRTBCount"
                                        write-host "failed RTB $FailedRTBCount"
                                        write-host "missed RTB $MissedRTBNames"
                                        
                                        
                                        $MissedRTBNamesDetails = @()
                                        if (-not $MissedRTBNames)
                                        {
                                            $MissedRTBNamesDetails = "Successful - $SuccessRTBCount/$TotalRTBCount"
                                        }
                                        else
                                        {
                                             $MissedRTBNamesDetails  = "Failed - $FailedRTBCount/$TotalRTBCount`n"
                                             $MissedRTBNamesDetails += ($MissedRTBNames -join ", ")
                                        }
    
                                        # NSG Inbound Rule update through ADO Config Repo
                                        if ($expansionType -eq "FiT")
                                        {
                                            # NSG Inbound Rules Update
                                            $NSGRuleUpdateResult = update-nsg-rule -adoPat "$adoPat" -subscriptionName "$subscriptionName" `
                                                -vnetRG "$vnetRG" -newIP "$vnetIP" -userEmail "$service_account_user" -userName "$service_account_user" `
                                                -sourceDirectory "$source_directory" -runNumber "$run_number" -vnetName "$vnetName"
                                                
                                            $TotalNSGCount   = $NSGRuleUpdateResult.TotalNSGCount
                                            $FailedNSGCount  = $NSGRuleUpdateResult.FailedNSGCount
                                            $MissedNSGNames  = $NSGRuleUpdateResult.MissedNSGNames
                                            $SuccessNSGCount = $NSGRuleUpdateResult.SuccessNSGCount
                                            $SuccessRTBs     = $NSGRuleUpdateResult.SuccessRTBs
                                            write-host "total NSG $TotalNSGCount"
                                            write-host "success NSG $SuccessNSGCount"
                                            write-host "failed NSG $FailedNSGCount"
                                            write-host "missed NSG $MissedNSGNames"
                                            write-host "RTB sucess in NSG $SuccessRTBs"
                                            
                                            $MissedNSGNamesDetails = @()
                                            if (-not $MissedRTBNames)
                                            {
                                                $MissedNSGNamesDetails = "Successful - $SuccessNSGCount/$TotalNSGCount"
                                            }
                                            else
                                            {
                                                $MissedNSGNamesDetails  = "Failed - $FailedNSGCount/$TotalNSGCount`n"
                                                $MissedNSGNamesDetails += ($MissedNSGNames -join ", ")
                                            }
                                        }
                                        else
                                        {
                                            $MissedNSGNamesDetails = "Not Required"
                                        }
    
                                        # Email Communication 
                                        
                                        $data += [PSCustomObject]@{"VNet Name" = "$vnetName"; "CIDR" = "$expansionType :$vnetIP"; "Sync" = "$failedSyncVNetsDetails"; "RTB UDR" = "$MissedRTBNamesDetails"; "NSG Rule" = "$MissedNSGNamesDetails"}
                                        
                                    } # End of IP added to VNet if condition          
                                } # End of VNet IP Reserved Ranges Not Exhausted
                            } # End of Peering Present if condition
                        } # End of VNet Expansion Required if condition
                    } # End of else condition - ignoring some subscriptions for FiT
                } # End of VNet Type (Standard and FiT) Looping
            } # End of VNet if Condition
        } # End of Subscription Looping
        if ($data)
        {
            $ifContent = $jsonData.($tenant + "_Email_Information").'if_content'
            $body      = Generate-HTMLTable -Data $data -content "$ifContent" -EmailGreeting "required" -EmailClosing "required"
        }
        else
        {
            $elseContent = $jsonData.($tenant + "_Email_Information").'else_content'
            $body        = Generate-HTMLTable -Data "not required" -content "$elseContent" -EmailGreeting "required" -EmailClosing "required"
        }
        
        $successfulTo = @()                                    
        $successfulTo = $jsonData.($tenant + "_Email_Information").'Successful_To'

        Write-Host "Body of the email is:"
        $body
        
        $sendEmail = send-email -serviceAccountUser "$service_account_user" -serviceAccountPassword "$service_account_password" `
            -to $successfulTo `
            -from "$service_account_user" -SMTPServer "$smtp_server" -body $body `
            -subject "$emailSubject" -port $port
            
    } # End of Main Try Block                                    
    catch
    {
        write-host "In Catch Block"
        if (!($errorCheck = $Error[0].Exception.Message))
        {
            $errorCheck = $null
            $errorCheck = $Error[0].Message
        }
        Write-Host "Error Message - $errorCheck"
        
        if ($data)
        {
            $ifErrorContent = $jsonData.($tenant + "_Email_Information").'if_Error_Content'
            $body           = Generate-HTMLTable -Data $data -content "$ifErrorContent" -EmailGreeting "required" -EmailClosing "required" -ErrorMessage "$errorCheck"
        }
        else
        {
            $elseErrorContent = $jsonData.($tenant + "_Email_Information").'else_Error_Content'
            $body             = Generate-HTMLTable -Data "not required" -content "$elseErrorContent" -EmailGreeting "required" -EmailClosing "required" -ErrorMessage "$errorCheck"
        }

        $failedTo = @()
        $failedCC = @()
        $failedTo = $jsonData.($tenant + "_Email_Information").'Failed_To'
        $failedCC = $jsonData.($tenant + "_Email_Information").'Failed_CC'

        Write-Host "Body of the email is:"
        $body
        
        $sendEmail = send-email -serviceAccountUser "$service_account_user" -serviceAccountPassword "$service_account_password" `
                         -to $failedTo -subject "$emailSubject" -body $body -ccEmail $failedCC `
                         -from "$service_account_user" -SMTPServer "$smtp_server" -port $port
        exit 1
    } # End of Main Catch Block
} # End of Main Function
