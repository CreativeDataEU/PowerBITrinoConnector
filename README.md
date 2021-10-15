# Power BI Trino
A Microsoft Power BI Custom Connector for importing Trino data into Power BI to visualize data and to achieve interactive analytics on top of PowerBI's VertiPaq engine. 

## Trino client REST API
The connector is directly communicating with the [Trino client REST API](https://trino.io/docs/current/develop/client-protocol.html) to retrieve data.

## Need further support?
In case you encounter any issues while installting or loading data, then feel free to reach out to one of the contributors of this repository. 

## Usage Power BI Desktop
Before you begin you need to allow Power BI Desktop to load Custom Connectors according to this [official documentation from Microsot](https://docs.microsoft.com/en-us/power-bi/connect-data/desktop-connector-extensibility).

1. You can take the .mez file from this [link](https://github.com/pichlerpa/PowerBITrinoConnector/raw/master/Trino/bin/Debug/Trino.mez) and place it in your Power BI custom connectors folder. Now, you should be able to see connector listed in your "Get Data" window, restart Power BI Desktop in case it doesn't appear:

![Power BI Trino Connector Menu](https://github.com/pichlerpa/PowerBITrinoConnector/blob/master/Trino/img/MenuConnector.JPG)

2. Populate the required and optional Parameters to communicate with your Trino environment and hit OK to scan all your objects:

![Power BI Trino Connector Parameters](https://github.com/pichlerpa/PowerBITrinoConnector/blob/master/Trino/img/ParameterConnector.JPG)

3. Choose the desired objects you want to import and click "Load" if you want to import data directly or "Transform Data" to transform data before importing using Power Query/M:

![Power BI Trino Connector Scanner](https://github.com/pichlerpa/PowerBITrinoConnector/blob/master/Trino/img/ScanningConnector.JPG)

## Usage Power BI Servie

## Further Power BI Custom Connector information
For more information on how to create your own custom connectors folder, please visit the [official documentation from Microsoft Power BI Custom Connectors](https://docs.microsoft.com/en-us/power-bi/connect-data/desktop-connector-extensibility#custom-connectors).

## Releases

**October 2021**

--First Release
