#!/bin/bash
VMVALUES="$(qm list | awk '$1 ~ /^[0-9]*$/{ print $1 }')"
#echo "Current VMID in use is: $VMVALUES"
read -p "Input VMID as Integer:[1000000]" VMIDINPUT
for VID in $VMVALUES
do
	if [[ $VMIDINPUT -eq $VID ]]
	then
		VMDUP=1
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
