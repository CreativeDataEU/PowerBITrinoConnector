# Power BI Trino
A Microsoft Power BI Custom Connector for importing Trino data into Power BI to visualize data and to achieve interactive analytics on top of PowerBI's VertiPaq engine. 

## Trino client REST API
The connector is directly communicating with the [Trino client REST API](https://trino.io/docs/current/develop/client-protocol.html) to retrieve data.

## Need further support?
In case you encounter any issues while installing or loading data, then feel free to reach out to one of the contributors of this repository. 

## Usage Power BI Desktop
Before you begin you need to allow Power BI Desktop to load Custom Connectors according to this [official documentation from Microsoft](https://docs.microsoft.com/en-us/power-bi/connect-data/desktop-connector-extensibility). This and the following steps end once the connector is officially supported.

1. You can take the .mez file from this [link](https://github.com/pichlerpa/PowerBITrinoConnector/raw/master/Trino/bin/Debug/Trino.mez) and place it in your Power BI custom connectors folder as outlined in the documentation. Once done, you should be able to see the connector listed in your "Get Data" window, restart Power BI Desktop in case it doesn't appear:

![Power BI Trino Connector Menu](https://github.com/pichlerpa/PowerBITrinoConnector/blob/master/Trino/img/MenuConnector.JPG)

2. Populate the required and optional Parameters to communicate with your Trino environment and hit OK to scan all your objects:

![Power BI Trino Connector Parameters](https://github.com/pichlerpa/PowerBITrinoConnector/blob/master/Trino/img/ParameterConnector.JPG)

3. Choose the desired objects you want to import and click "Load" if you want to import data directly. Clicking "Transform Data" allows you to transform data before actually importing it into the analytical storage engine:

![Power BI Trino Connector Scanner](https://github.com/pichlerpa/PowerBITrinoConnector/blob/master/Trino/img/ScanningConnector.JPG)

## Usage Power BI Servie
To support end-to-end refresh through the Power BI Service on the cloud, it requires you to setup an [on-premises data gateway](https://docs.microsoft.com/en-us/power-bi/connect-data/service-gateway-custom-connectors). This ends once the connector is officially supported.

## Releases

**October 2021**
- 2021-10-15: First Release
