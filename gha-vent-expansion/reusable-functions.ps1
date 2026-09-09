# Reusability Functions

# Function to check if all mandatory inputs are provided (i.e., not empty or null)
function Ensure-MandatoryInputs
{
    param (
        [hashtable]$Inputs
    )
    $Presence = "Not Empty"
    foreach ($Key in $Inputs.Keys)
    {
        if ([string]::IsNullOrEmpty($Inputs[$Key]))
        {
            Write-Host "$Key is a mandatory input and is empty"
            $Presence = "Empty"
        }
    }
    return $Presence
}

# Fetches resource details or provisioning state for the specified resource type (subnet, route table, nsg, vnet) based on action
function Get-ResourceDetails 
{
    param (
        [string]$ResourceType,
        [string]$Action,         
        [string]$ResourceGroupName = $Null,  
        [string]$ResourceName,    
        [string]$VnetName = $Null
    )    

    if ($ResourceType -notin @('subnet', 'routetable', 'nsg', 'vnet', 'rg')) 
    { 
        Write-Error "Invalid resource type."
        return 
    }
    if ($Action -notin @('details', 'provisioningState')) 
    { 
        Write-Error "Invalid action."
        return 
    }

    switch ($ResourceType) 
    {
        'rg'     
        { 
            $resource = (Get-AzResourceGroup -Name "$ResourceName" -ErrorAction SilentlyContinue) 
        }
        'subnet'     
        { 
            $resource = (Get-AzVirtualNetwork -Name "$VnetName" -ResourceGroupName "$ResourceGroupName" | Get-AzVirtualNetworkSubnetConfig | Where-Object { $_.Name -eq "$ResourceName" } -ErrorAction SilentlyContinue) 
        }
        'routetable' 
        { 
            $resource = (Get-AzRouteTable -Name "$ResourceName" -ResourceGroupName "$ResourceGroupName" -ErrorAction SilentlyContinue)
        } 
        'nsg'        
        { 
            $resource = (Get-AzNetworkSecurityGroup -Name "$ResourceName" -ResourceGroupName "$ResourceGroupName" -ErrorAction SilentlyContinue)
        }
        'vnet'       
        { 
            $resource = (Get-AzVirtualNetwork -Name "$ResourceName" -ResourceGroupName "$ResourceGroupName" -ErrorAction SilentlyContinue)
        }
    }

    switch ($Action) 
    {
        'details' 
        { 
            return $resource 
        }
        'provisioningState' 
        { 
            return $resource.ProvisioningState 
        }
    }
}

# This function reads JSON data from a file and returns the parsed object
function Get-JsonData 
{
    param (
        [string]$jsonFilePath
    )
    $jsonData   = Get-Content "$jsonFilePath"
    $jsonObject = $jsonData |  ConvertFrom-Json
    return $jsonObject
}

# Fetch the Peered VNet details
Function Get-PeeredVNetDetails
{
    Param (
        $vnetName,
        $vnetRG
    )
    $peeredVNetIds   = @()
    $peeredVNetName  = @()
    $peeredVNetIds   = (Get-AzVirtualNetworkPeering -VirtualNetwork "$vnetName" -ResourceGroupName "$vnetRG").RemoteVirtualNetwork.Id
    $peeredVNetNames = $peeredVNetIds | ForEach-Object { ($_ -split "/")[-1] }
    return $peeredVNetNames
}

# # Fetch the sync status
# Function Get-SyncStatus 
# {
#     Param (
#         $subscription_name = "NA",
#         $sync = "NA",
#         $vnetName = "NA",
#         $vnetrg = "NA",
#         $vnettype = "NA"
#     )
#     if ($vnettype -eq "spoke")
#     {
#         write-host "Spoke"
#         $spokeDetails, $spokeVNetID, $HubVNetName, $HubSubscriptionID, $HubRGName, $HubDetails = $null
#         $spokeDetails = Get-AzVirtualNetworkPeering -VirtualNetwork "$vnetName" -ResourceGroupName "$vnetrg"
#         $spokeVNetID = $spokeDetails.RemoteVirtualNetwork.Id
#         $HubVNetName = ($spokeVNetID -split '/')[-1]
#         $HubSubscriptionID = ($spokeVNetID -split '/')[2]
#         $HubRGName = ($spokeVNetID -split '/')[4]
#         Set-AzContext -Subscription "$HubSubscriptionID"
#     }
#     if ($vnettype -eq "hub")
#     {
#         write-host "Hub"
#         $HubVNetName = "$vnetName"
#         $HubRGName   = "$vnetrg"
#     }
#     $HubDetails = Get-AzVirtualNetworkPeering -VirtualNetwork "$HubVNetName" -ResourceGroupName "$HubRGName"
#     $hubSyncState = @()
#     :hubloop
#     foreach ($HubDlt in $HubDetails) 
#     {
#         if ($sync -eq "Required")
#         {
#             if (($HubDlt.RemoteVirtualNetwork.Id -split "/")[-1] -eq "$vnetName")
#             {
#                 write-host "Sync process is required from hub to spoke"
#                 $HubName, $HubsyncDetails, $hubSyncStatus = $null
#                 $HubName = $HubDlt.Name
#                 $HubsyncDetails = Sync-AzVirtualNetworkPeering -VirtualNetworkName "$HubVNetName" -ResourceGroupName "$HubRGName" -Name "$HubName"
#                 Start-Sleep -Seconds 5
#                 $hubSyncStatus = $HubsyncDetails.PeeringSyncLevel
#                 if ($hubSyncStatus -eq "FullyInSync")
#                 {
#                     $hubSyncState = "Present"
#                     write-host "Sync Present"
#                 }
#                 else
#                 {
#                     $hubSyncState = "NotPresent"
#                     write-host "Sync not Completed"
#                 }
#                 break hubloop
#             }
#         }
#         else
#         {
#             write-host "Checking the sync status"
#             $hubSyncStatus = $null
#             $hubSyncStatus = $HubDlt.PeeringSyncLevel
#             if ($hubSyncStatus -eq "FullyInSync")
#             {
#                 $hubSyncState += "Present"
#                 write-host "Sync Present"
#             }
#             else
#             {
#                 $hubSyncState += "NotPresent"
#                 write-host "Sync not Completed"
#             }
#         }
#     }
#     $finalStatus = $null
#     if ("NotPresent" -in $hubSyncState)
#     {
#         $finalStatus = "Not sync"
#     }
#     else
#     {
#         $finalStatus = "sync"
#     }
#     Set-AzContext -Subscription "$subscription_name"
#     return $finalStatus
# }

