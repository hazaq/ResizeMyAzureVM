#!/bin/bash

set -e 

#############################################################################
############### UPDATE BELOW VARIABLES BEFORE RUNNING #######################
#############################################################################
vmName='resize-vm'                 # Name of the VM                       ###
rgName='resize-vm_group'           # Name of the resource group           ###
newSize='Standard_D2s_v5'          # New size for the VM                  ###
subName='resize-Subscription'      # Name or ID of the Subscription       ###
#############################################################################
#############################################################################

#Name of the new VM, the VM name should not be the same as the original VM.
newVMName="$vmName"-2

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "Starting the VM to collect information"
az vm start -g $rgName --name $vmName --subscription "$subName"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi

echo "Collecting the information of VM .................."
diskName=$(az vm show --name $vmName --resource-group $rgName \
    --subscription "$subName" --query 'storageProfile.osDisk.name' -o tsv)
diskID=$(az vm show --name $vmName --resource-group $rgName \
    --subscription "$subName" --query 'storageProfile.osDisk.managedDisk.id' -o tsv)
diskSAType=$(az vm show --name $vmName --resource-group $rgName \
    --subscription "$subName" --query 'storageProfile.osDisk.managedDisk.storageAccountType' -o tsv)
diskSize=$(az vm show --name $vmName --resource-group $rgName \
    --subscription "$subName" --query 'storageProfile.osDisk.diskSizeGb' -o tsv)
diskOS=$(az vm show --name $vmName --resource-group $rgName \
    --subscription "$subName" --query 'storageProfile.osDisk.osType' -o tsv)
vmNIC=$(az vm show --name $vmName --resource-group $rgName \
    --subscription "$subName" --query 'networkProfile.networkInterfaces[0].id' -o tsv)
dataDiskCount=$(az vm show --name $vmName --resource-group $rgName \
    --subscription "$subName" --query 'storageProfile.dataDisks' -o tsv  | wc -l)
nicID=$(az vm show --name $vmName --resource-group $rgName \
    --subscription "$subName" --query 'networkProfile.networkInterfaces[0].id' -o tsv)
subnetID=$(az network nic show --ids $nicID --query 'ipConfigurations[0].subnet.id' -o tsv)
secType=$(az disk show --disk-name $diskName --resource-group $rgName --subscription "$subName" \
    --query securityProfile.securityType -o tsv)
genType=$(az disk show --disk-name $diskName --resource-group $rgName --subscription "$subName" \
    --query hyperVGeneration -o tsv)

#If the Security Type is Standard then the secType variable will be empty 
if [ -z $secType ]
then 
    $secType='Standard'
fi

#Saving tags of the VM
az vm show --name $vmName --resource-group $rgName --subscription "$subName" \
    --query tags -o json > "$vmName"-tags.txt

echo -e "Creating the snapshot of the OS Disk"
diskSnapshot=$(az snapshot create -g $rgName --source $diskID --name "$diskName"-snapshot \
    --subscription "$subName" --network-access-policy DenyAll --sku Standard_ZRS --tags Purpose=resize)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi

echo -e "Creating a new disk from the snpashot"
newOSDiks=$(az disk create -g $rgName -n "$diskName"-2 --subscription "$subName" --source "$diskName"-snapshot \
    --size-gb $diskSize --sku $diskSAType --os-type $diskOS --hyper-v-generation $genType --public-network-access Disabled)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi

echo -e "Creating a temp NIC"
tempNIC=$(az network nic create --name "$vmName"-tempnic -g $rgName --subscription "$subName" --subnet $subnetID)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi

echo -e "Stopping the VM"
az vm deallocate -g $rgName --name $vmName --subscription "$subName"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi

echo -e "Attaching the temp NIC to the old VM"
attachTempNIC=$(az vm nic add --nics "$vmName"-tempnic -g $rgName --subscription "$subName" --vm-name $vmName)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi

echo -e "Removing the main NIC from the old VM"
removeMainNIC=$(az vm nic remove -g $rgName --vm-name $vmName --subscription "$subName" --nics $vmNIC)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi

echo -e "Creating the new VM........"
resizedVM=$(az vm create -g $rgName --name "$newVMName" --subscription "$subName" --attach-os-disk "$diskName"-2 \
    --os-type $diskOS --size $newSize --nics $vmNIC --security-type $secType)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success]${NC}\n"
else 
    echo -e "${RED}Failed Exiting .... ${NC}"
fi


echo -e "Moving the data disks to the new Resized VM"
for ((i=0; i<$dataDiskCount; i++)) 
do 
    dataDisk=$(az vm show --name $vmName -g $rgName --subscription "$subName" --query "storageProfile.dataDisks[0].name" -o tsv)
    dataDiskLUN=$(az vm show --name $vmName -g $rgName --subscription "$subName" --query "storageProfile.dataDisks[0].lun" -o tsv) 
    dataDiskCache=$(az vm show --name $vmName -g $rgName --subscription "$subName" --query "storageProfile.dataDisks[0].caching" -o tsv)
    echo "Detaching data disk $i" 
    az vm disk detach -g $rgName --name $dataDisk --vm-name $vmName --subscription "$subName"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[Success]${NC}\n"
    else 
        echo -e "${RED}Failed Exiting .... ${NC}"
    fi 
    
    echo "Attaching data disk $i" 
    az vm disk attach -g $rgName --name $dataDisk --subscription "$subName" --vm-name "$newVMName" --lun $dataDiskLUN --caching $dataDiskCache
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[Success]${NC}\n"
    else 
        echo -e "${RED}Failed Exiting .... ${NC}"
    fi 
done 

