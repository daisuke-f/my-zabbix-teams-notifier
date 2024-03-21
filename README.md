# Deploy Azure resources

```
az login

az group create --name test20240321 --location japaneast

az deployment group create --resource-group test20240321 --template-file azure/template.bicep
```

# Add permission to connect to Teams

# Set Teams groupId and channelId in Logic App

# Test Logic App

# Deploy Zabbix servers

```
git clone https://github.com/zabbix/zabbix-docker.git

docker compose --file docker-compose_v3_alpine_mysql_latest.yaml up --detach
```

# Configure Zabbix

* Media type
  * Import `zbx_export_mediatype.xml`
  * Set `post_url` to post url in Logic App
* User
* Trigger action

# Test alert

```
docker exec -it <zabbix-server-id> /bin/bash

zabbix_sender -z localhost -s "Test Alert Host" -k int -o 123

zabbix_sender -z localhost -s "Test Alert Host" -k int -o 0
```