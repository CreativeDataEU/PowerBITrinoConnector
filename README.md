# Power BI Trino
A Microsoft Power BI Custom Connector for importing Trino data into Power BI to interactively visualize and analyze data. 

## Trino client REST API
The connector is directly communicating with the [Trino client REST API](https://trino.io/docs/current/develop/client-protocol.html) to retrieve data and provides some pararmeters to configure. In case you recieve client timeout errors (ABANDONED_QUERY), they need to be fixed by changing the value of query.client.timeout in the coordinators config.properties file - default 5 minutes. Basic Authentication is currently the only supported authentication mode.

## Need further support?
In case you encounter any issues while installing or loading data, just open an issue or feel free to reach out to one of the contributors of this repository. 

## Usage Power BI Desktop
Before you begin you need to allow Power BI Desktop to load Custom Connectors according to this [official documentation from Microsoft](https://docs.microsoft.com/en-us/power-bi/connect-data/desktop-connector-extensibility). Once the connector is officially supported, this and the following steps are not required anymore.

1. You can take the .mez file from this [link](https://github.com/pichlerpa/PowerBITrinoConnector/raw/master/Trino/bin/Debug/Trino.mez) and place it in your Power BI custom connectors folder as outlined in the documentation. Once done, you should be able to see the connector listed in your "Get Data" window, restart Power BI Desktop in case it doesn't appear:

![Power BI Trino Connector Menu](https://github.com/pichlerpa/PowerBITrinoConnector/blob/master/Trino/img/MenuConnector.JPG)

2. Populate the required and optional Parameters to communicate with your Trino environment and hit OK to scan all your objects:

![Power BI Trino Connector Parameters](https://github.com/pichlerpa/PowerBITrinoConnector/blob/master/Trino/img/ParaConnector.JPG)

3. Choose the desired objects you want to import and click "Load" if you want to import data directly. Clicking "Transform Data" allows you to transform data before actually importing it into the analytical storage engine:

![Power BI Trino Connector Scanner](https://github.com/pichlerpa/PowerBITrinoConnector/blob/master/Trino/img/ScanConnector.JPG)

## Usage Power BI Service
To support end-to-end refresh through the Power BI Service on the cloud, it requires you to setup an [on-premises data gateway](https://docs.microsoft.com/en-us/power-bi/connect-data/service-gateway-custom-connectors). Once the connector is officially supported, this is not required anymore.

## Releases

**October 2021**
- 2021-10-15: First Release
