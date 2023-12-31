# AWS Single Account SSO Deployment script

# NOTES:
#   This is the AWS Single account guide document
#      https://learn.microsoft.com/en-us/azure/active-directory/saas-apps/amazon-web-service-tutorial
#   API References:
#      https://learn.microsoft.com/en-us/graph/application-saml-sso-configure-api?tabs=http%2Cpowershell-script
#      https://learn.microsoft.com/en-us/graph/api/resources/serviceprincipal?view=graph-rest-1.0


# New Application Details
# Environment variables can also be used by setting
# the below values to $ENV:VARIABLE_NAME, ex $ENV:sync_secret_token

    # Specify values directly to the script
    # $display_name        = "AWS Single Account - App 1"                    # Name of the App/Service principal
    # $sync_client_secret  = "<client-secret>"                               # Obtain this from the AWS IAM configuration ref: https://learn.microsoft.com/en-us/azure/active-directory/saas-apps/amazon-web-service-tutorial
    # $sync_secret_token   = "<secret-token>"                                # Obtain this from the AWS IAM configuration ref: https://learn.microsoft.com/en-us/azure/active-directory/saas-apps/amazon-web-service-tutorial
    # $identifier_uri      = "https://signin.aws.amazon.com/saml#1"          # For multiple apps, increment the  number after the # sign, ex #1  #2 #3 ...

    #     -- or --

    # Configurable environment variables for Devops Pipelines/Github Actions
    $display_name        = $ENV:APP_DISPLAY_NAME                 # Name of the App/Service principal
    $sync_client_secret  = $ENV:SYNC_CLIENT_SECRET               # Obtain this from the AWS IAM configuration ref: https://learn.microsoft.com/en-us/azure/active-directory/saas-apps/amazon-web-service-tutorial
    $sync_secret_token   = $ENV:SYNC_SECRET_TOKEN                # Obtain this from the AWS IAM configuration ref: https://learn.microsoft.com/en-us/azure/active-directory/saas-apps/amazon-web-service-tutorial
    $identifier_uri      = $ENV:APP_IDENTIFIER_URI               # For multiple apps, increment the  number after the # sign, ex #1  #2 #3 ...
    


    # For Devops pipelines, choose script behaviour
    #   When a duplicate app with the same is found
    #   What should the script do?
    #      StopWithError
    #      StopWithSuccess
    #      UpdateExistingApp
    #      CreateDuplicate
        
    $DuplicateFoundAction="UpdateExistingApp"


    # These variables below should remain as is for the AWS Single Account app
    $gallery_template_id = "8b1025e4-1dd2-430b-a150-2ef79cd700f5"
    $sync_template_id    = "aws"
    $redirect_uri        = "https://signin.aws.amazon.com/saml"
    

# NOTES:
#   API References:
#   https://learn.microsoft.com/en-us/graph/application-saml-sso-configure-api?tabs=http%2Cpowershell-script
#   https://learn.microsoft.com/en-us/graph/api/resources/serviceprincipal?view=graph-rest-1.0



############################################################
#    GET an access token using Azure CLI
#    This script assumes Azure CLI has been previously
#    authenticated
############################################################
function get-access-token () {
    param(
        [string]$resource
    )
    $token = $(az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv)
    return $token
}

function get-current-tenant-id () {
    param(
        [string]$resource
    )
    $tenantId = $(az account show --query tenantId -o tsv)
    return $tenantId
}

############################################################
#    Look up service principals based on Display name
############################################################

Function Get-ServicePrincipalByDisplayName () {
    param(
        [string]$display_name
    )

    $headers = @{}
    $headers.Add("Authorization","Bearer $access_token")
    $headers.Add("Content-Type","application/json")
    Try {
        $Url = "https://graph.microsoft.com/v1.0/serviceprincipals?$('$filter')=displayName eq '$display_name'"
        Write-Information "Invoking: $Url"
        $Results = Invoke-RestMethod -Method GET -Uri $Url -Headers $headers
        return $Results
    }
    catch {
        Write-error "There was an error searching for service principals"
        Write-error $_.Exception.Message
        exit 1
    }
}


############################################################
#    Look up applications based on AppId
############################################################

Function Get-ApplicationByAppId () {
    param(
        [string]$app_id
    )

    $headers = @{}
    $headers.Add("Authorization","Bearer $access_token")
    $headers.Add("Content-Type","application/json")
    Try {
        $Url = "https://graph.microsoft.com/v1.0/applications?$('$filter')=appId eq '$app_id'"
        Write-Information "Invoking: $Url"
        $Results = Invoke-RestMethod -Method GET -Uri $Url -Headers $headers
        return $Results
    }
    catch {
        Write-error "There was an error searching for applications"
        Write-error $_.Exception.Message
        exit 1
    }
}

############################################################
#    Create a new application based on a Gallery template
############################################################      

