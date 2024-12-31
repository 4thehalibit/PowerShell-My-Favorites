################################
#        Password Expiry       #
#         Notification         #
#         Version 1.0          #
################################

<#
The purpose of this script is to email all users that their password is about to expire
days before the password expires. It also provides instructions on changing their password
in various environments.
#>

################################
#           Variables          #
################################

# Email account to send the email from
$From = "PasswordExpiration@lselectric.com"

# Mail server to send the email from
$SMTPServer = "COMPANY-com.mail.protection.outlook.com"

# Subject of the email
$MailSubject = "Windows Password Reminder: Your password will expire soon."

# Days before expiration for specific notifications
$DaysBeforeExpiry15 = 15
$DaysBeforeExpiry7 = 7

# Log file for tracking email errors and successes
$LogFile = "C:\Scripts\PasswordExpiryLog.txt"

# Check if the log file exists and if it is older than 30 days
if (Test-Path -Path $LogFile) {
    $LogFileAge = (Get-Date) - (Get-Item -Path $LogFile).CreationTime
    if ($LogFileAge.Days -ge 30) {
        # Delete and recreate the log file if it's older than 30 days
        Remove-Item -Path $LogFile -Force
        Write-Host "Log file is older than 30 days. Recreating the log file."
        New-Item -ItemType File -Path $LogFile -Force
    }
} else {
    # Create the log file if it doesn't exist
    New-Item -ItemType File -Path $LogFile -Force
}

# Testing settings "Yes,No"
$SetupForTesting = "No"
$TestingUsername = "USERNAME" # Your username to test email. doesnt matter if pasword is expiring

# For testing, manually set DaysLeft (e.g., 15, 7, or any day within 6 to 0 to simulate daily reminders)
$TestDaysLeft = $null  # Set to desired test value or set to $null to use actual calculation

################################
# Don't modify below this line #
################################

# Import Active Directory module
Try { 
    Import-Module ActiveDirectory -ErrorAction Stop 
    Write-Host "Active Directory module imported successfully."
} Catch { 
    Write-Host "Unable to load Active Directory module, is RSAT installed?"; 
    Add-Content -Path $LogFile -Value "Failed to import Active Directory module on $(Get-Date)"
    Break 
}

# Set the maximum password age based on group policy if not supplied in parameters.
if ($maxPasswordAge -eq $null) {
    $maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge
    Write-Host "Max password age set to $maxPasswordAge days."
} Else {
    Write-Host "Max password age manually set to $maxPasswordAge days."
}

# Retrieve user information for either testing or production
If ($SetupForTesting -eq "Yes") {
    Try {
        $CommandToGetInfoFromAD = Get-ADUser -Identity $TestingUsername -Properties PasswordLastSet, PasswordExpired, PasswordNeverExpires, EmailAddress, GivenName -ErrorAction Stop
        Write-Host "Testing mode: Retrieved user $TestingUsername."
    } Catch {
        Write-Host "User $TestingUsername does not exist in Active Directory."
        Add-Content -Path $LogFile -Value "User $TestingUsername does not exist in Active Directory on $(Get-Date)"
        Break  # Exit script if test user does not exist
    }
} Else {
    Try {
        $CommandToGetInfoFromAD = Get-ADUser -Filter * -Properties PasswordLastSet, PasswordExpired, PasswordNeverExpires, EmailAddress, GivenName
        Write-Host "Production mode: Retrieved all users from Active Directory."
    } Catch {
        Write-Host "Failed to retrieve users from Active Directory."
        Add-Content -Path $LogFile -Value "Failed to retrieve users from Active Directory on $(Get-Date)"
        Break
    }
}

