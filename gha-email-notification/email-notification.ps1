function send-email 
{
    Param (
        [string]$serviceAccountUser,
        [string]$serviceAccountPassword,
        $to,
        [string]$from,
        [string]$SMTPServer,
        [string]$body,
        [string]$subject,
        [string]$port,
        $ccEmail = $Null
    )
    
    $htmlBody = $true
    if ((-not $to) -or (-not $subject)) 
    {
        return "No subject or to specified. Aborting."
    }
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    $smtpcient             = New-Object System.Net.Mail.SmtpClient($SMTPServer)
    $smtpcient.Port        = $port
    $smtpcient.EnableSsl   = $True
    $smtpcient.Credentials = New-Object System.Net.NetworkCredential("$serviceAccountUser", "$serviceAccountPassword")
    $message               = New-Object System.Net.Mail.MailMessage
    $message.From          = $from
    $message.Subject       = $subject

    $to.Split(',') | ForEach-Object { $message.To.Add($_.Trim()) }

    if ($ccEmail) 
    {
        $ccEmail.Split(',') | ForEach-Object { $message.CC.Add($_.Trim()) }
    }
    
    if ($htmlbody) { $message.IsBodyHtml = $true }
    $message.Body = $body
    if ($attachments) 
    {
        foreach ($attachment in $attachments) 
        {
            if (test-path $attachment) 
            {
                $message.attachments.add((new-object Net.Mail.Attachment($attachment)))
            }
            else 
            {
                write-host "Could not find file $($attachment)"
            }
        }
    }
    try
    {
        $smtpcient.Send($message)
    }
    catch 
    {
        if ($error) 
        {
            $error[0].exception.tostring()
        }
        else 
        {
            "Exception calling System.Net.Mail.MailMessage send" 
        }
    }
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
}