function New-ApplicationFromGallery  {
    param(
        [string]$gallery_id,
        [string]$display_name
    )
    
    $headers = @{}
    $headers.Add("Authorization","Bearer $access_token")
    $headers.Add("Content-Type","application/json")

    $Url = "https://graph.microsoft.com/v1.0/applicationTemplates/$gallery_id/instantiate"
    $Payload = @{
        id = $gallery_id
        displayName = $display_name
    } | ConvertTo-Json -Compress 

    Try {
        $Results = Invoke-RestMethod -Method POST -Uri $Url -Headers $headers -Body $Payload -ErrorAction Stop
        
    }
    catch {
        Write-error "There was an error creating the application from the gallery"
        Write-error $_.Exception.Message
        exit 1
    }
    return $Results
}

############################################################
#    Configure Provisioning for the AWS Single account app
############################################################

function Set-ApplicationProvisioning {
    param(
        [string]$service_principal_id,
        [string]$sync_client_secret,
        [string]$sync_secret_token,
        [string]$sync_template_id
    )
    
    $headers = @{}
    $headers.Add("Authorization","Bearer $access_token")
    $headers.Add("Content-Type","application/json")

    # Create a provisioning Job
    $Url = "https://graph.microsoft.com/v1.0/servicePrincipals/{$service_principal_id}/synchronization/jobs"

    # First check if a Job already exists

    $Payload=[PSCustomObject]@{
        templateId = $sync_template_id
    } | ConvertTo-Json -Compress 

    Try {
        # First check if a Job already exists
        $SyncJobs = Invoke-RestMethod -Method GET -Uri $Url -Headers $headers -ErrorAction Stop
        if ($SyncJobs.value) {
            # A job already exist, so do not create a new one
            $SyncJob = $SyncJobs.value[0]
            Write-Warning "Provisioning: A sync job already exist, skipping creation of a new one"
        } else {
                Write-Warning "Provisioning: Creating sync job"
                $SyncJob = Invoke-RestMethod -Method POST -Uri $Url -Headers $headers -Body $Payload -ErrorAction Stop
                
        }
    }
    catch {
        Write-error "There was an error creating the Sync Job"
        Write-error $_.Exception.Message
        
        exit 1
    }

    


    # Add Secrets
    $Url = "https://graph.microsoft.com/v1.0/servicePrincipals/{$service_principal_id}/synchronization/secrets"
    $Payload=[PSCustomObject]@{
    
        value=@(
            @{
                key="ClientSecret"
                value=$sync_client_secret
            },
            @{
                key="SecretToken"
                value=$sync_secret_token
            }
        )
    } | ConvertTo-Json -Compress 

    Try {
        Write-Warning "Provisioning: Setting sync job credentials"
        $addSecrets=Invoke-RestMethod -Method PUT -Uri $Url -Headers $headers -Body $Payload -ErrorAction Stop
        
    }
    catch {
        Write-error "There was an error adding secrets to the Sync Job"
        Write-error $_.Exception.Message
        exit 1
    }

    <#
    # Validate credentials
    Start-Sleep 15
    $Url="https://graph.microsoft.com/v1.0/servicePrincipals/{$service_principal_Id}/synchronization/jobs/$($SyncJob.id)/validateCredentials"
    
    $Payload=[PSCustomObject]@{
        useSavedCredentials = $true 
    } | ConvertTo-Json -Compress 

    Try {
        Write-Warning "Provisioning: Validating credentials"
        $ValidateCreds = Invoke-RestMethod -Method POST -Body $Payload -Uri $Url -Headers $headers -ErrorAction Stop
        
    }
    catch {
        Write-error "There was an error validating the credentials"
        Write-error $_.Exception.Message
        exit 1
    }
    #>

    # Start the Sync Job
    $Url = "https://graph.microsoft.com/v1.0/servicePrincipals/{$service_principal_id}/synchronization/jobs/$($SyncJob.id)/start"

    Try {
        Write-Warning "Provisioning: Starting the sync job"
        $StartJob = Invoke-RestMethod -Method POST -Uri $Url -Headers $headers -ErrorAction Stop
        
    }
    catch {
        Write-error "There was an error starting the Sync Job"
        Write-error $_.Exception.Message
        exit 1
    }

}


############################################################
#    Configure SAML SSO for the AWS Single account app
############################################################

