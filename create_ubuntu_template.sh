#!/bin/bash
echo "Downloading Ubuntu Cloud image from repository..."
wget -q https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img --show-progress
echo "Now we have to resize the image to desired disk size"
read -p "Select desired disk size in G:[40]" DISKSIZE
if [[ $DISKSIZE =~ ^$ ]]
then
	RESIZE=40
	echo "No Selection. Resizing image to default value of $RESIZE""G"
elif [[ $DISKSIZE =~ ^[0-9]*$ ]]
then
	RESIZE=$DISKSIZE
	echo "Resizing image to $RESIZE""G"
else
	echo "No valid numeric selection. Try again"
	exit
fi
qemu-img resize noble-server-cloudimg-amd64.img $RESIZE"G" 
echo "Please wait while we get environment details"
echo "Getting Existing VM IDs..."
VMVALUES="$(qm list | awk '$1 ~ /^[0-9]*$/{ print $1 }')"
echo "Getting configured storage objects..."
STROPTIONS="$(cat /etc/pve/storage.cfg | grep : | awk '{print $2}')"
#echo "Current VMID in use is: $VMVALUES"
read -p "Input VMID as Integer:[1000000]" VMIDINPUT
for VID in $VMVALUES
do
	if [[ $VMIDINPUT -eq $VID ]]
	then
		VMDUP=1
#		echo "The Selected VMID is already in use"
#	else
#		VMDUP=0
#		echo "The Selected VMID is available"
	fi
done
if [[ $VMIDINPUT =~ ^$ ]]
then
	VMID=1000000
	echo "No Selection. Defaulting to VMID $VMID"
elif [[ $VMIDINPUT =~ ^[0-9]*$ && $VMIDINPUT -le 1000000 && $VMDUP -ne 1 ]]
then
	VMID="$VMIDINPUT"
	echo "Unique VMID Selected"
else
	echo "VMID entered is not a valid number. Please try again"
	exit
fi
echo "Setting VMID ID to $VMID"
echo "Valid storage options are [$STROPTIONS]"
read -p "Select Storage Target [local-lvm]" STRINPUT
for SID in $STROPTIONS
do
        if [[ $STRINPUT -eq $SID ]]
        then
                ISVALID=1
	else
		echo "The Selected Storage is not a valid option. Try again"
		exit
        fi
done

if [[ $STRINPUT =~ ^$ && $STROPTIONS =~ local-lvm ]]
then
	STORAGE="local-lvm"
	echo "No Selection. Defaulting to $STORAGE"
fi
echo "Creating VM"
qm create $VMID --name "ubuntu-2404-cloudinit-template" --ostype l26 \
    --memory 2048 \
    --agent 1 \
    --bios ovmf --machine q35 --efidisk0 $STORAGE:0,pre-enrolled-keys=0 \
    --cpu host --socket 1 --cores 2 \
    --vga serial0 --serial0 socket  \
    --net0 virtio,bridge=vmbr0,firewall=0 
echo "Importing Ubuntu Cloud resized image"
qm importdisk $VMID noble-server-cloudimg-amd64.img $STORAGE 
echo "Setting hardware settings"
qm set $VMID --scsihw virtio-scsi-pci --virtio0 $STORAGE:vm-$VMID-disk-1,discard=on 
qm set $VMID --boot order=virtio0 
qm set $VMID --scsi1 $STORAGE:cloudinit 
echo "Creating Cloud Init file"
cat << EOF | tee /var/lib/vz/snippets/vendor.yaml
#cloud-config
package_update: true
package_upgrade: true
timezone: America/New_York
ssh_pwauth: true
runcmd:
    - apt update
    - apt install -y qemu-guest-agent
    - systemctl start qemu-guest-agent
    - reboot
EOF 
echo "Setting cloud init user and network settings"
qm set $VMID --cicustom "vendor=local:snippets/vendor.yaml" 
qm set $VMID --tags ubuntu-template,24.04,cloudinit 
read -p "Enter default cloud init user:[zsroot]" CI_INPUT 
if [[ $CI_INPUT =~ ^$ ]]
then
	echo "No Selection. Defaulting to zsroot"
	CI_USER="zsroot"
else
	echo "User will be $CI_INPUT"
	CI_USER="$CI_INPUT"
fi
CI_PASSWORD=""
while [[ $CI_PASSWORD =~ ^$ ]]
do
	read -sp "Enter Password:" PWD_INPUT
 	CI_PASSWORD=$PWD_INPUT
done
qm set $VMID --ciuser $CI_USER 
qm set $VMID --cipassword $(openssl passwd -6 $CI_PASSWORD) 
qm set $VMID --sshkeys ~/.ssh/authorized_keys 
qm set $VMID --ipconfig0 ip=dhcp 
rm noble-server-cloudimg-amd64.img
