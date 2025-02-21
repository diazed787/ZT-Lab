#!/bin/bash
echo "Checking if AppConnector is already running"
COUNT="$(docker ps | grep zpa-connector | wc -l)"
echo "App Connector count is $COUNT"
if [ $COUNT -ne 0 ]
then
	echo "AppConnector is already running"
else
	echo "Let's provision your AppConnector"
	read -p "Enter ZPA Prov Key: " ZPAKEY
	docker pull zscaler/zpa-connector:latest.amd64
	docker run -d --init \
	--name zpa-connector \
	--cap-add cap_net_admin \
	--cap-add cap_net_bind_service \
	--cap-add cap_net_raw \
	--cap-add cap_sys_nice \
	--cap-add cap_sys_time \
	--cap-add cap_sys_resource \
	--restart always \
	-e ZPA_PROVISION_KEY="$ZPAKEY" \
	zscaler/zpa-connector:latest.amd64
fi