# Verify that CommandToGetInfoFromAD contains results before proceeding
if ($CommandToGetInfoFromAD -ne $null) {
    Write-Host "Starting user loop..."
    # Loop through each user and calculate days until password expiry
    $CommandToGetInfoFromAD | ForEach {
        $Today = (Get-Date)
        $UserName = $_.GivenName
        if (!$_.PasswordExpired -and !$_.PasswordNeverExpires) {
            $ExpiryDate = ($_.PasswordLastSet + $maxPasswordAge)
            $ExpiryDateForEmail = $ExpiryDate.ToString("dddd, MMMM dd yyyy 'at' hh:mm tt")
            $DaysLeft = ($ExpiryDate - $Today).Days
            
            # Override DaysLeft for testing purposes
            if ($TestDaysLeft -ne $null) {
                $DaysLeft = $TestDaysLeft
                Write-Host "Testing mode: Overriding DaysLeft to $DaysLeft days."
            }

            Write-Host "$UserName has $DaysLeft days left before password expiration."

            # Set high priority if days left is between 6-1
            $Priority = if ($DaysLeft -le 6 -and $DaysLeft -gt 0) { "High" } else { "Normal" }

            # Send notifications based on specific days left until expiration
            if ($DaysLeft -eq $DaysBeforeExpiry15 -or $DaysLeft -eq $DaysBeforeExpiry7 -or ($DaysLeft -le 6 -and $DaysLeft -ge 0)) {
                $MailProperties = @{
                    From = $From
                    To = $_.EmailAddress
                    Subject = $MailSubject
                    SMTPServer = $SMTPServer
                    Priority = $Priority  # Sets email priority based on days left
                }

    # Customize email message based on DaysLeft
    if ($DaysLeft -eq $DaysBeforeExpiry15) {
        $MsgBody = "<p>$UserName,</p><p>Your Windows password will expire in <span style='font-weight: bold; color: #DAA520;'>15 days</span>, on $ExpiryDateForEmail. Please change it <span style='color: red; font-weight: bold;'>before expiration</span> to prevent access issues.</p>"
    } elseif ($DaysLeft -eq $DaysBeforeExpiry7) {
        $MsgBody = "<p>$UserName,</p><p>Your Windows password will expire in <span style='font-weight: bold; color: #FFA500;'>7 days</span>. The system is still waiting for you to change your password to ensure uninterrupted access.</p>"
    } elseif ($DaysLeft -eq 0) {
        $MsgBody = "<p>$UserName,</p><p><span style='font-weight: bold; color: red;'>Critical:</span> Your Windows password <span style='color: red; font-weight: bold;'>expires within 24 hours</span>. You need to change it <span style='color: red; font-weight: bold;'>immediately</span> to avoid loss of access.</p>"
    } elseif ($DaysLeft -le 6 -and $DaysLeft -gt 0) {
        $MsgBody = "<p>$UserName,</p><p><span style='font-weight: bold; color: red;'>Urgent Reminder:</span> Your Windows password expires in <span style='font-weight: bold; color: red;'>$DaysLeft day(s)</span>, on $ExpiryDateForEmail. Please update it immediately.</p>"
    }

                # Additional instructions common to all notifications
                $MsgBody += @"
<p><strong>To change your password in SharePoint, please follow these steps:</strong></p>
<ol>
    <li>Click your profile picture (or initials) in the top right corner of the SharePoint page.</li>
    <li>In the dropdown menu, select "View Account" or "My Account".</li>
    <li>On the account settings page, look for "Password" or "Change Password" (usually in the Security or Settings section).</li>
    <li>Enter your current password and the new password you'd like to use.</li>
    <li>Confirm the new password and click "Submit" or "Save" to finalize the change.</li>
</ol>

<p><strong>To clear your VPN credentials, follow these steps:</strong></p>
<ol>
    <li>Open Settings by pressing Win + I.</li>
    <li>Go to Network & Internet and select VPN from the options.</li>
    <li>Find the VPN connection you want to update and click on it.</li>
    <li>Select Advanced options.</li>
    <li>Under Clear sign-in info, click Clear to remove the saved credentials.</li>
</ol>

<p>After clearing, you will need to re-enter your username and password the next time you connect to the VPN.</p>
<p><strong>Important Note:</strong> Please allow time for your new password to sync across all systems. You will need to sign in to each software application again as they update with your new password. Additionally, if you are working remote your computer password will sync once you connect to the VPN using your new credentials.</p>

<p><em>You can also find these instructions by going to</em> <strong>SharePoint</strong> <em>and navigating to</em> <strong>IT and Systems</strong>. <em>Search for</em> "<strong>VPN</strong>" <em>or</em> "<strong>Password</strong>" <em>to access video instructions on password changes and clearing VPN credentials.</em></p>

<p>Thank you,<br>
IT Department<br>
715-241-3293<br><a href="mailto:support@lselectric.com">support@lselectric.com</a></p>
"@

                ### Try to send email to user with the message in $MsgBody variable and the supplied @MailProperties.
                Try {
                    Write-Host "Attempting to send email to $UserName at $($_.EmailAddress)."
                    Send-MailMessage @MailProperties -Body $MsgBody -BodyAsHtml
                    $SuccessMessage = "Successfully sent email to $UserName at $($_.EmailAddress) on $(Get-Date)"
                    Add-Content -Path $LogFile -Value $SuccessMessage
                } Catch {
                    Write-Host "Failed to send email to $UserName at $($_.EmailAddress)"
                    $ErrorMessage = "Failed to send email to $UserName at $($_.EmailAddress) on $(Get-Date): $($_.Exception.Message)"
                    Add-Content -Path $LogFile -Value $ErrorMessage
                }
            }
        } Else {
            Write-Host "$UserName's password does not expire or has already expired."
        }
    }
    Write-Host "User loop complete."
} Else {
    Write-Host "No users found or failed to retrieve users."
}