function Generate-HTMLTable 
{
    param (
        [Parameter(Mandatory = $true)]
        [array]$Data,
        [string]$content,
        [string]$ErrorMessage  = $null,
        [string]$EmailGreeting = $null,
        [string]$EmailClosing  = $null
    )

    if ($Data -ne "not required")
    {
        $htmlContent = @"
            <html>
            <head>
                <style>
                    body {
                        font-family: Arial, sans-serif;
                        font-size: 12px;
                        margin: 0;
                        padding: 0;
                    }
                    .table-wrapper {
                        display: flex;
                        justify-content: center;
                        margin-top: 20px;
                    }
                    table {
                        width:800px;
                        table-layout: fixed;
                        border-collapse: collapse;
                        background-color: #fff;
                        border: 1px solid #ccc;
                    }
                    th, td {
                        border: 1px solid #ccc;
                        padding: 6px;
                        text-align: center;
                        overflow-wrap: break-word;
                        word-wrap: break-word;
                        word-break: break-all;
                    }
                    th {
                        background-color: #87CEFA; 
                        color: white;
                        font-weight: bold;
                        text-align: center;
                    }
                    tr:nth-child(even) {
                        background-color: #f9f9f9;
                    }
                    tr:nth-child(odd) {
                        background-color: #ffffff;
                    }
                    td {
			word-wrap: break-word;
                    }
                    .status {
			font-size: 16px;
			font-weight: bold;
			color: #28a745;
                    }
                    .failed {
			color: #FF0000; 
                    }
                    .bold-black {
			font-weight: bold;
			color: #000000;
                    }
                    .error-message {
			color: #FF0000;
			font-weight: bold;
			margin-top: 10px;
                    }
                    .error-detail {
			color: #000000;
			font-weight: normal;
			margin-top: 5px;
                    }
                    td:first-child {
			min-width: 120px;
			max-width: 200px;
                    }
                    td:last-child {
			min-width: 150px;
			max-width: 300px;
                    }
                    .table-container {
			max-height: 500px;
			overflow: auto; 
                    }
                </style>
            </head>
            <body>
"@
    }

    if ($EmailGreeting -eq 'required') 
    {
        $htmlContent += "<p>Hello Team,</p>"
    }

    $htmlContent += "<p>$content</p>"

    if ($Data -ne "not required")
    {
        $htmlContent += @"
            <div class='table-wrapper'>
                <table>
                    <tr>
                        <th>VNet Name</th>
                        <th>CIDR</th>
                        <th>Sync</th>
                        <th>RTB UDR</th>
                        <th>NSG Rule</th>
                    </tr>
"@

        foreach ($item in $Data) 
        {
            $vnetName      = $item.'VNet Name'
            $cidr          = $item.CIDR
            $syncStatus    = $item.'Sync'
            $rtbUpdate     = $item.'RTB UDR'
            $nsgUpdate     = $item.'NSG Rule'

            if ($vnetName -match '(?i)Failed') 
            {
                $vnetName = "<span style='color:red;'>$vnetName</span>"
            }
            if ($cidr -match '(?i)Failed') 
            {
                $cidr = "<span style='color:red;'>$cidr</span>"
            }
            if ($syncStatus -match '(?i)Failed') 
            {
                $syncStatus = "<span style='color:red;'>$syncStatus</span>"
            }
            if ($rtbUpdate -match '(?i)Failed') 
            {
                $rtbUpdate = "<span style='color:red;'>$rtbUpdate</span>"
            }
            if ($nsgUpdate -match '(?i)Failed') 
            {
                $nsgUpdate = "<span style='color:red;'>$nsgUpdate</span>"
            }

            $htmlContent += "<tr><td>$vnetName</td><td>$cidr</td><td>$syncStatus</td><td>$rtbUpdate</td><td>$nsgUpdate</td></tr>"
        }

        $htmlContent += "</table></div>"
    }

    if ($ErrorMessage) 
    {
        $htmlContent += "<p><span style='color: #FF0000;'>Error: </span>$ErrorMessage</p>"
    }

    if ($EmailClosing -eq 'required') 
    {
        $htmlContent += "<p>Best Regards,<br/>IaC Automation Team,</br><b>Note:</b> This is an automated email. Please do not reply.</p>"
    }

    $htmlContent += "</body></html>"

    return $htmlContent
}
