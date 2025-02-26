#!/bin/bash
echo "Please wait while we get environment details..."
echo "Getting Existing VM IDs..."
readarray -t VM_VALUES < <(qm list | awk '$1 ~ /^[0-9]*$/{ print $1 }')
echo "Getting configured storage objects..."
readarray -t STROPTIONS < <(cat /etc/pve/storage.cfg | grep : | awk '{print $2}')
echo "VM IDs already in use are: [${VM_VALUES[@]}]"

# BEGIN INPUTS SECTION
read -p "Input VMID as Integer: [1000000] " VMIDINPUT

# Check for no input
if [[ -z "$VMIDINPUT" ]]; then
    VMID=1000000
    echo "No Selection. Defaulting to VMID $VMID"
else
    VMID="$VMIDINPUT" #assign VMID here.
fi

# Check Selected VMID against existing values
VMDUP=0
for VID in "${VM_VALUES[@]}"; do
    if [[ "$VMID" -eq "$VID" ]]; then
        VMDUP=1
        break # Exit loop if duplicate found
    fi
done

if [[ "$VMID" =~ ^[0-9]+$ ]] && [[ "$VMID" -ge 100 ]] && [[ "$VMID" -le 1000000 ]] && [[ "$VMDUP" -eq 0 ]]; then
    echo "Unique VMID Selected"
else
    echo "VMID entered is not a valid number or is already in use. Please try again."
    exit 1
fi

echo "Setting VMID ID to $VMID"
echo "Valid storage options are: [${STROPTIONS[@]}]"
read -p "Select Storage Target: [local-lvm] " STRINPUT

# Check for no input
if [[ -z "$STRINPUT" ]]; then
    STORAGE="local-lvm"
else
    STORAGE="$STRINPUT"
fi

# Validate Storage input is valid
ISVALID=0
for SID in "${STROPTIONS[@]}"; do
    if [[ "$STORAGE" == "$SID" ]]; then
        ISVALID=1
        break # Exit loop if valid storage found
    fi
done

if [[ "$ISVALID" -eq 1 ]]; then
    echo "Setting storage to $STORAGE"
else
    echo "Storage input is not valid. Please try again."
    exit 1
fi

read -p "Select desired disk size in G: [40] " DISKSIZE
if [[ -z "$DISKSIZE" ]]; then
    RESIZE=40
    echo "No Selection. Resizing image to default value of $RESIZE""G"
elif [[ "$DISKSIZE" =~ ^[0-9]+$ ]]; then
    RESIZE="$DISKSIZE"
    echo "Resizing image to $RESIZE""G"
else
    echo "No valid numeric selection. Try again"
    exit 1
fi

read -p "Enter default cloud init user: [zsroot] " CI_INPUT
if [[ -z "$CI_INPUT" ]]; then
    echo "No Selection. Defaulting to zsroot"
    CI_USER="zsroot"
else
    echo "User will be $CI_INPUT"
    CI_USER="$CI_INPUT"
fi

read_password() {
    local PWD_1=""
    local PWD_2=""
    while true; do
        read -s -p "Enter password: " PWD_1
        echo ""
        if [[ -z "$PWD_1" ]]; then
            echo "Password cannot be blank. Please try again."
            continue
        fi
        read -s -p "Confirm password: " PWD_2
        echo ""
        if [[ "$PWD_1" == "$PWD_2" ]]; then
            break
        else
            echo "Passwords do not match. Please try again."
        fi
    done
    echo "Password confirmed."
    echo "$PWD_1" #return password.
}

CI_PASSWORD=$(read_password)
echo "Done"
echo "VM SUMMARY..."
echo "VMID: $VMID"
echo "Storage: $STORAGE"
echo "Disk Size: $RESIZE"
echo "Cloud Init User: $CI_USER"
##############################
##############################
##############################
##############################
##############################
echo "OK"
echo "Account Password Set"
#       END INPUT SECTION
echo "#......................................................#"
echo "#....Downloading Ubuntu Cloud image from repository....#"
echo "#......................................................#"
wget -q https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img --show-progress
echo "Now we have to resize the image to desired disk size"
echo "Resizing OS image..."
qemu-img resize noble-server-cloudimg-amd64.img $RESIZE"G" > /dev/null 
echo "Creating VM..."
qm create $VMID --name "ubuntu-2404-cloudinit-template" --ostype l26 \
    --memory 2048 \
    --agent 1 \
    --bios ovmf --machine q35 --efidisk0 $STORAGE:0,pre-enrolled-keys=0 \
    --cpu host --socket 1 --cores 2 \
    --vga serial0 --serial0 socket  \
    --net0 virtio,bridge=vmbr0,firewall=0 > /dev/null 