function Set-ApplicationSamlSSO {
    param(
        [string]$service_principal_id,
        [string]$application_id,
        [string]$redirect_uri,
        [string]$identifier_uri
    )
    
    $headers = @{}
    $headers.Add("Authorization","Bearer $access_token")
    $headers.Add("Content-Type","application/json")


    # First, get service principal details
    $Url="https://graph.microsoft.com/v1.0/servicePrincipals/$service_principal_id"

    Try {
        Write-Warning "SSO setup: Getting service principal details"
        $sp_details = Invoke-RestMethod -Method GET -Uri $Url -Headers $headers -ErrorAction Stop
        
    }
    catch {
        Write-error "There was an error reading the service principal"
        Write-error $_.Exception.Message
        exit 1
    }


    # Configure Single Sign on mode
    $Url="https://graph.microsoft.com/v1.0/servicePrincipals/$service_principal_id"

    $Payload=[PSCustomObject]@{
        preferredSingleSignOnMode = "saml" 
    } | ConvertTo-Json -Compress 

    Try {
        Write-Warning "SSO setup: Setting Single Sign on mode to SAML"
        $Result = Invoke-RestMethod -Method PATCH -Uri $Url -Headers $headers -Body $Payload -ErrorAction Stop
        
    }
    catch {
        Write-error "There was an error setting the SSO mode"
        Write-error $_.Exception.Message
        exit 1
    }
    
    # Configure SAML SSO URLs  
    $Url="https://graph.microsoft.com/v1.0/applications/$application_id"

    $Payload=[PSCustomObject]@{
    web = @{
        redirectUris = @(
        $redirect_uri
        
        )
    }
    identifierUris = @(
            $identifier_uri
    )
    
    } | ConvertTo-Json -Compress 

    Try {
        Write-Warning "SSO setup: Configurating Single Sign on SAML URLs"
        
        $Result = Invoke-RestMethod -Method PATCH -Uri $Url -Headers $headers -Body $Payload -ErrorAction Stop
        
    }
    catch {
        Write-error "There was an error setting the SAML SSO settings"
        Write-error $_.Exception.Message
        exit 1
    }
 
    # Configure SAML Signing Certificate

    if ($sp_details.keyCredentials.count -le 0) {

        $Url="https://graph.microsoft.com/v1.0/servicePrincipals/$service_principal_id/addTokenSigningCertificate"
        $Payload=[PSCustomObject]@{
            displayName = "CN=AWSSSO"
            endDateTime = (Get-Date).AddYears(1).ToString("yyyy-MM-ddThh:mm:ss")    
        } | ConvertTo-Json -Compress 
    
        Try {
            Write-Warning "SSO setup: Adding a Token Signing Certificate"
            $Result = Invoke-RestMethod -Method POST -Uri $Url -Headers $headers -Body $Payload -ErrorAction Stop
        
        
        }   
        catch {
            Write-error "There was an error adding the SAML Signing Certificate"
            Write-error $_.Exception.Message
            exit 1
        }
    } else {
        write-warning "SSO Setup: Signing certs already exist, not adding a new one"
    }

    
}

#####################################################
# Main
#####################################################

# Get an access token
    Write-Warning "Getting access token"
    $access_token = get-access-token
    

# First let's check if the application already exists
    $Answer=Get-ServicePrincipalByDisplayName -display_name $display_name

    if ($Answer.value) {
        # Application already exists        
        
        
        
        Switch($DuplicateFoundAction){

            "StopWithError"     {  $service_principal_id = $Answer.value[0].id; Write-Error "Application $display_name already exists - $service_principal_id" ; exit 1  }
            "StopWithSuccess"   {  $service_principal_id = $Answer.value[0].id; Write-Host "Application $display_name already exists - $service_principal_id" ; exit 0   }
            "UpdateExistingApp" {  Write-Host "Application $display_name already exists - $service_principal_id, updating ..." ;

                                                            
                                                $service_principal_id = $Answer.value[0].id
                                                $application_appid = $Answer.value[0].appId

                                                $application_id = (Get-ApplicationByAppId -app_id $application_appid).value[0].id
                                                

                                }
            "CreateDuplicate"   {  Write-Host "Application $display_name already exists - $service_principal_id, creating duplicate anyway."}

        }

    }

    # Check if $service_principal_id is null, if so, create the application
    if ($service_principal_id -eq $null) {

        # Create the application
        Write-warning "Creating new app"
        $NewApp=New-ApplicationFromGallery -display_name $display_name -gallery_id $gallery_template_id
        $service_principal_id = $NewApp.servicePrincipal.id
        $application_appid = $NewApp.servicePrincipal.appId
        $application_id = $NewApp.application.id

        # Wait for objects to replicate
        Write-warning "Waiting 60 seconds to allow replication..."
        Start-sleep 60

    }
    
    # Configure Provisioning
    Set-ApplicationProvisioning -service_principal_id $service_principal_id -sync_client_secret $sync_client_secret -sync_secret_token $sync_secret_token -sync_template_id $sync_template_id
    
    # Set the SAML SSO settings
    Set-ApplicationSamlSSO -service_principal_id $service_principal_id -application_id $application_id -redirect_uri $redirect_uri -identifier_uri $identifier_uri


    # Provide output for devops flows
    $tenantId = get-current-tenant-id
    [PsCustomObject]@{

        AppId                 = $application_appid
        ServicePrincipalId    = $service_principal_id
        ApplicationId         = $application_id
        display_name          = $display_name
        SamlFedMetadataUrl    = "https://login.microsoftonline.com/{0}/federationmetadata/2007-06/federationmetadata.xml?appid={1}" -f $tenantId, $application_appid


    } | ConvertTo-Json




    Remove-Variable service_principal_id
    Remove-Variable sync_secret_token
    Remove-Variable sync_client_secret
  
