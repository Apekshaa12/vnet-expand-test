function IP-Presence
{
    param (
        [string]$nsgName,
        [string]$vnetRG,
        [string]$newIP
    )
    $status         = $Null
    $nsg            = Get-AzNetworkSecurityGroup -Name "$nsgName" -ResourceGroupName "$vnetRG"
    $inboundRuleIps = @()
    $inboundRuleIps = ($nsg.SecurityRules | Where-Object { $_.Direction -eq "Inbound" -and $_.Name -eq "Deny_FromFitRange_to_Vnet" }).SourceAddressPrefix
    if ($newIP -in $inboundRuleIps)
    {
        $status = "Present"
    }
    else
    {
        $status = "Not There"
    }
    return $status
}

function fetch-nsgnames
{
    param (
        $resourceGroupName
    )
    $rgSplit       = $resourceGroupName -split "-"
    $rgScope       = $rgSplit[0]
    $rgEnvironment = $rgSplit[1]
    $rgDepartment  = $rgSplit[3]
    $rgRegionCode  = $rgSplit[4]
    $nsgNames      = @()

    if ($rgDepartment -eq "informationtechnology") {
        $nsgDept = "it"     # special case
    }
    else {
        $nsgDept = $rgDepartment
    }

    Write-Host "Detected Department: $rgDepartment  → Using NSG Department: $nsgDept"

    # Build patterns
    $patterns = @(
        "$rgScope-$rgEnvironment-g-$nsgDept-$rgRegionCode-*-nsg",
        "$rgScope-$rgEnvironment-c-$nsgDept-$rgRegionCode-*-nsg"
    )

	Write-Host "NSG Matching Patterns:"
    $patterns | ForEach-Object { Write-Host " - $_" }
    
    $nsgNamesList = (Get-AzNetworkSecurityGroup -ResourceGroupName "$resourceGroupName" -ErrorAction SilentlyContinue).Name 
    $nsgnames     = @()
    
    if ($nsgNamesList.Count -gt 0)
    {
        foreach ($nsgName in $nsgNamesList)
        {
            $matchFound =  $patterns | Where-Object { $nsgName -like $_ }
            if ($matchFound) 
            {
               $nsgnames += $nsgName
            }
        }
    }
	Write-Host "Filtered NSG names are:"
    $nsgnames | ForEach-Object { Write-Host " - $_" }
    return $nsgnames
}

function Remove-NSGInboundRuleForMissingASG
{
    param (
	[string]$filePath
    )
    $inputFileContent = Get-Content -Path $filePath -Raw
    $asgNames         = [regex]::Matches($inputFileContent, '/applicationSecurityGroups/([^/"]+)') | ForEach-Object { $_.Groups[1].Value }
    $uniqueAsgNames   = $asgNames | Select-Object -Unique
    if ($uniqueAsgNames)
    {
    	foreach ($uniqueAsg in $uniqueAsgNames)
        {
	   if (((Get-AzApplicationSecurityGroup -Name $uniqueAsg -ErrorAction SilentlyContinue).ProvisioningState) -eq "Succeeded") {}
           else 
           {
		$fileContent     = Get-Content -Path $filePath -Raw
		$modifiedContent = $fileContent -replace "(?s)\{[^{}]*$uniqueAsg[^{}]*\}(?:\s*,)?", ""
		$modifiedContent | Set-Content -Path $filePath
		$modifiedContent = $modifiedContent -replace "(.*),`r?`n\s*(`r?`n\s*)?\]", "`$1`r`n`$2]"
	        $modifiedContent | Set-Content -Path $filePath
		$modifiedContent = $modifiedContent -replace "`r?`n\s*`r?`n", "`r`n"
		$modifiedContent = $modifiedContent.TrimEnd()
		$cleanedContent  = $modifiedContent | Where-Object { $_ -match '\S' }
	        $cleanup         = $cleanedContent  | Set-Content -Path $filePath
	    }
	} 
    }
}

