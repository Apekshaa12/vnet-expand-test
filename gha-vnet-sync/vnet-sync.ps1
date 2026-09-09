function Get-SyncStatus 
{
    Param (
        [string]$subscriptionName,
        [string]$vnetName,
        [string]$vnetRG
    )

    $peeringDetails   = $Null
    $peeredVNetIDs    = $Null
    $peeredSyncStatus = @()
    $failedSyncVNets  = @()
    

    # Peered VNet to Self VNet Sync
    $peeringDetailsPeered = Get-AzVirtualNetworkPeering -VirtualNetwork "$vnetName" -ResourceGroupName "$vnetRG"
    foreach ($peeringDetail in $peeringDetailsPeered)
    {
        $peeredVNetID         = $peeringDetail.RemoteVirtualNetwork.Id
        $splitPeeredVNetID    = $peeredVNetID -split '/'
        $peeredVnetName       = $splitPeeredVNetID[-1]
        $peeredSubscriptionID = $splitPeeredVNetID[2]
        $peeredRGName         = $splitPeeredVNetID[4]
        try
        {
            #Set-AzContext -Subscription "$peeredSubscriptionID" -ErrorAction Stop
            $retry = 0
            while ($retry -lt 3) {
                 try {
                     $setSubsription = Set-AzContext -Subscription "$peeredSubscriptionID" -ErrorAction Stop
                     break
                 } catch {
                     Write-Host "Set-AzContext failed. Attempt $($retry+1) of 3"
                     Start-Sleep -Seconds 3
                 $retry++
                     if ($retry -eq 3) {
                        throw "Failed to set context for subscription: $peeredSubscriptionID"
                     }
               }
             }
        }
        catch 
        {
            $peeredSyncStatus += "Failed"
            $failedSyncVNets  += (($peeringDetail.RemoteVirtualNetwork.Id) -split '/')[-1]
            Write-Host "Sync Not Happened"
            continue
        }
        $peeredVNetDetails = Get-AzVirtualNetworkPeering -VirtualNetwork "$peeredVnetName" -ResourceGroupName "$peeredRGName"
        foreach ($peeredVNetDetail in $peeredVNetDetails)
        {
            $peeredVNetLinkName = $peeredVNetDetail.Name
            if ($peeredVNetDetail.PeeringSyncLevel -eq "FullyInSync")
            {
                $peeredSyncStatus += "FullyInSync"
                Write-Host "Already FullyInSync"
            }
            else
            {
                try
                {
                    $syncDetails  = Sync-AzVirtualNetworkPeering -VirtualNetworkName "$peeredVnetName" -ResourceGroupName "$peeredRGName" -Name "$peeredVNetLinkName" -ErrorAction Stop
                    $syncStatus   = $syncDetails.PeeringSyncLevel
                    if ($syncStatus -eq "FullyInSync")
                    {
                        $peeredSyncStatus += "FullyInSync"
                        Write-Host "FullyInSync"
                    }
                    else
                    {
                        $peeredSyncStatus += "Failed"
                        $failedSyncVNets  += (($peeredVNetDetail.RemoteVirtualNetwork.Id) -split '/')[-1]
                        Write-Host "Sync Not Happened"
                    }
                }
                catch
                {
                    $peeredSyncStatus += "Failed"
                    $failedSyncVNets  += (($peeredVNetDetail.RemoteVirtualNetwork.Id) -split '/')[-1]
                    Write-Host "Sync Not Happened"
                    continue
                }
            }
        }
    }

    #Set-AzContext -Subscription $subscriptionName
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

    # Self VNet to Peered VNet Sync
    $peeringDetails   = Get-AzVirtualNetworkPeering -VirtualNetwork "$vnetName" -ResourceGroupName "$vnetRG"
    foreach ($peeringDetail in $peeringDetails)
    {
        $vnetLinkName = $peeringDetail.Name
        if ($peeringDetail.PeeringSyncLevel -eq "FullyInSync")
        {
            $peeredSyncStatus += "FullyInSync"
            Write-Host "Already FullyInSync"
        }
        else
        {
            try
            {
                $selfSyncDetails = Sync-AzVirtualNetworkPeering -VirtualNetworkName "$vnetName" -ResourceGroupName "$vnetRG" -Name "$vnetLinkName" -ErrorAction Stop
                $selfSyncStatus  = $selfSyncDetails.PeeringSyncLevel
                if ($selfSyncStatus -eq "FullyInSync")
                {
                    $peeredSyncStatus += "FullyInSync"
                    Write-Host "FullyInSync"
                }
                else
                {
                    $peeredSyncStatus += "Failed"
                    $failedSyncVNets  += (($peeringDetail.RemoteVirtualNetwork.Id) -split '/')[-1]
                    Write-Host "Sync Not Happened"
                }
            }
            catch
            {
                $peeredSyncStatus += "Failed"
                $failedSyncVNets  += (($peeringDetail.RemoteVirtualNetwork.Id) -split '/')[-1]
                Write-Host "Sync Not Happened"
                continue
            }

        }
    }

    return @{
        peeredSyncStatus = $peeredSyncStatus
        failedSyncVNets  = $failedSyncVNets
    }
}
