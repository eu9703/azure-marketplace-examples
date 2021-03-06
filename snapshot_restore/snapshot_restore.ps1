<#
.Synopsis
    Deploys an Azure Storage Account and Elasticsearch cluster. 
.Description
    The Storage account is configured with the azure-repository plugin to be used for snapshot/restore for the Elasticsearch cluster.
.Example
    & .\snapshot_restore.ps1 -AdminUserName "russ" `
    -AdminPassword $(ConvertTo-SecureString -String "Password1234" -AsPlainText -Force) `
    -SecurityAdminPassword $(ConvertTo-SecureString -String "Password123" -AsPlainText -Force) `
    -SecurityReadPassword $(ConvertTo-SecureString -String "Password123" -AsPlainText -Force) `
    -SecurityKibanaPassword $(ConvertTo-SecureString -String "Password123" -AsPlainText -Force)
.Example
    & .\snapshot_restore.ps1 -ClientId "clientid" `
    -ClientSecret $(ConvertTo-SecureString -String "clientsecret" -AsPlainText -Force) `
    -TenantId "tenantid" -SubscriptionId "subscriptionid" `
    -AdminUserName "russ" -AdminPassword $(ConvertTo-SecureString -String "Password1234" -AsPlainText -Force) `
    -SecurityAdminPassword $(ConvertTo-SecureString -String "Password123" -AsPlainText -Force) `
    -SecurityReadPassword $(ConvertTo-SecureString -String "Password123" -AsPlainText -Force) `
    -SecurityKibanaPassword $(ConvertTo-SecureString -String "Password123" -AsPlainText -Force)
.Parameter ClientId
    the client id to log in with a Service Principal
.Parameter ClientSecret
    the client secret to log in with a Service Principal
.Parameter TenantId
    the tenant id to log in with a Service Principal
.Parameter SubscriptionId
    the subscription id to deploy the resources to. If the current session is not logged into the Azure account, user will
    be prompted to log in and select a SubscriptionId
.Parameter AdminUserName
    the admin username in order to log into VMs deployed in the Elasticsearch cluster
.Parameter AdminPassword
    the admin password in order to log into VMs deployed in the Elasticsearch cluster 
.Parameter SecurityAdminPassword
    the password to log into the Elasticsearch cluster through X-Pack Security with user 'es_admin' (2.x) or 'elastic' (5.x)
.Parameter SecurityReadPassword
    the password to log into the Elasticsearch cluster through X-Pack Security with user 'es_read'
.Parameter SecurityKibanaPassword
    the password to log into the Elasticsearch cluster through X-Pack Security with user 'es_kibana'
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false)]
    [string] $ClientId,

    [Parameter(Mandatory=$false)]
    [securestring] $ClientSecret,

    [Parameter(Mandatory=$false)]
    [string] $TenantId,

    [Parameter(Mandatory=$false)]
    [string] $SubscriptionId,

    [Parameter(Mandatory=$true)]
    [string] $AdminUserName,

    [Parameter(Mandatory=$true)]
    [securestring] $AdminPassword,

    [Parameter(Mandatory=$true)]
    [securestring] $SecurityAdminPassword,

    [Parameter(Mandatory=$true)]
    [securestring] $SecurityReadPassword,
  
    [Parameter(Mandatory=$true)]
    [securestring] $SecurityKibanaPassword
)
$ErrorActionPreference = "Stop"

function Write-Log($Message, $ForegroundColor) {
    if ($ForegroundColor -eq $null) {
        $ForegroundColor = "White"
    }

    Write-Host "[$(Get-Date -format 'u')] $message" -ForegroundColor $ForegroundColor
}

function Show-Custom($title, $optionValues, $optionDescriptions) {
    Write-Host $title
    Write-Host
    for($i = 0; $i -lt $optionValues.Length; $i++) {
        Write-Host "$($i+1))" $optionDescriptions[$i]
    }
    Write-Host

    while($true) {
        Write-Host "Choose an option: "
        $option = Read-Host
        $option = $option -as [int]

        if($option -ge 1 -and $option -le $optionValues.Length) {
            return $optionValues[$option-1]
        }
    }
}

function Show-Subscription() {
    # Choose subscription. If there's only one we will choose automatically
    $subs = Get-AzureRmSubscription
    $subscriptionId = ""

    if($subs.Length -eq 0) {
        Write-Error "No subscriptions bound to this account."
        return
    }

    if($subs.Length -eq 1) {
        $subscriptionId = $subs[0].SubscriptionId
    }
    else {
        $subscriptionChoices = @()
        $subscriptionValues = @()

        foreach($subscription in $subs) {
            $subscriptionChoices += "$($subscription.SubscriptionName) ($($subscription.SubscriptionId))";
            $subscriptionValues += ($subscription.SubscriptionId);
        }

        $subscriptionId = Show-Custom "Choose a subscription" $subscriptionValues $subscriptionChoices
    }

    return $subscriptionId
}

try {
    if ($ClientId -and $ClientSecret -and $TenantId -and $SubscriptionId) {
        $credential = new-object -typename System.Management.Automation.PSCredential `
                                -argumentlist $ClientId, $ClientSecret

        Add-AzureRmAccount -Credential $credential -Tenant $TenantId -ServicePrincipal -ErrorAction Stop     
    }

    Select-AzureRmSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop
}
catch {
    Write-Host "Please Login"
    Login-AzureRmAccount
    $SubscriptionId = Show-Subscription
    Select-AzureRmSubscription -SubscriptionId $SubscriptionId
}

$location = "Australia Southeast"
$storageResourceGroup = "storage-account"
$storageAccountName = "esclusterbackups"

Write-Log "Creating storage account"
New-AzureRmResourceGroup -Name $storageResourceGroup -Location $location
New-AzureRmStorageAccount -ResourceGroupName $storageResourceGroup `
    -AccountName $storageAccountName -Type "Standard_LRS" -Location $location
Write-Log "Storage account created" -ForegroundColor "green"

$storageAccountKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $storageResourceGroup `
    -Name $storageAccountName
$templateVersion = "5.1.2"
$templateUrl = "https://raw.githubusercontent.com/elastic/azure-marketplace/$templateVersion/src"
$mainTemplate = "$templateUrl/mainTemplate.json"
$resourceGroup = "repository-cluster"
$name = "elasticsearch"

$templateParameters = @{
    "artifactsBaseUrl"= $templateUrl
    "esClusterName" = $name
    "adminUsername" = $AdminUserName
    "authenticationType" = "password"
    "adminPassword" = $AdminPassword
    "securityAdminPassword" = $SecurityAdminPassword
    "securityReadPassword" = $SecurityReadPassword
    "securityKibanaPassword" = $SecurityKibanaPassword
    "azureCloudPlugin" = "Yes"
    "azureCloudStorageAccountName" = $storageAccountName
    "azureCloudStorageAccountKey" = $storageAccountKeys[0].Value   
}

Write-Log "Creating Elasticsearch cluster"
New-AzureRmResourceGroup -Name $resourceGroup -Location $location
New-AzureRmResourceGroupDeployment -Name $name -ResourceGroupName $resourceGroup `
    -TemplateUri $mainTemplate -TemplateParameterObject $templateParameters
Write-Log "Elasticsearch cluster created" -ForegroundColor "green"