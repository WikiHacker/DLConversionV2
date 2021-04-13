<#
    .SYNOPSIS

    This function uses the exchange online powershell session to gather the office 365 distribution list configuration.

    .DESCRIPTION

    This function uses the exchange online powershell session to gather the office 365 distribution list configuration.

    .PARAMETER GroupSMTPAddress

    The mail attribute of the group to search.

    .OUTPUTS

    Returns the PS object associated with the recipient from get-o365recipient

    .EXAMPLE

    Get-O365DLFullMaiboxAccess -groupSMTPAddress Address

    #>
    Function Get-O365DLFullMaiboxAccess
     {
        [cmdletbinding()]

        Param
        (
            [Parameter(Mandatory = $true)]
            [string]$groupSMTPAddress
        )

        #Declare function variables.

        [array]$functionFullMailboxAccess=@()
        $functionMailboxes=$NULL
        $functionRecipient=$NULL

        #Start function processing.

        Out-LogFile -string "********************************************************************************"
        Out-LogFile -string "BEGIN Get-O365DLFullMaiboxAccess"
        Out-LogFile -string "********************************************************************************"

        #Log the parameters and variables for the function.

        Out-LogFile -string ("GroupSMTPAddress = "+$groupSMTPAddress)

        #Get the recipient using the exchange online powershell session.

        try {
            out-logfile -string "Getting recipient..."

            $functionRecipient = get-ExoRecipient -identity $groupSMTPAddress
        }
        catch {
            out-logfile -string $_ -isError:$TRUE
        }

        #Get all of the mailboxes to test.

        try {
            out-logfile -string "Getting all Office 365 mailboxes."

            $functionMailboxes = get-exomailbox -resultsize unlimited
        }
        catch {
            out-logfile -string $_ -isError:$TRUE
        }
        
        try 
        {
            Out-LogFile -string "Using Exchange Online to locate all of the full mailbox access rights in Office 365."

            $ProgressDelta = 100/($functionMailboxes.count); $PercentComplete = 0; $MbxNumber = 0

            foreach ($mailbox in $functionMailboxes)
            {
                $MbxNumber++

                write-progress -activity "Processing Recipient" -status $mailbox.primarySMTPAddress -PercentComplete $PercentComplete

                $PercentComplete += $ProgressDelta

                $functionFullMailboxAccess+=get-exoMailboxPermission -identity $mailbox.identity | where {$_.user -eq $functionRecipient.identity}
            }
        }
        catch 
        {
            Out-LogFile -string $_ -isError:$TRUE
        }

        write-progress -completed

        Out-LogFile -string "END Get-O365DLFullMaiboxAccess"
        Out-LogFile -string "********************************************************************************"
        
        return $functionFullMailboxAccess
    }