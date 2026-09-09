function vnet-range-update {
    param (
        [string]$subscriptionName,
        [string]$vnetName,
        [string]$vnetRG,
        [string]$vnetIP,
        [int]$maxRetries = 3
    )
  
    #$setSubscription = Set-AzContext -Subscription "$subscriptionName" -ErrorAction Stop
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
    $vnetIP          = $vnetIP.Trim()
    $result          = $null

    # ---------------------------
    # Retryable fetch of VNet
    # ---------------------------
    $retryCount = 0
    $success = $false
    $vnetExp = $null

    while (-not $success -and $retryCount -lt $maxRetries) {
        try {
            Write-Host "➡️ Attempt $($retryCount + 1): Fetching VNet $vnetName from $vnetRG..."
            $vnetExp = Get-AzVirtualNetwork -ResourceGroupName "$vnetRG" -Name "$vnetName" -ErrorAction Stop
            $success = $true
        }
        catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                $delay = [math]::Pow(2, $retryCount)
                Write-Warning "⚠️ Attempt $retryCount to fetch VNet failed: $($_.Exception.Message)"
                Write-Host "⏳ Retrying in $delay seconds..."
                Start-Sleep -Seconds $delay
            }
            else {
                Write-Error "❌ All $maxRetries attempts failed to fetch VNet $vnetName in $vnetRG."
                return "Fetch Failed"
            }
        }
    }

    # ---------------------------
    # Add IP if not already present
    # ---------------------------
    if ($vnetIP -notin $vnetExp.AddressSpace.AddressPrefixes) {
        $vnetExp.AddressSpace.AddressPrefixes.Add($vnetIP) | Out-Null

        $retryCount = 0
        $success = $false

        while (-not $success -and $retryCount -lt $maxRetries) {
            try {
                Write-Host "➡️ Attempt $($retryCount + 1): Updating VNet $vnetName with new range $vnetIP..."
                $setVNet = Set-AzVirtualNetwork -VirtualNetwork $vnetExp -ErrorAction Stop
                Start-Sleep -Seconds 5

                # Verify update
                $vnetVerify = Get-AzVirtualNetwork -ResourceGroupName "$vnetRG" -Name "$vnetName" -ErrorAction Stop
                if ($vnetIP -in $vnetVerify.AddressSpace.AddressPrefixes) {
                    Write-Host "✅ Added the new address range ($vnetIP) to $vnetName"
                    $result = "Added"
                    $success = $true
                }
                else {
                    throw "❌ Verification failed: $vnetIP not found in $vnetName after update."
                }
            }
            catch {
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    $delay = [math]::Pow(2, $retryCount)
                    Write-Warning "⚠️ Attempt $retryCount to update VNet failed: $($_.Exception.Message)"
                    Write-Host "⏳ Retrying in $delay seconds..."
                    Start-Sleep -Seconds $delay
                }
                else {
                    Write-Error "❌ All $maxRetries attempts failed to update VNet $vnetName."
                    $result = "Not Added"
                }
            }
        }
    }
    else {
        Write-Host "ℹ️ Address range $vnetIP already present in $vnetName."
        $result = "vnetIP already Present"
    }

    return $result
}