####################################
####################################
####################################
####################################
####################################
####################################
echo "Importing Ubuntu Cloud resized image..."
qm importdisk $VMID noble-server-cloudimg-amd64.img $STORAGE > /dev/null 
echo "Setting additional hardware settings..."
qm set $VMID --scsihw virtio-scsi-pci --virtio0 $STORAGE:vm-$VMID-disk-1,discard=on  > /dev/null
qm set $VMID --boot order=virtio0  > /dev/null
qm set $VMID --scsi1 $STORAGE:cloudinit  > /dev/null
echo "Creating Cloud Init file"
echo "........................"
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
echo "........................"
#       EVALUATE storage.cfg FILE AND LOOK FOR LINES DEFINING AN OBJECT
STORAGE_PARENT_LINES="$(cat /etc/pve/storage.cfg | grep -n : | cut -d : -f 1)"
#       DUMP RESULTS INTO AN ARRAY
STORAGE_PARENT_INDEX=()
for INDEX_ID in $STORAGE_PARENT_LINES
do
        STORAGE_PARENT_INDEX+=($INDEX_ID)
done
#       DETERMINE RESULTING ARRAY LENGTH
STORAGE_INDEX_LENGTH=${#STORAGE_PARENT_INDEX[@]}
#       GET LINE NUMBER WHERE local IS DEFINED
LOCAL_BEGIN="$(cat /etc/pve/storage.cfg | grep -n :\ local$ | cut -d : -f 1)"
#       DETERMINE INDEX NUMBER WHERE LINE EXIST AND ASSOCIATED LINE NUMBER
LOCAL_INDEX=0
for ITEM in "${STORAGE_PARENT_INDEX[@]}"
do
        if [[ $LOCAL_BEGIN -eq $ITEM ]]
        then
                break
        else
                ((LOCAL_INDEX++))
        fi
done
#       ESTABLISH LINES WERE CONFIGURATION BEGINS AND ENDS
LOCAL_NEXT=${STORAGE_PARENT_INDEX[$((LOCAL_INDEX+1))]}
LOCAL_END=$((LOCAL_NEXT-1))
#       GRAB CONFIG FILE LINE THAT WOULD BE CHANGED IF SNIPPETS NOT ENABLED
SED_LINE="$(awk "NR>=${LOCAL_BEGIN} &&  NR<=${LOCAL_END} && /content\ / {print NR}" /etc/pve/storagetest.cfg)"
#       GRAB CONFIGURATION STRING ON RELEVANT LINES
LOCAL_CONFIG="$(sed -n $LOCAL_BEGIN","$LOCAL_END"p" /etc/pve/storage.cfg)"
#       CHECK IF SNIPPETS EXIST, IF NOT ADD IT
echo "Checking if local storage supports snippets..."
if [[ "$LOCAL_CONFIG" == *snippets* ]]
then
        echo "Snippets already supported. No action was needed"
else
        echo "Creating backup of storage configuration file..."
        cp /etc/pve/storage.cfg etc/pve/storage.cfg.bkup
        echo "Adding snippets to local storage definition..."
        sed -i "${SED_LINE}s/content\ /content\ snippets,/" /etc/pve/storage.cfg
        systemctl restart pvestorage
fi
echo "Setting cloud init user and network settings..."
qm set $VMID --cicustom "vendor=local:snippets/vendor.yaml" > /dev/null 
qm set $VMID --tags ubuntu-template,24.04,cloudinit  > /dev/null
echo "Configuring credentials..."
qm set $VMID --ciuser $CI_USER > /dev/null 
qm set $VMID --cipassword $(openssl passwd -6 $CI_PASSWORD) > /dev/null 
qm set $VMID --sshkeys ~/.ssh/authorized_keys  > /dev/null
qm set $VMID --ipconfig0 ip=dhcp  > /dev/null
echo "Converting into a template..."
qm template $VMID > /dev/null
echo "Removing downloaded image..."
rm noble-server-cloudimg-amd64.img > /dev/null
