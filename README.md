# ResizeMyAzureVM
A bash script that helps you resize the your Azure VM to a new SKU

## Overview  
Traditionally and with older generations of Azure VMs, there was a local ephemeral storage that was attached (for example Standard_D2s_v3, Standard_E48_v3), but as Microsoft released new generations of VMs this ephemeral storage is no longer available for the same SKU type. While it is tempting to move to the newer generation of VM, Azure does not allow resizing a VM size that has a local temp disk to a VM size with no local temp disk. The only way for someone to resize in this case is to take a snapshot of the OS disk and recreate the VM using the new SKU type. I have created this simple bash script to automate the process and move any data disk that might be attached to the original VM.  

