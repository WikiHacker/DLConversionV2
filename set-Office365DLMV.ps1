<#
    .SYNOPSIS

    This function sets the multi valued attributes of the DL

    .DESCRIPTION

    This function sets the multi valued attributes of the DL.
    For each of use - I've combined these into a single function instead of splitting them out.

    .OUTPUTS

    None

    .EXAMPLE

    set-Office365DLMV -originalDLConfiguration -exchangeDLMembership -exchangeRejectMessage -exchangeAcceptMessage -exchangeManagedBy -exchangeModeratedBy -exchangeBypassMOderation -exchangeGrantSendOnBehalfTo.


    #>
    Function set-Office365DLMV
     {
        [cmdletbinding()]

        Param
        (
            [Parameter(Mandatory = $true)]
            $originalDLConfiguration,
            [Parameter(Mandatory = $true)]
            $office365DLConfiguration,
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [array]$exchangeDLMembershipSMTP=$NULL,
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [array]$exchangeRejectMessagesSMTP=$NULL,
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [array]$exchangeAcceptMessageSMTP=$NULL,
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [array]$exchangeManagedBySMTP=$NULL,
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [array]$exchangeModeratedBySMTP=$NULL,
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [array]$exchangeBypassModerationSMTP=$NULL,
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [array]$exchangeGrantSendOnBehalfToSMTP=$NULL,
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [array]$exchangeSendAsSMTP=$NULL,
            [Parameter(Mandatory=$true)]
            [string]$groupTypeOverride,
            [Parameter(Mandatory=$true)]
            $office365DLConfigurationPostMigration,
            [Parameter(Mandatory=$TRUE)]
            $mailOnMicrosoftComDomain,
            [Parameter(Mandatory=$TRUE)]
            $allowNonSyncedGroup=$FALSE,
            [Parameter(Mandatory=$TRUE)]
            $allOffice365SendAsAccessOnGroup=$NULL
        )

        #Output all parameters bound or unbound and their associated values.

        write-functionParameters -keyArray $MyInvocation.MyCommand.Parameters.Keys -parameterArray $PSBoundParameters -variableArray (Get-Variable -Scope Local -ErrorAction Ignore)

        #Declare function variables.

        [array]$functionDirectoryObjectID = $NULL
        $functionEmailAddress = $NULL
        [boolean]$routingAddressIsPresent=$FALSE
        [string]$hybridRemoteRoutingAddress=$NULL
        [int]$functionLoopCounter=0
        [boolean]$functionFirstRun=$TRUE
        [array]$functionRecipients=@()
        [array]$functionEmailAddresses=@()
        [string]$functionMail=""
        [string]$functionMailNickname=""
        [string]$functionExternalDirectoryObjectID = ""
        [string]$functionEmailAddressToRemove = ""

        [boolean]$isTestError=$false
        [array]$functionErrors=@()

        #Start function processing.

        Out-LogFile -string "********************************************************************************"
        Out-LogFile -string "BEGIN SET-Office365DLMV"
        Out-LogFile -string "********************************************************************************"

        out-logfile -string "Resetting all SMTP addresses on the object to match on premises."

        foreach ($address in $originalDLConfiguration.proxyAddresses)
        {
            if ($address.contains("mail.onmicrosoft.com"))
            {
                out-logfile -string ("Hybrid remote routing address found.")
                out-logfile -string $address
                $routingAddressIsPresent=$TRUE
            }

            out-logfile -string $address
            $functionEmailAddresses+=$address.tostring()
        }

        foreach ($address in $office365DLConfiguration.emailAddresses)
        {
            if ($address.contains("mail.onmicrosoft.com"))
            {
                out-logfile -string ("Hybrid remote routing address found.")
                out-logfile -string $address
                $routingAddressIsPresent=$TRUE
            }

            out-logfile -string $address
            $functionEmailAddresses+=$address.tostring()
        }

        $functionEmailAddresses = $functionEmailAddresses | select-object -unique

        out-logfile -string $functionEmailAddresses

        $functionExternalDirectoryObjectID = $office365DLConfigurationPostMigration.externalDirectoryObjectID
        
        out-logfile -string "External directory object ID utilized for set commands:"
        out-logfile -string $functionExternalDirectoryObjectID

        $functionEmailAddressToRemove = $office365DLConfigurationPostMigration.primarySMTPAddress

        out-logfile -string "Email address to remove after resetting attributes."
        out-logfile -string $functionEmailAddressToRemove

        if ($originalDLConfiguration.mailNickName -ne $NULL)
        {
            out-logfile -string "Mail nickname present on premsies -> using this value."
            $functionMailNickName = $originalDLConfiguration.mailNickName
            out-logfile -string $functionMailNickName
        }
        else 
        {
            out-logfile -string "Mail nickname not present on premises -> using Office 365 value."
            $functionMailNickName = $office365DLConfiguration.alias
            out-logfile -string $functionMailNickName
        }

        #With the new temp DL logic - the fast deletion and then immediately moving into set operations sometimes caused cache collisions.
        #This caused the following bulk logic to fail - then the individual set logics would also fail.
        #This left us with the temp DL without any actual SMTP addresses.
        #New logic - try / sleep 10 times then try the individuals.

        $maxRetries = 0

        Do
        {
            try {
                $isTestError=$FALSE

                out-logfile -string ("Max retry attempt: "+$maxRetries.toString())

                Set-O365DistributionGroup -identity $functionExternalDirectoryObjectID -emailAddresses $functionEmailAddresses -errorAction STOP -BypassSecurityGroupManagerCheck

                $maxRetries = 10 #The previous set was successful - so immediately bail.
            }
            catch {
                out-logfile -string "Error bulk updating email addresses on distribution group."
                out-logfile -string $_
                $isTestError=$TRUE
                out-logfile -string "Starting 10 second sleep before trying bulk update."
                start-sleep -s 10
                $maxRetries = $maxRetries+1
            }
        }
        while($maxRetries -lt 10)
        
        if ($isTestError -eq $TRUE)
        {
            out-logfile -string "Attempting SMTP address updates per address."

            out-logfile -string "Establishing group primary SMTP Address."

            try {
                set-o365DistributionGroup -identity $functionExternalDirectoryObjectID -primarySMTPAddress $originalDLConfiguration.mail -errorAction STOP
            }
            catch {
                out-logfile -string "Error establishing new group primary SMTP Address."

                out-logfile -string $_
                
                $isErrorObject = new-Object psObject -property @{
                    PrimarySMTPAddressorUPN = $originalDLConfiguration.mail
                    ExternalDirectoryObjectID = $originalDLConfiguration.'msDS-ExternalDirectoryObjectId'
                    Alias = $functionMailNickName
                    Name = $originalDLConfiguration.name
                    Attribute = "Cloud Proxy Addresses"
                    ErrorMessage = ("Unable to set cloud distribution group primary SMTP address to match on-premsies mail address.")
                    ErrorMessageDetail = $_
                }

                out-logfile -string $isErrorObject

                $functionErrors+=$isErrorObject
            }

            foreach ($address in $functionEmailAddresses)
            {
                out-logfile -string ("Processing address: "+$address)

                try{
                    Set-O365DistributionGroup -identity $functionExternalDirectoryObjectID -emailAddresses @{add=$address} -errorAction STOP -BypassSecurityGroupManagerCheck
                }
                catch{
                    out-logfile -string ("Error processing address: "+$address)

                    out-logfile -string $_

                    $isErrorObject = new-Object psObject -property @{
                        PrimarySMTPAddressorUPN = $originalDLConfiguration.mail
                        ExternalDirectoryObjectID = $originalDLConfiguration.'msDS-ExternalDirectoryObjectId'
                        Alias = $functionMailNickName
                        Name = $originalDLConfiguration.name
                        Attribute = "Cloud Proxy Addresses"
                        ErrorMessage = ("Address "+$address+" could not be added to new cloud distribution group.  Manual addition required.")
                        ErrorMessageDetail = $_
                    }

                    out-logfile -string $isErrorObject

                    $functionErrors+=$isErrorObject
                }
            }
        }
        
        #Operation set complete - reset isError.

        $isTestError=$FALSE

        if ($originalDLConfiguration.legacyExchangeDN -ne $NULL)
        {
            out-logfile -string "Processing on premises legacy ExchangeDN to X500"
            out-logfile -string $originalDLConfiguration.legacyExchangeDN

            $functionEmailAddress = "X500:"+$originalDLConfiguration.legacyExchangeDN

            out-logfile -string ("The x500 address to process = "+$functionEmailAddress)

            try {
                Set-O365DistributionGroup -identity $functionExternalDirectoryObjectID -emailAddresses @{add=$functionEmailAddress} -errorAction STOP -BypassSecurityGroupManagerCheck
            }
            catch {
                out-logfile -string ("Error processing address: "+$functionEmailAddress)

                out-logfile -string $_

                $isErrorObject = new-Object psObject -property @{
                    PrimarySMTPAddressorUPN = $originalDLConfiguration.mail
                    ExternalDirectoryObjectID = $originalDLConfiguration.'msDS-ExternalDirectoryObjectId'
                    Alias = $functionMailNickName
                    Name = $originalDLConfiguration.name
                    Attribute = "Cloud Proxy Addresses"
                    ErrorMessage = ("Address "+$functionEmailAddress+" could not be added to new cloud distribution group.  Manual addition required.")
                    ErrorMessageDetail = $_
                }

                out-logfile -string $isErrorObject

                $functionErrors+=$isErrorObject
            }
        }

        if ($allowNonSyncedGroup -eq $FALSE)
        {
            out-logfile -string "Processing original cloud legacy ExchangeDN to X500"
            out-logfile -string $office365DLConfiguration.legacyExchangeDN

            $functionEmailAddress = "X500:"+$office365DLConfiguration.legacyExchangeDN

            out-logfile -string ("The x500 address to process = "+$functionEmailAddress)

            try {
                Set-O365DistributionGroup -identity $functionExternalDirectoryObjectID -emailAddresses @{add=$functionEmailAddress} -errorAction STOP -BypassSecurityGroupManagerCheck
            }
            catch {
                out-logfile -string ("Error processing address: "+$functionEmailAddress)

                out-logfile -string $_

                $isErrorObject = new-Object psObject -property @{
                    PrimarySMTPAddressorUPN = $originalDLConfiguration.mail
                    ExternalDirectoryObjectID = $originalDLConfiguration.'msDS-ExternalDirectoryObjectId'
                    Alias = $functionMailNickName
                    Name = $originalDLConfiguration.name
                    Attribute = "Cloud Proxy Addresses"
                    ErrorMessage = ("Address "+$functionEmailAddress+" could not be added to new cloud distribution group.  Manual addition required.")
                    ErrorMessageDetail = $_
                }

                out-logfile -string $isErrorObject

                $functionErrors+=$isErrorObject
            }
        }

        if ($routingAddressIsPresent -eq $FALSE)
        {
            out-logfile -string "A hybrid remote routing address was not present.  Adding hybrid remote routing address."
            $hybridRemoteRoutingAddress=$functionMailNickName+"@"+$mailOnMicrosoftComDomain

            out-logfile -string ("Calculated hybrid remote routing address = "+$hybridRemoteRoutingAddress)

            out-logfile -string ("Determine if the calcualted routing address is already in use.")

            $hybridDoLoop = $FALSE

            do
            {
                if (get-o365Recipient -identity $hybridRemoteRoutingAddress)
                {
                    out-logfile -string "Calculated hybrid remote routing address found on another mail enabled object."
                    $hybridDoLoop = $FALSE
                    $hybridDoRandom = (Get-Random).toString()  
                    $hybridRemoteRoutingAddress=$functionMailNickName+$hybridDoRandom+"@"+$mailOnMicrosoftComDomain
                    out-logfile -string ("Calculated remote routing address with random number: "+$hybridRemoteRoutingAddress)
                }
                else 
                {
                    out-logfile -string "Calculated hybrid remote routing address is not present - continue."
                    $hybridDoLoop = $TRUE   
                }
            }until ($hybridDoLoop -eq $TRUE)

            try {
                Set-O365DistributionGroup -identity $functionExternalDirectoryObjectID -emailAddresses @{add=$hybridRemoteRoutingAddress} -errorAction STOP -BypassSecurityGroupManagerCheck
            }
            catch {
                out-logfile -string ("Error processing address: "+$hybridRemoteRoutingAddress)

                out-logfile -string $_

                $isErrorObject = new-Object psObject -property @{
                    PrimarySMTPAddressorUPN = $originalDLConfiguration.mail
                    ExternalDirectoryObjectID = $originalDLConfiguration.'msDS-ExternalDirectoryObjectId'
                    Alias = $functionMailNickName
                    Name = $originalDLConfiguration.name
                    Attribute = "Cloud Proxy Addresses"
                    ErrorMessage = ("Address "+$hybridRemoteRoutingAddress+" could not be added to new cloud distribution group.  Manual addition required.")
                    ErrorMessageDetail = $_
                }

                out-logfile -string $isErrorObject

                $functionErrors+=$isErrorObject
            }
        }

        $isTestError=$FALSE

        out-logFile -string "Evaluating exchangeDLMembershipSMTP"

        if ($exchangeDLMembershipSMTP -ne $NULL)
        {
            #All of the members were previously verified as present - so no member should be gone by now unless removed.
            #This adds all members as a single operation.  Errors we silently continue.

            #Ensureing all addresses in the array are unique.
            foreach ($member in $exchangeDLMembershipSMTP)
            {
                if ($member.externalDirectoryObjectID -ne $NULL)
                {
                    out-logfile -string ("Processing directory ID: "+$member.ExternalDirectoryObjectID)
                    $functionDirectoryObjectID=$member.externalDirectoryObjectID.Split("_")
                    $functionRecipients+=$functionDirectoryObjectID[1]
                }
                else 
                {
                    out-logfile -string ("Processing SMTPAddress: "+$member.primarySMTPAddressOrUPN)  
                    $functionRecipients+=$member.primarySMTPAddressOrUPN    
                }
            }

            #Becuase groups could have been mirgated and retained - this ensures that all SMTP addresses and GUIDs in the array are unique.

            $functionRecipients = $functionRecipients | select-object -Unique

            out-logfile -string "Updating membership with unique values."
            out-logfile -string $functionRecipients

            #Using update to reset the entire membership of the DL to the unique array.
            #Alberto Larrinaga for the suggestion.

            try {
                update-o365DistributionGroupMember -identity $functionExternalDirectoryObjectID -members $functionRecipients -BypassSecurityGroupManagerCheck -confirm:$FALSE -errorAction Stop
            }
            catch {
                out-logfile -string "Unable to bulk update distribution group membership."

                out-logfile -string $_

                $isTestError=$TRUE
            }
            
            if ($isTestError -eq $TRUE)
            {
                out-logfile -string "Attempting to update membership individually..."

                foreach ($recipient in $functionRecipients)
                {
                    out-logfile -string ("Attempting to add recipient: "+$recipient)


                    try {
                        add-O365DistributionGroupMember -identity $functionExternalDirectoryObjectID -member $recipient -BypassSecurityGroupManagerCheck -errorAction STOP
                    }
                    catch {
                        out-logfile -string ("Error procesing recipient: "+$recipient)

                        out-logfile -string $_

                        $isErrorObject = new-Object psObject -property @{
                            PrimarySMTPAddressorUPN = $originalDLConfiguration.mail
                            ExternalDirectoryObjectID = $originalDLConfiguration.'msDS-ExternalDirectoryObjectId'
                            Alias = $originalDLConfiguration.mailNickName
                            Name = $functionMailNickName
                            Attribute = "Cloud Distribution Group Member"
                            ErrorMessage = ("Member "+$recipient+" unable to add to cloud distribution group.  Manual addition required.")
                            ErrorMessageDetail = $_
                        }

                        out-logfile -string $isErrorObject

                        $functionErrors+=$isErrorObject
                    }
                }
            }
        }
        else 
        {
            Out-LogFile -string "There were no members to process."    
        }

        $isTestError=$FALSE #Resetting error trigger.

        $functionRecipients=@() #Reset the test array.

        out-logFile -string "Evaluating exchangeRejectMessagesSMTP"

        if ($exchangeRejectMessagesSMTP -ne $NULL)
        {
            foreach ($member in $exchangeRejectMessagesSMTP)
            {
                #Implement some protections for larger operations to ensure we do not exhaust our powershell budget.

                if ($member.externalDirectoryObjectID -ne $NULL)
                {
                    out-LogFile -string ("Processing member = "+$member.externalDirectoryObjectID)

                    $functionDirectoryObjectID=$member.externalDirectoryObjectID.Split("_")

                    out-LogFile -string ("Processing updated member = "+$functionDirectoryObjectID[1])

                    $functionRecipients+=$functionDirectoryObjectID[1]
                }
                elseif ($member.primarySMTPAddressOrUPN -ne $NULL)
                {
                    out-LogFile -string ("Processing member = "+$member.PrimarySMTPAddressOrUPN)

                    $functionRecipients+=$member.primarySMTPAddressOrUPN    
                }
                else 
                {
                    out-logfile -string "Invalid function object for recipient." -isError:$TRUE
                } 
            }

            #Becuase groups could have been mirgated and retained - this ensures that all SMTP addresses and GUIDs in the array are unique.

            $functionRecipients = $functionRecipients | select-object -Unique

            out-logfile -string "Updating reject messages SMTP with unique values."
            out-logfile -string $functionRecipients

            try {
                set-o365DistributionGroup -identity $functionExternalDirectoryObjectID -RejectMessagesFromSendersOrMembers $functionRecipients -errorAction STOP -BypassSecurityGroupManagerCheck
            }
            catch {
                out-logfile -string "Error bulk updating RejectMessagesFromSendersOrMembers"

                out-logfile -string $_

                $isTestError=$TRUE
            }

            if ($isTestError -eq $TRUE)
            {
                out-logfile -string "Attempting individual update of RejectMessagesFromSendersOrMembers"

                foreach ($recipient in $functionRecipients)
                {
                    out-logfile -string ("Attempting to add recipient: "+$recipient)

                    try {
                        set-o365DistributionGroup -identity $functionExternalDirectoryObjectID -RejectMessagesFromSendersOrMembers @{Add=$recipient} -errorAction STOP -BypassSecurityGroupManagerCheck                    }
                    catch {
                        out-logfile -string ("Error procesing recipient: "+$recipient)

                        out-logfile -string $_

                        $isErrorObject = new-Object psObject -property @{
                            PrimarySMTPAddressorUPN = $originalDLConfiguration.mail
                            ExternalDirectoryObjectID = $originalDLConfiguration.'msDS-ExternalDirectoryObjectId'
                            Alias = $functionMailNickName
                            Name = $originalDLConfiguration.name
                            Attribute = "Cloud Distribution Group RejectMessagesFromSendersOrMembers"
                            ErrorMessage = ("Member of RejectMessagesFromSendersOrMembers "+$recipient+" unable to add to cloud distribution group.  Manual addition required.")
                            ErrorMessageDetail = $_
                        }

                        out-logfile -string $isErrorObject

                        $functionErrors+=$isErrorObject
                    }
                }
            }

        }
        else 
        {
            Out-LogFile -string "There were no members to process."    
        }

        $isTestError = $FALSE #Reset error tracker.

        $functionRecipients=@() #Reset the test array.

        out-logFile -string "Evaluating exchangeAcceptMessagesSMTP"

        if ($exchangeAcceptMessageSMTP -ne $NULL)
        {
            foreach ($member in $exchangeAcceptMessageSMTP)
            {
                #Implement some protections for larger operations to ensure we do not exhaust our powershell budget.

                if ($member.externalDirectoryObjectID -ne $NULL)
                {
                    out-LogFile -string ("Processing member = "+$member.externalDirectoryObjectID)

                    $functionDirectoryObjectID=$member.externalDirectoryObjectID.Split("_")

                    out-LogFile -string ("Processing updated member = "+$functionDirectoryObjectID[1])

                    $functionRecipients+=$functionDirectoryObjectID[1]
                }
                elseif ($member.primarySMTPAddressOrUPN -ne $NULL)
                {
                    out-LogFile -string ("Processing member = "+$member.PrimarySMTPAddressOrUPN)

                    $functionRecipients+=$member.primarySMTPAddressOrUPN    
                }
                else 
                {
                    out-logfile -string "Invalid function object for recipient." -isError:$TRUE
                } 
            }

            #Becuase groups could have been mirgated and retained - this ensures that all SMTP addresses and GUIDs in the array are unique.

            $functionRecipients = $functionRecipients | select-object -Unique

            out-logfile -string "Updating accept messages SMTP with unique values."
            out-logfile -string $functionRecipients

            try {
                set-o365DistributionGroup -identity $functionExternalDirectoryObjectID -AcceptMessagesOnlyFromSendersOrMembers $functionRecipients -errorAction STOP -BypassSecurityGroupManagerCheck

            }
            catch {
                out-logfile -string "Error bulk updating AcceptMessagesOnlyFromSendersOrMembers."

                out-logfile -string $_

                $isTestError = $TRUE
            }

            if ($isTestError -eq $TRUE)
            {
                out-logfile -string "Attempting individual update of AcceptMessagesOnlyFromSendersOrMembers"

                foreach ($recipient in $functionRecipients)
                {
                    out-logfile -string ("Attempting to add recipient: "+$recipient)

                    try {
                        set-o365DistributionGroup -identity $functionExternalDirectoryObjectID -AcceptMessagesOnlyFromSendersOrMembers @{Add=$recipient} -errorAction STOP -BypassSecurityGroupManagerCheck                    }
                    catch {
                        out-logfile -string ("Error procesing recipient: "+$recipient)

                        out-logfile -string $_

                        $isErrorObject = new-Object psObject -property @{
                            PrimarySMTPAddressorUPN = $originalDLConfiguration.mail
                            ExternalDirectoryObjectID = $originalDLConfiguration.'msDS-ExternalDirectoryObjectId'
                            Alias = $functionMailNickName
                            Name = $originalDLConfiguration.name
                            Attribute = "Cloud Distribution Group AcceptMessagesOnlyFromSendersOrMembers"
                            ErrorMessage = ("Member of AcceptMessagesOnlyFromSendersOrMembers "+$recipient+" unable to add to cloud distribution group.  Manual addition required.")
                            ErrorMessageDetail = $_
                        }

                        out-logfile -string $isErrorObject

                        $functionErrors+=$isErrorObject
                    }
                }
            }
        }
        else 
        {
            Out-LogFile -string "There were no members to process."    
        }

        $isTestError = $FALSE #Reset error tracker.

        $functionRecipients=@() #Reset the test array.

        out-logFile -string "Evaluating exchangeManagedBySMTP"

        if ($exchangeManagedBySMTP -ne $NULL)
        {
            foreach ($member in $exchangeManagedBySMTP)
            {
                #Implement some protections for larger operations to ensure we do not exhaust our powershell budget.

                if ($member.externalDirectoryObjectID -ne $NULL)
                {
                    out-LogFile -string ("Processing member = "+$member.externalDirectoryObjectID)

                    $functionDirectoryObjectID=$member.externalDirectoryObjectID.Split("_")

                    out-LogFile -string ("Processing updated member = "+$functionDirectoryObjectID[1])

                    $functionRecipients+=$functionDirectoryObjectID[1]
                }
                elseif ($member.primarySMTPAddressOrUPN -ne $NULL)
                {
                    out-LogFile -string ("Processing member = "+$member.PrimarySMTPAddressOrUPN)

                    $functionRecipients+=$member.primarySMTPAddressOrUPN    
                }
                else 
                {
                    out-logfile -string "Invalid function object for recipient." -isError:$TRUE
                } 
            }

            #Becuase groups could have been mirgated and retained - this ensures that all SMTP addresses and GUIDs in the array are unique.

            $functionRecipients = $functionRecipients | select-object -Unique

            out-logfile -string "Updating managed by SMTP with unique values."
            out-logfile -string $functionRecipients

            try {
                set-o365DistributionGroup -identity $functionExternalDirectoryObjectID -managedBy $functionRecipients -errorAction STOP -BypassSecurityGroupManagerCheck
            }
            catch {
                out-logfile -string "Unable to bulk update managedBy"

                out-logfile $_

                $isTestError=$TRUE
            }

            if ($isTestError -eq $TRUE)
            {
                out-logfile -string "Attempting individual update of ManagedBy"

                foreach ($recipient in $functionRecipients)
                {
                    out-logfile -string ("Attempting to add recipient: "+$recipient)

                    try {
                        set-o365DistributionGroup -identity $functionExternalDirectoryObjectID -managedBy @{Add=$recipient} -errorAction STOP -BypassSecurityGroupManagerCheck                    }
                    catch {
                        out-logfile -string ("Error procesing recipient: "+$recipient)

                        out-logfile -string $_

                        $isErrorObject = new-Object psObject -property @{
                            PrimarySMTPAddressorUPN = $originalDLConfiguration.mail
                            ExternalDirectoryObjectID = $originalDLConfiguration.'msDS-ExternalDirectoryObjectId'
                            Alias = $functionMailNickName
                            Name = $originalDLConfiguration.name
                            Attribute = "Cloud Distribution Group ManagedBy"
                            ErrorMessage = ("Member of ManagedBy "+$recipient+" unable to add to cloud distribution group.  Manual addition required.")
                            ErrorMessageDetail = $_
                        }

                        out-logfile -string $isErrorObject

                        $functionErrors+=$isErrorObject
                    }
                }
            }
        }
        else 
        {
            Out-LogFile -string "There were no members to process."    
        }

        $isTestError = $FALSE #Reset error tracker.

        $functionRecipients=@() #Reset the test array.

        out-logFile -string "Evaluating exchangeModeratedBy"

        if ($exchangeModeratedBySMTP -ne $NULL)
        {
            foreach ($member in $exchangeModeratedBySMTP)
            {
                #Implement some protections for larger operations to ensure we do not exhaust our powershell budget.

                if ($member.externalDirectoryObjectID -ne $NULL)
                {
                    out-LogFile -string ("Processing member = "+$member.externalDirectoryObjectID)

                    $functionDirectoryObjectID=$member.externalDirectoryObjectID.Split("_")

                    out-LogFile -string ("Processing updated member = "+$functionDirectoryObjectID[1])

                    $functionRecipients+=$functionDirectoryObjectID[1]
                }
                elseif ($member.primarySMTPAddressOrUPN -ne $NULL)
                {
                    out-LogFile -string ("Processing member = "+$member.PrimarySMTPAddressOrUPN)

                    $functionRecipients+=$member.primarySMTPAddressOrUPN    
                }
                else 
                {
                    out-logfile -string "Invalid function object for recipient." -isError:$TRUE
                } 
            }

            #Becuase groups could have been mirgated and retained - this ensures that all SMTP addresses and GUIDs in the array are unique.

            $functionRecipients = $functionRecipients | select-object -Unique

            out-logfile -string "Updating moderated by SMTP with unique values."
            out-logfile -string $functionRecipients

            try {
                set-o365DistributionGroup -identity $functionExternalDirectoryObjectID -moderatedBy $functionRecipients -errorAction STOP -BypassSecurityGroupManagerCheck
            }
            catch {
                out-logfile -string "Unable to bulk update moderatedBy."

                out-logfile -string $_

                $isTestError=$TRUE
            }

            if ($isTestError -eq $TRUE)
            {
                out-logfile -string "Attempting individual update of ModeratedBy"

                foreach ($recipient in $functionRecipients)
                {
                    out-logfile -string ("Attempting to add recipient: "+$recipient)

                    try {
                        set-o365DistributionGroup -identity $functionExternalDirectoryObjectID -moderatedBy @{Add=$recipient} -errorAction STOP -BypassSecurityGroupManagerCheck                    }
                    catch {
                        out-logfile -string ("Error procesing recipient: "+$recipient)

                        out-logfile -string $_

                        $isErrorObject = new-Object psObject -property @{
                            PrimarySMTPAddressorUPN = $originalDLConfiguration.mail
                            ExternalDirectoryObjectID = $originalDLConfiguration.'msDS-ExternalDirectoryObjectId'
                            Alias = $functionMailNickName
                            Name = $originalDLConfiguration.name
                            Attribute = "Cloud Distribution Group ModeratedBy"
                            ErrorMessage = ("Member of ModeratedBy "+$recipient+" unable to add to cloud distribution group.  Manual addition required.")
                            ErrorMessageDetail = $_
                        }

                        out-logfile -string $isErrorObject

                        $functionErrors+=$isErrorObject
                    }
                }
            }
        }
        else 
        {
            Out-LogFile -string "There were no members to process."    
        }

        $isTestError=$FALSE

        $functionRecipients=@() #Reset the test array.

        out-logFile -string "Evaluating exchangeBypassModerationSMTP"

        if ($exchangeBypassModerationSMTP -ne $NULL)
        {
            foreach ($member in $exchangeBypassModerationSMTP)
            {
                #Implement some protections for larger operations to ensure we do not exhaust our powershell budget.

                if ($member.externalDirectoryObjectID -ne $NULL)
                {
                    out-LogFile -string ("Processing member = "+$member.externalDirectoryObjectID)

                    $functionDirectoryObjectID=$member.externalDirectoryObjectID.Split("_")

                    out-LogFile -string ("Processing updated member = "+$functionDirectoryObjectID[1])

                    $functionRecipients+=$functionDirectoryObjectID[1]
                }
                elseif ($member.primarySMTPAddressOrUPN -ne $NULL)
                {
                    out-LogFile -string ("Processing member = "+$member.PrimarySMTPAddressOrUPN)

                    $functionRecipients+=$member.primarySMTPAddressOrUPN    
                }
                else 
                {
                    out-logfile -string "Invalid function object for recipient." -isError:$TRUE
                } 
            }

            #Becuase groups could have been mirgated and retained - this ensures that all SMTP addresses and GUIDs in the array are unique.

            $functionRecipients = $functionRecipients | select-object -Unique

            out-logfile -string "Updating bypass moderation from senders or members SMTP with unique values."
            out-logfile -string $functionRecipients

            try {
                set-o365DistributionGroup -identity $functionExternalDirectoryObjectID -BypassModerationFromSendersOrMembers $functionRecipients -errorAction STOP -BypassSecurityGroupManagerCheck
            }
            catch {
                out-logfile -string "Unable to bulk modify bypassModerationFromSendersOrMembers"

                out-logfile -string $_

                $isTestError=$TRUE
            }

            if ($isTestError -eq $TRUE)
            {
                out-logfile -string "Attempting individual update of BypassModerationFromSendersOrMembers"

                foreach ($recipient in $functionRecipients)
                {
                    out-logfile -string ("Attempting to add recipient: "+$recipient)

                    try {
                        set-o365DistributionGroup -identity $functionExternalDirectoryObjectID -BypassModerationFromSendersOrMembers @{Add=$recipient} -errorAction STOP -BypassSecurityGroupManagerCheck                    }
                    catch {
                        out-logfile -string ("Error procesing recipient: "+$recipient)

                        out-logfile -string $_

                        $isErrorObject = new-Object psObject -property @{
                            PrimarySMTPAddressorUPN = $originalDLConfiguration.mail
                            ExternalDirectoryObjectID = $originalDLConfiguration.'msDS-ExternalDirectoryObjectId'
                            Alias = $functionMailNickName
                            Name = $originalDLConfiguration.name
                            Attribute = "Cloud Distribution Group BypassModerationFromSendersOrMembers"
                            ErrorMessage = ("Member of BypassModerationFromSendersOrMembers "+$recipient+" unable to add to cloud distribution group.  Manual addition required.")
                            ErrorMessageDetail = $_
                        }

                        out-logfile -string $isErrorObject

                        $functionErrors+=$isErrorObject
                    }
                }
            }
        }
        else 
        {
            Out-LogFile -string "There were no members to process."    
        }

        $isTestError=$FALSE

        $functionRecipients=@() #Reset the test array.

        out-logFile -string "Evaluating exchangeGrantSendOnBehalfToSMTP"

        if ($exchangeGrantSendOnBehalfToSMTP -ne $NULL)
        {
            foreach ($member in $exchangeGrantSendOnBehalfToSMTP)
            {
                #Implement some protections for larger operations to ensure we do not exhaust our powershell budget.

                if ($member.externalDirectoryObjectID -ne $NULL)
                {
                    out-LogFile -string ("Processing member = "+$member.externalDirectoryObjectID)

                    $functionDirectoryObjectID=$member.externalDirectoryObjectID.Split("_")

                    out-LogFile -string ("Processing updated member = "+$functionDirectoryObjectID[1])

                    $functionRecipients+=$functionDirectoryObjectID[1]
                }
                elseif ($member.primarySMTPAddressOrUPN -ne $NULL)
                {
                    out-LogFile -string ("Processing member = "+$member.PrimarySMTPAddressOrUPN)

                    $functionRecipients+=$member.primarySMTPAddressOrUPN    
                }
                else 
                {
                    out-logfile -string "Invalid function object for recipient." -isError:$TRUE
                } 
            }

            #Becuase groups could have been mirgated and retained - this ensures that all SMTP addresses and GUIDs in the array are unique.

            $functionRecipients = $functionRecipients | select-object -Unique

            out-logfile -string "Updating grant send on behalf to SMTP with unique values."
            out-logfile -string $functionRecipients

            try {
                set-o365DistributionGroup -identity $functionExternalDirectoryObjectID -GrantSendOnBehalfTo $functionRecipients -errorAction STOP -BypassSecurityGroupManagerCheck
            }
            catch {
                out-logfile -string "Unable to bulk updated GrantSendOnBehalfTo."

                out-logfile -string $_

                $isTestError=$TRUE
            }

            if ($isTestError -eq $TRUE)
            {
                out-logfile -string "Attempting individual update of GrantSendOnBehalfTo"

                foreach ($recipient in $functionRecipients)
                {
                    out-logfile -string ("Attempting to add recipient: "+$recipient)

                    try {
                        set-o365DistributionGroup -identity $functionExternalDirectoryObjectID -GrantSendOnBehalfTo @{Add=$recipient} -errorAction STOP -BypassSecurityGroupManagerCheck                    }
                    catch {
                        out-logfile -string ("Error procesing recipient: "+$recipient)

                        out-logfile -string $_

                        $isErrorObject = new-Object psObject -property @{
                            PrimarySMTPAddressorUPN = $originalDLConfiguration.mail
                            ExternalDirectoryObjectID = $originalDLConfiguration.'msDS-ExternalDirectoryObjectId'
                            Alias = $functionMailNickName
                            Name = $originalDLConfiguration.name
                            Attribute = "Cloud Distribution Group GrantSendOnBehalfTo"
                            ErrorMessage = ("Member of GrantSendOnBehalfTo "+$recipient+" unable to add to cloud distribution group.  Manual addition required.")
                            ErrorMessageDetail = $_
                        }

                        out-logfile -string $isErrorObject

                        $functionErrors+=$isErrorObject
                    }
                }
            }
        }
        else 
        {
            Out-LogFile -string "There were no members to process."    
        }

        $isTestError=$FALSE

        out-logFile -string "Evaluating exchangeSendAsSMTP"

        if ($exchangeSendAsSMTP -ne $NULL)
        {
            foreach ($member in $exchangeSendAsSMTP)
            {
                if ($member.externalDirectoryObjectID -ne $NULL)
                {
                    out-LogFile -string ("Processing member = "+$member.externalDirectoryObjectID)

                    $functionDirectoryObjectID=$member.externalDirectoryObjectID.Split("_")

                    out-LogFile -string ("Processing updated member = "+$functionDirectoryObjectID[1])

                    try {
                        add-o365RecipientPermission -Identity $functionExternalDirectoryObjectID -Trustee $functionDirectoryObjectID[1] -AccessRights "SendAs" -confirm:$FALSE
                    }
                    catch {
                        out-logfile -string "Unable to add member. "

                        out-logfile -string $_

                        $isErrorObject = new-Object psObject -property @{
                            PrimarySMTPAddressorUPN = $member.externalDirectoryObjectID
                            ExternalDirectoryObjectID = $NULL
                            Alias = $NULL
                            Name = $NULL
                            Attribute = "Cloud Distribution Group SendAs"
                            ErrorMessage = ("Unable to add migrated distribution group with send as to "+$member.externalDirectoryObjectID+".  Manual addition required.")
                            ErrorMessageDetail = $_
                        }

                        out-logfile -string $isErrorObject

                        $functionErrors+=$isErrorObject
                    }
                }
                elseif ($member.primarySMTPAddressOrUPN -ne $NULL)
                {
                    out-LogFile -string ("Processing member = "+$member.PrimarySMTPAddressOrUPN)

                    try {
                        add-o365RecipientPermission -Identity $functionExternalDirectoryObjectID -Trustee $member.primarySMTPAddressOrUPN -AccessRights "SendAs" -confirm:$FALSE
                    }
                    catch {
                        out-logfile -string "Unable to add member. "
                        out-logfile -string $_

                        $isErrorObject = new-Object psObject -property @{
                            PrimarySMTPAddressorUPN = $member.primarySMTPAddressorUPN
                            ExternalDirectoryObjectID = $NULL
                            Alias = $NULL
                            Name = $NULL
                            Attribute = "Cloud Distribution Group SendAs"
                            ErrorMessage = ("Unable to add migrated distribution group with send as to "+$member.primarySMTPAddressOrUPN+".  Manual addition required.")
                            ErrorMessageDetail = $_
                        }

                        out-logfile -string $isErrorObject

                        $functionErrors+=$isErrorObject
                    }
                }
                else 
                {
                    out-logfile -string "Invalid function object for recipient." -isError:$TRUE
                } 
            }
        }
        else 
        {
            Out-LogFile -string "There were no members to process."    
        }

        out-logfile -string "Resetting send as directly set on the group to be migrated."

        if ($allOffice365SendAsAccessOnGroup -ne $NULL)
        {
            foreach ($member in $allOffice365SendAsAccessOnGroup)
            {
                out-logfile -string ("Processing trustee: "+$member.trustee)

                try
                {
                    add-o365RecipientPermission -identity $functionExternalDirectoryObjectID -trustee $member.trustee -accessRights $member.accessRights -confirm:$FALSE -errorAction STOP
                }
                catch
                {
                    out-logfile -string "Unable to add member. "

                    out-logfile -string $_

                    $isErrorObject = new-Object psObject -property @{
                        PrimarySMTPAddressorUPN = $member.trustee
                        ExternalDirectoryObjectID = $null
                        Alias = $functionMailNickName
                        Name = $originalDLConfiguration.name
                        Attribute = "Send As On Migrated Group"
                        ErrorMessage = ("Unable to add "+$member.trustee+" to migrated distribution group with send as rights.  Manual addition required.")
                        ErrorMessageDetail = $_
                    }

                    out-logfile -string $isErrorObject

                    $functionErrors+=$isErrorObject
                }
            }
        }

        out-logfile -string "Remove the SMTP Address added by creating the temporary DL."

        try {
            out-logfile -string ("Removing: "+$functionEmailAddressToRemove)
            Set-O365DistributionGroup -identity $functionExternalDirectoryObjectID -emailAddresses @{remove=$functionEmailAddressToRemove} -errorAction STOP -BypassSecurityGroupManagerCheck
        }
        catch {
            out-logfile -string "Unable to remove SMTP address assigned by default during group creation."
            out-logfile -string $_

            $isErrorObject = new-Object psObject -property @{
                PrimarySMTPAddressorUPN = $originalDLConfiguration.mail
                ExternalDirectoryObjectID = $originalDLConfiguration.'msDS-ExternalDirectoryObjectId'
                Alias = $functionMailNickName
                Name = $originalDLConfiguration.name
                Attribute = "Unable to remove temporary SMTP address of group."
                ErrorMessage = ("Unable to remove" +$functionEmailAddressToRemove+" - manaual removal required.")
                ErrorMessageDetail = $_
            }

            out-logfile -string $isErrorObject

            $functionErrors+=$isErrorObject
        }

        Out-LogFile -string "END SET-Office365DLMV"
        Out-LogFile -string "********************************************************************************"

        out-logfile -string ("The number of function Errors = "+$functionErrors.count)
        $global:postCreateErrors += $functionErrors
    }