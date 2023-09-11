#!/bin/bash

set -e 

#############################################################################
############### UPDATE BELOW VARIABLES BEFORE RUNNING #######################
#############################################################################
vmName='resize-vm'                 # Name of the VM                       ###
rgName='resize-vm_group'           # Name of the resource group           ###
newSize='Standard_D2s_v5'          # New size for the VM                  ###
#############################################################################
#############################################################################

newVMName=''

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "Starting the VM to collect information"
az vm start -g $rgName --name $vmName 
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi

echo "Collecting the information of VM .................."
diskName=$(az vm show --name $vmName --resource-group $rgName \
    --query 'storageProfile.osDisk.name' -o tsv)
diskID=$(az vm show --name $vmName --resource-group $rgName \
    --query 'storageProfile.osDisk.managedDisk.id' -o tsv)
diskSAType=$(az vm show --name $vmName --resource-group $rgName \
    --query 'storageProfile.osDisk.managedDisk.storageAccountType' -o tsv)
diskSize=$(az vm show --name $vmName --resource-group $rgName \
    --query 'storageProfile.osDisk.diskSizeGb' -o tsv)
diskOS=$(az vm show --name $vmName --resource-group $rgName \
    --query 'storageProfile.osDisk.osType' -o tsv)
vmNIC=$(az vm show --name $vmName --resource-group $rgName \
    --query 'networkProfile.networkInterfaces[0].id' -o tsv)
dataDiskCount=$(az vm show --name $vmName --resource-group $rgName \
    --query 'storageProfile.dataDisks' -o tsv  | wc -l)
nicID=$(az vm show --name $vmName --resource-group $rgName \
    --query 'networkProfile.networkInterfaces[0].id' -o tsv)
subnetID=$(az network nic show --ids $nicID --query \
    'ipConfigurations[0].subnet.id' -o tsv)

echo -e "Creating the snapshot of the OS Disk"
diskSnapshot=$(az snapshot create -g $rgName --source $diskID --name "$diskName"-snapshot \
    --network-access-policy DenyAll --sku Standard_ZRS --tags Purpose=resize)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi

echo -e "Creating a new disk from the snpashot"
newOSDiks=$(az disk create -g $rgName -n "$diskName"-2 --source "$diskName"-snapshot \
    --size-gb $diskSize --sku $diskSAType --os-type $diskOS --hyper-v-generation \
    V2 --public-network-access Disabled)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi

echo -e "Creating a temp NIC"
tempNIC=$(az network nic create --name "$vmName"-tempnic -g $rgName --subnet $subnetID)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi

echo -e "Stopping the VM"
az vm deallocate -g $rgName --name $vmName
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi

echo -e "Attaching the temp NIC to the old VM"
attachTempNIC=$(az vm nic add --nics "$vmName"-tempnic -g $rgName --vm-name $vmName)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi

echo -e "Removing the main NIC from the old VM"
removeMainNIC=$(az vm nic remove -g $rgName --vm-name $vmName --nics $vmNIC)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi

echo -e "Creating the new VM........"
resizedVM=$(az vm create -g $rgName --name "$vmName"-2 --attach-os-disk "$diskName"-2 \
    --os-type $diskOS --size Standard_D2s_v5 --nics $vmNIC --security-type TrustedLaunch)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi


echo -e "Moving the data disks to the new Resized VM"
for ((i=0; i<$dataDiskCount; i++)) 
do 
    dataDisk=$(az vm show --name $vmName -g $rgName --query "storageProfile.dataDisks[0].name" -o tsv)
    dataDiskLUN=$(az vm show --name $vmName -g $rgName --query "storageProfile.dataDisks[0].lun" -o tsv) 
    dataDiskCache=$(az vm show --name $vmName -g $rgName --query "storageProfile.dataDisks[0].caching" -o tsv)
    echo "Detaching data disk $i" 
    az vm disk detach -g $rgName --name $dataDisk --vm-name $vmName
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[Success]${NC}\n"
    else 
        echo -e "${RED}Failed Exiting .... ${NC}"
    fi 
    
    echo "Attaching data disk $i" 
    az vm disk attach -g $rgName --name $dataDisk --vm-name "$vmName"-2 --lun $dataDiskLUN --caching $dataDiskCache
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[Success]${NC}\n"
    else 
        echo -e "${RED}Failed Exiting .... ${NC}"
    fi 
done 

