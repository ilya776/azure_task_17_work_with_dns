$location = "uksouth"
$resourceGroupName = "mate-resources"

$virtualNetworkName = "todoapp"
$vnetAddressPrefix = "10.20.30.0/24"
$webSubnetName = "webservers"
$webSubnetIpRange = "10.20.30.0/26"
$mngSubnetName = "management"
$mngSubnetIpRange = "10.20.30.128/26"

$sshKeyName = "linuxboxsshkey"
$sshKeyPublicKey = Get-Content "~/.ssh/id_rsa.pub"

$vmImage = "Ubuntu2204"
$vmSize = "Standard_B1s"
$webVmName = "webserver"
$jumpboxVmName = "jumpbox"
$dnsLabel = "matetask" + (Get-Random -Count 1)

$privateDnsZoneName = "or.nottodo"
$ArtifactsStorageAccountName = "mateartefacts"
$ArtifactsContainerName = "task-artifacts"

# -------------------------------
# Resource Group
# -------------------------------
$rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Host "Creating resource group $resourceGroupName ..."
    New-AzResourceGroup -Name $resourceGroupName -Location $location
} else {
    Write-Host "Resource group $resourceGroupName already exists, skipping."
}

# -------------------------------
# Network Security Groups
# -------------------------------
$webNsg = Get-AzNetworkSecurityGroup -Name $webSubnetName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $webNsg) {
    Write-Host "Creating web NSG..."
    $webHttpRule = New-AzNetworkSecurityRuleConfig -Name "web" -Description "Allow HTTP" `
       -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80,443
    $webNsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name $webSubnetName -SecurityRules $webHttpRule
} else {
    Write-Host "Web NSG $webSubnetName exists, skipping."
}

$mngNsg = Get-AzNetworkSecurityGroup -Name $mngSubnetName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $mngNsg) {
    Write-Host "Creating management NSG..."
    $mngSshRule = New-AzNetworkSecurityRuleConfig -Name "ssh" -Description "Allow SSH" `
       -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22
    $mngNsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name $mngSubnetName -SecurityRules $mngSshRule
} else {
    Write-Host "Management NSG $mngSubnetName exists, skipping."
}

# -------------------------------
# Virtual Network
# -------------------------------
$virtualNetwork = Get-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $virtualNetwork) {
    Write-Host "Creating virtual network $virtualNetworkName ..."
    $webSubnet = New-AzVirtualNetworkSubnetConfig -Name $webSubnetName -AddressPrefix $webSubnetIpRange -NetworkSecurityGroup $webNsg
    $mngSubnet = New-AzVirtualNetworkSubnetConfig -Name $mngSubnetName -AddressPrefix $mngSubnetIpRange -NetworkSecurityGroup $mngNsg
    $virtualNetwork = New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $webSubnet,$mngSubnet
} else {
    Write-Host "Virtual network $virtualNetworkName exists, skipping."
}

# -------------------------------
# SSH Key
# -------------------------------
$sshKey = Get-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $sshKey) {
    Write-Host "Creating SSH key $sshKeyName ..."
    New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey
} else {
    Write-Host "SSH key $sshKeyName exists, skipping."
}

# -------------------------------
# Web Server VM
# -------------------------------
$webVm = Get-AzVm -Name $webVmName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $webVm) {
    Write-Host "Creating web server VM $webVmName ..."
    New-AzVm `
    -ResourceGroupName $resourceGroupName `
    -Name $webVmName `
    -Location $location `
    -Image $vmImage `
    -Size $vmSize `
    -SubnetName $webSubnetName `
    -VirtualNetworkName $virtualNetworkName `
    -SshKeyName $sshKeyName

    $Params = @{
        ResourceGroupName  = $resourceGroupName
        VMName             = $webVmName
        Name               = 'CustomScript'
        Publisher          = 'Microsoft.Azure.Extensions'
        ExtensionType      = 'CustomScript'
        TypeHandlerVersion = '2.1'
        Settings           = @{fileUris = @('https://raw.githubusercontent.com/mate-academy/azure_task_17_work_with_dns/main/install-app.sh'); commandToExecute = './install-app.sh'}
    }
    Set-AzVMExtension @Params
} else {
    Write-Host "Web server VM $webVmName exists, skipping."
}

