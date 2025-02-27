#!/bin/bash
#	Check if jq is installed
echo "Checking if JQ is installed on host..."
JQ_BIN=$(dpkg -l | awk '$2 == "jq" { count++ } END { print count + 0 }')
if [[ "$JQ_BIN" == 1 ]]
then
	echo "JQ is already installed"
else
	echo "JQ is not installed"
	echo "Installing JQ..."
	apt install -y jq > /dev/null
fi
echo "Grabbing available VM templates"
echo "........."
#	Get next available VM ID in case there is no selection
VM_NEXT=$(pvesh get /cluster/nextid)
readarray -t TEMPLATE_VM < <(pvesh get /cluster/resources -type vm --output-format json | jq -c '.[] | select(.template == 1) | {vmid: .vmid, name: .name}')
readarray -t TEMPLATE_VMID < <(pvesh get /cluster/resources -type vm --output-format json | jq -c '.[] | select(.template == 1) | .vmid') 
echo "Getting Existing VM IDs..."
readarray -t VM_VALUES < <(qm list | awk '$1 ~ /^[0-9]*$/{ print $1 }')
echo "Getting configured storage objects..."
readarray -t STROPTIONS < <(cat /etc/pve/storage.cfg | grep : | awk '{print $2}')
echo "VM IDs already in use are: [${VM_VALUES[@]}]"
# BEGIN INPUTS SECTION
read -p "Input VMID as Integer: [next available] " VMIDINPUT
# Check for no input
if [[ -z "$VMIDINPUT" ]]; then
    VMID=$VM_NEXT
    echo "No Selection. Defaulting to next avialable value of $VM_NEXT"
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
#	Get VM name
VMNAMEINPUT="" 
read -p "Input VM Name: [docker] " VMNAMEINPUT
# Check for no input
if [[ -z "$VMNAMEINPUT" ]]; then
    NEWVM_NAME="docker"
    echo "No Selection. Defaulting to $NEWVM_NAME"
else
    NEWVM_NAME="$VMNAMEINPUT"
fi
echo "Available templates are: ${TEMPLATE_VM[@]}"
#	Check if any template VMs exist
if [[ ${#TEMPLATE_VMID[@]} -eq 0 ]]
then
  echo "No templates found."
  exit 1
fi
NEWVM_ID=$VMID
# 	Create Selection Menu
echo "Select a template VMID:"
select template_vmid in "${TEMPLATE_VMID[@]}"
do
	if [[ -n "$template_vmid" ]]
	then
		echo "You selected: $template_vmid"
		#pvesh create clone $template_vmid $NEWVM_ID $NEWVM_NAME --full
		break
	else
		echo "Invalid selection."
	fi
done