function nsg-rule-update
{ 
    param(
        $adoPat,
        $subscriptionName,
        $vnetName,
        $vnetRG,
        $newIP,
        $userEmail,
        $userName,
        $sourceDirectory,
	$runNumber
    )
    write-host "nsg update function $vnetName, $vnetRG, $newIP, $userEmail, $userName, $sourceDirectory, $runNumber"
    $gitConfigUserEmail = git config --global user.email "$userEmail"
    $gitConfigUserName  = git config --global user.name "$userName"
    $gitClone           = git clone "https://bogususer:$adoPat@dev.azure.com/nestle-it/STIG/_git/ChinaConfigs"

    $cd                 = cd "$sourceDirectory/ChinaConfigs/"
    $gitCheckout        = git checkout master

    $updateStatus = @()

    $nsgNames = fetch-nsgnames -resourceGroupName "$vnetRG"
	Write-Host "NSG names are:"
    foreach ($nsg in $nsgNames) {
      Write-Host " - $nsg"
    }

    foreach ($nsgName in $nsgNames)
    {
	    write-host "NSG name is $nsgName"
    	$foldername = "$subscriptionName"+"_"+"$vnetName"
        $filePath   = "$sourceDirectory/ChinaConfigs/tf/az/$foldername/$nsgName.tf"
		write-host "file path is $filePath"
        
        $removeASGRules = Remove-NSGInboundRuleForMissingASG -filePath "$filePath"

        if (Test-Path $filePath) 
        {
            Write-Output "File is present: $filePath"
            $content     = Get-Content $filePath
            $existingIPs = @()
        
            for ($i = 0; $i -lt $content.Count; $i++) 
            {
                $line = $content[$i].Trim()
                if ($line -match '^name\s*=\s*"Deny_FromFitRange_to_Vnet"$') 
                {
                    $j = $i+1
                    Write-Host "Found target name i.e Deny_FromFitRange_to_Vnet at line $j"
		    $foundTargetName = "found"
                    continue
                }
                if (($foundTargetName -eq "found") -and ($line -match '^\s*source_address_prefixes\s*=\s*\[(.*)\]'))
                {
                    $k = $i+1
                    Write-Host "Found source_address_prefixes at line $k"
                    $existingIPs = $matches[1] -replace '[\[\]"]', '' -split ',\s*'
                    if ($existingIPs -notcontains $newIP) 
                    {
                        $existingIPs    += $newIP
                        $joinedIPs       = ($existingIPs -join '", "')
                        $newLine         = "                                    " + "source_address_prefixes                     = [`"$joinedIPs`"]"
                        $content[$i]     = $newLine
                        Set-Content $filePath -Value $content -Encoding UTF8
                        $updateStatus    += "updated"
                    }
                    break
                }
            }
        }
    }
    return $updateStatus
}

function git-initial-commands
{
    param (
        $adoPat,
        $subscriptionName,
        $vnetName,
        $vnetRG,
        $newIP,
        $userEmail,
        $userName,
        $sourceDirectory,
        $runNumber 
    )
    $updatedStatus = @()
    $updatedStatus = nsg-rule-update -adoPat "$adoPat" -subscriptionName "$subscriptionName" -vnetName "$vnetName" `
        -vnetRG "$vnetRG" -newIP "$newIP" -userEmail "$userEmail" -userName "$userName" -sourceDirectory "$sourceDirectory" -runNumber "$runNumber"

    if ("updated" -in $updatedStatus) 
    {
        git pull origin master
		$timestamp = (Get-Date).ToString("yyyyMMddHHmmss")
		$global:tempBranch = "testing_$timestamp_$runNumber"
		git checkout -b $global:tempBranch
        git add .
        git commit -m "Self RG commit - Run Number $runNumber, Commit from VNet Expansion Github Action."
    }
}
    
function update-nsg-rule
{
    param (
        $adoPat,
        $subscriptionName,
        $vnetName,
        $vnetRG,
        $newIP,
        $userEmail,
        $userName,
        $sourceDirectory,
        $runNumber 
    )

    $maxRetries = 20
    $retryCount = 0
    $statusgit  = "failure"
    while ($retryCount -le $maxRetries)
    {
        try 
        {
            $gitPushResult = ""
            $gitCommands = git-initial-commands -adoPat "$adoPat" -subscriptionName "$subscriptionName" -vnetName "$vnetName" `
                -vnetRG "$vnetRG" -newIP "$newIP" -userEmail "$userEmail" -userName "$userName" `
                -sourceDirectory "$sourceDirectory" -runNumber "$runNumber"
            #$gitPushResult = 
	    #git push origin master
		git checkout master
		git pull origin master
		git merge $global:tempBranch
		git push origin master
            if ($LASTEXITCODE -eq 0) 
            {
                $statusgit = "success"
                break
            }
         } 
         catch
         {
            $errorCheck = $_.Exception.Message
            Write-Host "Retry attempt $($retryCount + 1): $errorCheck"
            $retryCount++
            $retryDelaySeconds = (Get-Random -Minimum 20 -Maximum 30)
            Write-Host "Sleep for $retryDelaySeconds seconds"
            $sleep = Start-Sleep -Seconds $retryDelaySeconds
            $gitCommands = git-initial-commands -adoPat "$adoPat" -subscriptionName "$subscriptionName" -vnetName "$vnetName" `
                -vnetRG "$vnetRG" -newIP "$newIP" -userEmail "$userEmail" -userName "$userName" `
                -sourceDirectory "$sourceDirectory" -runNumber "$runNumber"
         }
    }
    
    $nsgUpdateFailed  = @()
    $nsgUpdateSuccess = @()
    $nsgNames         = fetch-nsgnames -resourceGroupName "$vnetRG"
    $nsgNamesCount    = $nsgNames.count
    
    if ($statusgit -ne "success")
    {
        Write-Host "Operation failed after $maxRetries retries. Pipeline failed to add the NSG inbound rule to the ChinaConfigs repo due to git merge issues"
 	$failedNSGCount   = 0
        $nsgUpdateFailed  = 0
        $successNSGCount  = 0
        $nsgUpdateSuccess = 0
    }
    if ($statusgit -eq "success")
    {
        Write-Host "git push finished successfully"
        Write-Host "Waiting for 120 seconds to get NSG pipeline triggered"
        Start-Sleep -Seconds 120
 
        foreach ($nsgName in $nsgNames)
        {
            for ($i = 0; $i -lt 10; $i++) 
            {
			    write-host "nsg name is $nsgName $vnetRG $newIP"
                $IPUpdateStatus = IP-Presence -nsgName "$nsgName" -vnetRG "$vnetRG" -newIP "$newIP"
                if ($IPUpdateStatus -eq "Present") 
                {
                    Write-Host "NSG Rule has been updated"
                    $nsgdep = "Deployed"
                    break
                }
                else
                {
                    Write-Host "NSG Rule has not updated yet"
                    Write-Host "Sleeping for 10 seconds..."
                    Start-Sleep -Seconds 60
                }
            }
            
            if ($nsgdep -ne "Deployed")
            {
                Write-Host "After maximum iterations NSG rule was unable to update"
                $nsgUpdateFailed += "$nsgName"
            }
            if ($nsgdep -eq "Deployed") 
	    {
     		$nsgUpdateSuccess += "$nsgName"
	    }
        }
	
	$failedNSGCount  = $nsgUpdateFailed.Count
 	$successNSGCount = $nsgUpdateSuccess.Count
    }
    return @{
        TotalNSGCount   = $nsgNamesCount
        FailedNSGCount  = $failedNSGCount
        MissedNSGNames  = $nsgUpdateFailed
        SuccessNSGCount = $successNSGCount
        SuccessRTBs     = $nsgUpdateSuccess
    }
}