# -------------------------------
# Public IP + Management VM
# -------------------------------
$publicIp = Get-AzPublicIpAddress -Name $jumpboxVmName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $publicIp) {
    Write-Host "Creating public IP $jumpboxVmName ..."
    New-AzPublicIpAddress -Name $jumpboxVmName -ResourceGroupName $resourceGroupName -Location $location -Sku Standard -AllocationMethod Static -DomainNameLabel $dnsLabel
} else {
    Write-Host "Public IP $jumpboxVmName exists, skipping."
}

$jumpVm = Get-AzVm -Name $jumpboxVmName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $jumpVm) {
    Write-Host "Creating management VM $jumpboxVmName ..."
    New-AzVm `
    -ResourceGroupName $resourceGroupName `
    -Name $jumpboxVmName `
    -Location $location `
    -Image $vmImage `
    -Size $vmSize `
    -SubnetName $mngSubnetName `
    -VirtualNetworkName $virtualNetworkName `
    -SshKeyName $sshKeyName `
    -PublicIpAddressName $jumpboxVmName
} else {
    Write-Host "Management VM $jumpboxVmName exists, skipping."
}

# -------------------------------
# Private DNS Zone
# -------------------------------
$dnsZone = Get-AzPrivateDnsZone -Name $privateDnsZoneName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $dnsZone) {
    Write-Host "Creating private DNS zone $privateDnsZoneName ..."
    New-AzPrivateDnsZone -Name $privateDnsZoneName -ResourceGroupName $resourceGroupName
} else {
    Write-Host "Private DNS zone $privateDnsZoneName exists, skipping."
}

$dnsLink = Get-AzPrivateDnsVirtualNetworkLink -ZoneName $privateDnsZoneName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq "todoapp-link"}
if (-not $dnsLink) {
    Write-Host "Linking private DNS zone to virtual network ..."
    New-AzPrivateDnsVirtualNetworkLink `
        -ZoneName $privateDnsZoneName `
        -ResourceGroupName $resourceGroupName `
        -Name "todoapp-link" `
        -VirtualNetworkId $virtualNetwork.Id `
        -EnableRegistration
} else {
    Write-Host "VNet link 'todoapp-link' exists, skipping."
}

$dnsRecord = Get-AzPrivateDnsRecordSet -ZoneName $privateDnsZoneName -ResourceGroupName $resourceGroupName -Name "todo" -RecordType CNAME -ErrorAction SilentlyContinue
if (-not $dnsRecord) {
    Write-Host "Creating CNAME record todo.$privateDnsZoneName ..."
    New-AzPrivateDnsRecordSet `
        -ZoneName $privateDnsZoneName `
        -ResourceGroupName $resourceGroupName `
        -Name "todo" `
        -RecordType "CNAME" `
        -Ttl 300 `
        -PrivateDnsRecords (New-AzPrivateDnsRecordConfig -Cname "$webVmName.$privateDnsZoneName")
} else {
    Write-Host "CNAME record todo.$privateDnsZoneName exists, skipping."
}

# -------------------------------
# Storage Account + Container for Artifacts
# -------------------------------
$storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $ArtifactsStorageAccountName -ErrorAction SilentlyContinue
if (-not $storageAccount) {
    Write-Host "Creating storage account $ArtifactsStorageAccountName ..."
    $storageAccount = New-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $ArtifactsStorageAccountName -Location $location -SkuName Standard_LRS -Kind StorageV2
} else {
    Write-Host "Storage account $ArtifactsStorageAccountName exists, skipping."
}

# Create container if it doesn't exist
$storageContext = $storageAccount.Context
$container = Get-AzStorageContainer -Name $ArtifactsContainerName -Context $storageContext -ErrorAction SilentlyContinue
if (-not $container) {
    Write-Host "Creating storage container $ArtifactsContainerName ..."
    New-AzStorageContainer -Name $ArtifactsContainerName -Context $storageContext -PublicAccess Off
} else {
    Write-Host "Storage container $ArtifactsContainerName exists, skipping."
}

# -------------------------------
# Generate and Validate Artifacts
# -------------------------------
Write-Host "Running generate-artifacts.ps1 ..."
pwsh ./scripts/generate-artifacts.ps1 -ArtifactsStorageAccountName $ArtifactsStorageAccountName

Write-Host "Running validate-artifacts.ps1 ..."
pwsh ./scripts/validate-artifacts.ps1

Write-Host "Deployment and artifacts setup completed successfully!"
Write-Host "Private DNS Zone: $privateDnsZoneName"
Write-Host "CNAME record: todo.$privateDnsZoneName -> $webVmName.$privateDnsZoneName"
Write-Host "Test URL: http://todo.$privateDnsZoneName:8080/"