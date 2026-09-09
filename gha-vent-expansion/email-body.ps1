Function email-subject-body {
    Param (
        [string]$prdhquser,
        [string]$prdhqpwd,
        [string]$message = "NA",
        [string]$errormessage = "NA",
        [string]$successTable = "NA",
        [string]$FailTable = "NA",
        [string]$emailType = "NA"
    )
    Write-Host "Email Notification"
    $part1 = @"
        <html>
        <head>
            <style>
                table {
                    border-collapse: collapse;
                    width: 80%;
                    margin: auto;
                }
                th, td {
                    border: 1px solid black;
                    padding: 8px;
                    text-align: center;
                    vertical-align: middle;
                }
                th {
                    background-color: #3498db;
                    color: white;
                }
                table {
                    font-family: Arial, sans-serif;
                    font-size: 14px;
                }
            </style>
        </head>
        <body>
            <table border='1'>
                <thead>
                    <tr>
                        <th style="width: 30%;">VNet Name</th>
                        <th style="width: 25%;">Newly added CIDR</th>
                        <th style="width: 10%;">Sync Status</th>
"@
    $part2 = @"
                    </tr>
            </thead>
            <tbody>
"@
    $part3 = @"
            </tbody>
        </table>
        </body>
        </html>
"@
    $TableforSuccessItems = @"
    $part1
                    <th style="width: 30%;">Action required from Network Team</th>
    $part2
                $successTable
    $part3
"@
    $TableforFailedItems = @"
    $part1
    $part2
    $FailTable
    $part3
"@
    $body1 = @"
        <html>
            Hello Team
            <br><br>
"@
    $body2 = @"
            <br><br>
            Best Regards,<br>
            IaC Automation Team<br>
            <b>Note: You cannot reply to this e-mail.</b>
        </html>
"@
    # Success Case
    if ($emailType -eq "normal") {
        $subject1 = "VNet Expansion | Standard, FiT | Automation Pipeline - Successful"
        $subject2 = "VNet Expansion | Standard, FiT | Automation Pipeline - Failed"
        $positive = @"
            Please find the below <b>VNet Expansion</b> table.
            <br><br>
            $TableforSuccessItems
"@
        $negative = @"
            Please find the below <b>Failed VNet Expansion</b> details table.
            <br><br>
            $TableforFailedItems
"@
        if ($message -eq "allSuccess") {
            $subject = $subject1
            $body = @"
                $body1 
                Automation pipeline executed successfully.
                <br><br>
                Determined that there is sufficient space available (/25 - Standard and /24 - FiT CIDR range) in the VNet across all subscriptions which are in scope. Therefore, there is <b>no immediate need to expand the VNets</b> at this time.
                $body2
"@
        }
        elseif ($message -eq "onlyVNetExpSuccess") {
            $subject = $subject1
            $body = @"
                $body1
                $positive
                $body2
"@
        }
        elseif ($message -eq "onlyVNetExpFail") {
            $subject = $subject2
            $body = @"
                $body1 
                $negative
                $body2
"@
        }
        elseif ($message -eq "combVNetSuccessFail") {
            $subject = $subject2
            $body = @"
                $body1
                $positive
                <br><br>
                $negative
                $body2
"@
        }
    }
    # Failure 
    elseif ($emailType -eq "failed") {
        $subject = "VNet Expansion | Standard, FiT | Automation Pipeline - Failed"
        $firstLine = "Automation pipeline got failed with the below mentioned error."
        $defaultMsg = "<b><span style='color: red;'>Failure Error Message: </span></b>$errormessage"
        $secondLine1 = "Please find the list of <b>Expanded VNet</b> details preceding the pipeline failure in the below table."
        $secondLine2 = "Please find the list of <b>Failed VNet Expansion</b> details preceding the pipeline failure in the below table."
        $commonMsg = @"
            $firstLine
            <br><br>
            $defaultMsg
"@
        $positive = @"
            <br><br>
            $secondLine1
            <br><br>
            $TableforSuccessItems
"@
        $negative = @"
            <br><br>
            $secondLine2
            <br><br>
            $TableforFailedItems
"@
        if ($message -eq "allSuccess") {
            $body = @"
                $body1 
                $commonMsg
                $body2
"@
        }
        elseif ($message -eq "onlyVNetExpSuccess") {
            $body = @"
                $body1
                $commonMsg
                $positive
                $body2
"@
        }
        elseif ($message -eq "onlyVNetExpFail") {
            $body = @"
                $body1
                $commonMsg
                $negative 
                $body2
"@
        }
        elseif ($message -eq "combVNetSuccessFail") {
            $body = @"
                $body1
                $commonMsg
                $positive
                $negative
                $body2
"@
        }
    }
    Write-Host "subject is: $subject"
    Write-Host "body is: $body"
    # Output the variables
    [PSCustomObject]@{
        subject = $subject
        body = $body
    }
}
