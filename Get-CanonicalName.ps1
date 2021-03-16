<#
    .SYNOPSIS

    This function returns the canonicalName associated with a distinguished name.
    
    .DESCRIPTION

    This function returns the canonicalName associated with a distinguished name.

    .PARAMETER GlobalCatalog

    The global catalog to make the query against.

    .PARAMETER DN

    The DN of the object to pass to normalize.

    .OUTPUTS

    The canonical name of a given object.

    .EXAMPLE

    get-canonicalName -globalCatalog GC -DN DN

    #>
    Function get-canonicalName
     {
        [cmdletbinding()]

        Param
        (
            [Parameter(Mandatory = $true)]
            [string]$globalCatalogServer,
            [Parameter(Mandatory = $true)]
            [string]$DN
        )

        #Declare function variables.

        $functionTest=$NULL #Holds the return information for the group query.
        $functionObject=$NULL #This is used to hold the object that will be returned.
        [string]$functionSMTPAddress=$NULL
        [string]$globalCatalogServer=$globalCatalogServer+":3268"

        #Start function processing.

        Out-LogFile -string "********************************************************************************"
        Out-LogFile -string "BEGIN GET-NormalizedDN"
        Out-LogFile -string "********************************************************************************"

        #Log the parameters and variables for the function.

        Out-LogFile -string ("GlobalCatalogServer = "+$globalCatalogServer)
        OUt-LogFile -string ("DN Set = "+$DN)
        
        #Get the specific user using ad providers.
        
        try 
        {
            Out-LogFile -string "Attempting to find the AD object associated with the member."

            $functionTest = get-adObject -filter {distinguishedname -eq $dn} -properties * -errorAction STOP

            if ($functionTest -eq $NULL)
            {
                throw "The array member cannot be found by DN in Active Directory."
            }

            Out-LogFile -string "The array member was found by DN."
        }
        catch 
        {
            Out-LogFile -string $_ -isError:$TRUE
        }

        try
        {
            #In this iteraction of the script were changing how we track recipients - since we're using adsi.
            #First step check to see if the object has a recipient display type - that means it's mail enabled.
            #If the object is mail enabled - regardless of object type - look to see if the previous migration was done (group to contact conversion.)
            #If the group was not migrated or is not a group - take those attributes.
            #The next case is that we do allow contacts to have a mail attribute but not be a full recipient.  (The only wayt to get them into the group is to use ADUC to do it - but it happens.)
            #If the object has MAIL and is a CONTACT record information we can.  It can be migrated.
            #Otherwise we've found non-mail present object (user with mail attribute / bad user / bad group - end.)

            #Check to see if the recipient has a recipient display type.

            if ($functionTest.msExchRecipientDisplayType -ne $NULL)
            {
                #Check to see if the object has been migrated.

                if ($functionTest.extensionAttribute1 -eq "MigratedByScript")
                {
                    Out-LogFile -string "The object was previously migrated - using migrated information."

                    $functionObject = New-Object PSObject -Property @{
                        Alias = $functionTest.mailNickName
                        Name = $functionTest.Name
                        PrimarySMTPAddressOrUPN = $functionTest.extensionAttribute2
                        GUID = $NULL
                        RecipientType = $functionTest.objectClass
                        RecipientOrUser = "Recipient"
                        ExternalDirectoryObjectID = $functionTest.'msDS-ExternalDirectoryObjectId'
                        isAlreadyMigrated = $true
                    }
                }

                #If the group has not been migrated - take the attributes of the group as is.

                else 
                {
                    Out-LogFile -string "The object was not previously migrated - using directory information."
                    
                    $functionObject = New-Object PSObject -Property @{
                        Alias = $functionTest.mailNickName
                        Name = $functionTest.Name
                        PrimarySMTPAddressOrUPN = $functionTest.mail
                        GUID = $NULL
                        RecipientType = $functionTest.objectClass
                        RecipientOrUser = "Recipient"
                        ExternalDirectoryObjectID = $functionTest.'msDS-ExternalDirectoryObjectId'
                        isAlreadyMigrated = $false
                    }
                }
            }

            #The contact can be created with only an email address and be in sync scope.  It could be added to a group and will appear as a mail contact in the service.
            #If we find the user with a non-null email, no exchange type, and type contact - we'll normalize it and include it.

            elseif (($functiontest.mail -ne $NULL) -and ($functiontest.msExchRecipientDisplayType -eq $NULL) -and ($functionTest.objectClass -eq "Contact"))
            {
                Out-LogFile -string "The object is a contact with a mail attribute - but is not fully exchange enabled."
                    
                    $functionObject = New-Object PSObject -Property @{
                        Alias = $NULL
                        Name = $functionTest.Name
                        PrimarySMTPAddressOrUPN = $functionTest.mail
                        GUID = $NULL
                        RecipientType = $functionTest.objectClass
                        RecipientOrUser = "Recipient"
                        ExternalDirectoryObjectID = $functionTest.'msDS-ExternalDirectoryObjectId'
                        isAlreadyMigrated = $false
                    }
            }

            #At this point we have users that could be added to managedBy or members that are not mail enabled.  This is permissable through ADUC tools and supported with Exchange commands.

            elseif ($functionTest.objectClass -eq "User")
            {
                Out-LogFile -string "The object is a user only object hopefully in managedBY or USERS."
                    
                    $functionObject = New-Object PSObject -Property @{
                        Alias = $NULL
                        Name = $functionRecipient.Name
                        PrimarySMTPAddressOrUPN = $functionUser.UserprincipalName
                        GUID = $NULL
                        RecipientType = "User"
                        RecipientOrUser = "User"
                }
            }

            #Object is not a user, contact with mail, or other mail enabled contact so bail.

            else 
            {
                 throw "The following object "+$dn+" is not mail enabled and must be removed or mail enabled to continue."
            }
        }
        catch
        {
            Out-LogFile -string $_ -isError:$true  
        }

        Out-LogFile -string "END GET-NormalizedDN"
        Out-LogFile -string "********************************************************************************"
        
        #This function is designed to open local and remote powershell sessions.
        #If the session requires import - for example exchange - return the session for later work.
        #If not no return is required.
        
        return $functionObject
    }