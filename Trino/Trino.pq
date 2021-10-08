///////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////
/////////////                                                                 /////////////
/////////////    Title: Trino Connector for Power BI                         ///////////// 
/////////////    Created by: Patrick Pichler (pichlerpatr@gmail.com)          ///////////// 
/////////////    Website: https://github.com/pichlerpa/ConnectorTrinoPowerBI  ///////////// 
/////////////                                                                 ///////////// 
///////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////

section Trino;

[DataSource.Kind="Trino", Publish="Trino.Publish"]
 shared Trino.Contents = Value.ReplaceType(TrinoImpl, TrinoType);

TrinoType = type function (
    Host as (type text meta [
        Documentation.FieldCaption = "Host",
        Documentation.FieldDescription = "The host name of the Trino coordinator.",
        Documentation.SampleValues = {"trinohost"}
    ]),
    Port as (type text meta [
        Documentation.FieldCaption = "Port",
        Documentation.FieldDescription = "The port to connect the Trino coordinator. Default: http=8080, https=8443",
        Documentation.SampleValues = {"8080"}
    ]),
    optional Catalog as (type text meta [
        Documentation.FieldCaption = "Catalog",
        Documentation.FieldDescription = "The catalog name to run queries against.",
        Documentation.SampleValues = {"Hive"}
    ]),
    optional User as (type text meta [
        Documentation.FieldCaption = "User",
        Documentation.FieldDescription = "The user name associated with the query. Default: TinoPBI",
        Documentation.SampleValues = {"TrinoPBI"}
    ]),
    optional Retries as (type number meta [
        Documentation.FieldCaption = "Retries",
        Documentation.FieldDescription = "The maximum number of attempts when sending requests to the host. Default: 5",
        Documentation.SampleValues = {5}
    ]),
    optional Timeout as (type number meta [
        Documentation.FieldCaption = "Timeout",
        Documentation.FieldDescription = "The maximum time to wait in seconds for the host to send data before giving up. Default: 100",
        Documentation.SampleValues = {100}
    ])
    )
    as table meta [
        Documentation.Name = "Trino",
        Documentation.LongDescription = "Trino Client REST API"        
    ];

TrinoImpl = (Host as text, Port as text, optional Catalog as text, optional User as text, optional Retries as number, optional Timeout as number) as table =>
    let
        User = if User is null then "TrinoPBI" else User,
        Header = [
            #"X-Trino-User" = User
            //, #"X-Trino-Client-Capabilities" = "PARAMETRIC_DATETIME"
            //, #"X-Forwarded-Proto" = "https",
            //#"Authorization" = "Basic " & Text.From(Extension.CurrentCredential()[Username]) & ":" & Text.From(Extension.CurrentCredential()[Password])
        ],
        ManualStatusHandling = {200,400,401,403,404,410,429,500,503},
        Http = if (Extension.CurrentCredential()[AuthenticationKind]?) = "UsernamePassword" then "https://" else "http://",        
        Url = Http & Host & ":" & Port & "/v1/statement",
        Retries = if Retries is null then 5 else Retries,
        Timeout = if Timeout is null then #duration(0,0,1,40) else #duration(0,0,0,Timeout), //WebContents default value are 100 seconds
        Table = TrinoNavTable(Url, Catalog, Retries, Timeout, Header, ManualStatusHandling)
    in
        Table;

duration = #duration(0,0,0,0);

PostStatementCatalogs = (Url as text, optional Catalog as text, optional Retries as number, optional Timeout as any, optional Header as any, optional ManualStatusHandling as any) as table =>    
    Table.Buffer(let
        response = Value.WaitFor(
                (iteration) =>
                    let
                        responsePrepare = () => Web.Contents(Url, [
                                Content = Text.ToBinary("show catalogs")
                                ,Headers=Header
                                ,Timeout=Timeout
                                //ManualStatusHandling = ManualStatusHandling
                            ]
                        ),
                        response = Function.InvokeAfter(responsePrepare, duration),
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => duration,
                Retries),
        body = Json.Document(response),
        Source = if (Record.HasFields(body, {"error"})) then error body[error][message] else GetAllPagesByNextLink(body[nextUri])        
     in
        if Catalog = null then Source else #table({"Catalog"}, {{Catalog}}));

PostStatementSchemas = (Url as text, optional Catalog as text, optional Retries as number, optional Timeout as any, optional Header as any, optional ManualStatusHandling as any) as table =>    
    Table.Buffer(let
         response = Value.WaitFor(
                (iteration) =>
                    let
                        responsePrepare = () => Web.Contents(Url, [
                                Content=Text.ToBinary("select schema_name from " & Catalog & ".information_schema.schemata")
                                ,Headers=Header
                                ,Timeout=Timeout
                                //ManualStatusHandling = ManualStatusHandling
                            ]
                        ), 
                        response = Function.InvokeAfter(responsePrepare, duration),
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => duration,
                Retries),
        body = Json.Document(response),
        Source = if (Record.HasFields(body, {"error"})) then error body[error][message] else GetAllPagesByNextLink(body[nextUri])

     in
        Source);

PostStatementTables = (Url as text, Catalog as text, Schema as text, optional Retries as number, optional Timeout as any, optional Header as number, optional ManualStatusHandling as any) as table =>       
    let
        response = Value.WaitFor(
                (iteration) =>
                    let
                        responsePrepare = () => Web.Contents(Url,[
                                Content=Text.ToBinary("select table_name, table_schema from " & Catalog & ".information_schema.tables where table_schema = '" & Schema & "'")
                                ,Headers=Header
                                ,Timeout=Timeout
                                //ManualStatusHandling = ManualStatusHandling
                            ]
                        ), 
                        response = Function.InvokeAfter(responsePrepare, duration),
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => duration,
                Retries),
        body = Json.Document(response),
        Source = if (Record.HasFields(body, {"error"})) then error body[error][message] else GetAllPagesByNextLink(body[nextUri])

     in
        Source;

PostStatementQueryTables = (url as text, Catalog as text, schema as text, table as text, optional Retries as number, optional Timeout as any, optional Header as any, optional ManualStatusHandling as any) as table =>          
    let
        response = Value.WaitFor(
                (iteration) =>
                    let
                        responsePrepare = () => Web.Contents(url, [
                                Content=Text.ToBinary("select * from " & Catalog & "." & schema & "." & table)
                                ,Headers=Header
                                ,Timeout=Timeout
                                //ManualStatusHandling = ManualStatusHandling
                            ]
                        ), 
                        response = Function.InvokeAfter(responsePrepare, duration),
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => duration,
                Retries),
        body = Json.Document(response),
        Source = if (Record.HasFields(body, {"error"})) then error body[error][message] else GetAllPagesByNextLink(body[nextUri])

     in
        Source;

// In this implementation, 'response' will be the parsed body of the response after the call to Json.Document.
// Look for the 'nextUri' field and simply return null if it doesn't exist.
GetNextLink = (response) as nullable text => Record.FieldOrDefault(response, "nextUri");

GetPage = (Url as text, optional Retries as number, optional Timeout as number, optional Header as any, optional ManualStatusHandling as any) as table =>          
    let
        response = Value.WaitFor(
                (iteration) =>
                    let
                        isRetry = if iteration > 0 then true else false,
                        responsePrepare = () => Web.Contents(Url, 
                            [
                                Headers=Header                                
                                ,IsRetry=isRetry
                                ,Timeout=Timeout
                                //,ManualStatusHandling = ManualStatusHandling
                            ]
                        ), 
                        response = Function.InvokeAfter(responsePrepare, duration),
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => duration,
                Retries),
        body = Json.Document(response),
        nextLink = GetNextLink(body), 

        DataTable =
            if (Record.HasFields(body, {"columns","data"}) and not List.IsEmpty(body[data]) and not List.IsEmpty(body[columns])) then
                let
                         //Prepare column names and appropriate types
                        ColumnTableConvert = Record.ToTable(body),
                        ColumnTableFilteredRows = Table.SelectRows(ColumnTableConvert, each ([Name] = "columns")),
                        ColumnTableExpandedValue = Table.ExpandListColumn(ColumnTableFilteredRows, "Value"),
                        ColumnTableFilteredRowsExpandedValue = Table.ExpandRecordColumn(ColumnTableExpandedValue, "Value", {"name", "type"}, {"name", "type"}),
                        ColumnTable = Table.RemoveColumns(ColumnTableFilteredRowsExpandedValue,{"Name"}),
                        ColumnTableMapping = Table.AddColumn(ColumnTable, "typeMapping", each 
                            if Text.Contains([type], "char") then type text //VARCHAR, CHAR
                            else if Text.Contains([type], "int") then type number //TINYINT, SMALLINT, INTEGER, BIGINT
                            else if Text.Contains([type], "decimal") then type number //DECIMAL
                            else if Text.Contains([type], "boolean") then type logical //BOOLEAN
                            else if Text.Contains([type], "date") then type date //DATE
                            else if Text.Contains([type], "timestamp") then type datetime //TIMESTAMP, TIMESTAMP(P),TIMESTAMP WITH TIME ZONE, TIMESTAMP(P) WITH TIME ZONE
                            else if Text.Contains([type], "time") then type time //TIME, TIME(P), TIME WITH TIME ZONE                            
                            else if Text.Contains([type], "real") then type number //REAL
                            else if Text.Contains([type], "double") then type number //DOUBLE  
                            else if Text.Contains([type], "varbinary") then type binary //VARBINARY
                            else type text), //INTERVAL YEAR TO MONTH, INTERVAL DAY TO SECOND, MAP, JSON, ARRAY, ROW, IPADDRESS, UUID
                        ColumnTableMappingTranspose = Table.Transpose(Table.SelectColumns(ColumnTableMapping,{"name","typeMapping"})),
                        ColumnTableMappingTransposeList = Table.ToColumns(ColumnTableMappingTranspose),

                        //Prepare corresponding data
                        DataTableConvert = Record.ToTable(body),
                        DataTableFilteredRows = Table.SelectRows(DataTableConvert, each ([Name] = "data")),
                        DataTableConvertExpandedValue = Table.ExpandListColumn(DataTableFilteredRows, "Value"),
                        DataTableFilteredRowsAddedCustom = Table.AddColumn(DataTableConvertExpandedValue, "Custom", each Table.Transpose(Table.FromList([Value], Splitter.SplitByNothing(), null, null, ExtraValues.Error))),
                        Data = Table.SelectColumns(DataTableFilteredRowsAddedCustom,{"Custom"}),

                        //Bring together columns and data
                        ColumnTableColumnsList = List.Generate(()=> [Counter=1], each [Counter] <= Table.RowCount(ColumnTable), each [Counter=[Counter]+1], each "Column" & Number.ToText([Counter])),
                        DataTableFilteredRowsExpandedCustom = Table.ExpandTableColumn(Data, "Custom", ColumnTableColumnsList),
                        DataTableReName = Table.RenameColumns(DataTableFilteredRowsExpandedCustom,List.Zip({Table.ColumnNames(DataTableFilteredRowsExpandedCustom),ColumnTable[name]})),
                        DataTableReType = Table.TransformColumnTypes(DataTableReName, ColumnTableMappingTransposeList)                                       
  
                   in
                        DataTableReType 
            else if (Record.HasFields(body, {"error"})) then 
                    let
                        //Output = error 
                        Output = error Error.Record(body[error][errorName], body[error][message], body[error][failureInfo][stack])
                    in
                        Output
            else
                #table({},{})                     
    in
        DataTable meta [NextLink = nextLink];


TrinoNavTable = (Url as text, optional Catalog as text, optional Retries as number, optional Timeout as any, optional Header as any, optional ManualStatusHandling as any) as table =>
    let
        catalogs = PostStatementCatalogs(Url,Catalog,Retries,Timeout,Header,ManualStatusHandling),
        catalogsRename = Table.RenameColumns(catalogs, {Table.ColumnNames(#"catalogs"){0},"Name"}),
        catalogsRenameSort = Table.Sort(catalogsRename, {"Name"}),
        DataColumn = Table.AddColumn(catalogsRenameSort,"Data", each TrinoNavTableLeaf(Url,[Name],Retries,Timeout,Header,ManualStatusHandling)),
        ItemKindColumn = Table.AddColumn(DataColumn,"ItemKind", each "Database"),
        ItemNameColumn = Table.AddColumn(ItemKindColumn,"ItemName", each "Database"),
        IsLeafColumn = Table.AddColumn(ItemNameColumn,"IsLeaf", each false),
        source = IsLeafColumn,
        navTable = Table.ToNavigationTable(source, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable;


TrinoNavTableLeaf = (Url as text, optional Catalog as text, optional Retries as number, optional Timeout as any, optional Header as any, optional ManualStatusHandling as any) as table =>
    let
        schemas = PostStatementSchemas(Url,Catalog,Retries,Timeout,Header,ManualStatusHandling),
        schemasConc = Table.AddColumn(schemas, "Name", each [schema_name]),
        tablesConcSort = Table.Sort(schemasConc, {"Name"}),
        DataColumn = Table.AddColumn(tablesConcSort,"Data", each TrinoNavTableLeafLeaf(Url,Catalog,[schema_name],Retries,Timeout,Header,ManualStatusHandling)),
        ItemKindColumn = Table.AddColumn(DataColumn,"ItemKind", each "Folder"),
        ItemNameColumn = Table.AddColumn(ItemKindColumn,"ItemName", each "Folder"),
        IsLeafColumn = Table.AddColumn(ItemNameColumn,"IsLeaf", each false),
        source = IsLeafColumn,
        navTable = Table.ToNavigationTable(source, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable;

TrinoNavTableLeafLeaf = (url as text, Catalog as text, Schema as text, optional Retries as number, optional Timeout as any, optional Header as any, optional ManualStatusHandling as any) as table =>
    let
        tables = PostStatementTables(url,Catalog,Schema,Retries,Timeout,Header,ManualStatusHandling),
        tablesConc = Table.AddColumn(tables, "Name", each [table_schema] & "." & [table_name]),
        tablesConcSort = Table.Sort(tablesConc, {"Name"}),       
        //DataColumn = Table.AddColumn(tablesConcSort,"Data", each Diagnostics.LogFailure("Error in GetEntity", () => PostStatementQueryTables(url,Catalog,[table_schema],[table_name]))),
        DataColumn = Table.AddColumn(tablesConcSort,"Data", each PostStatementQueryTables(url,Catalog,[table_schema],[table_name],Retries,Timeout,Header,ManualStatusHandling)),
        ItemKindColumn = Table.AddColumn(DataColumn,"ItemKind", each "Table"),
        ItemNameColumn = Table.AddColumn(ItemKindColumn,"ItemName", each "Table"),
        IsLeafColumn = Table.AddColumn(ItemNameColumn,"IsLeaf", each true),
        source = IsLeafColumn,
        navTable = Table.ToNavigationTable(source, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable;

//////////////////////
//// DATA SOURCE /////
//////////////////////

//Data Source Kind description
Trino = [
    Authentication = [
        UsernamePassword = [
            UsernameLabel = Extension.LoadString("UsernameLabelText"),
            PasswordLabel = Extension.LoadString("PasswordLabelText")
        ],      
//         Key = [
//                      Label = "Access Token",
//                      KeyLabel = "Get your access token at https://www.surveymonkey.com/apps/power_bi"
//                  ],
        // Windows = [],
        Implicit = []
    ],  
    Label = Extension.LoadString("DataSourceLabel")
];

// Data Source UI publishing description
Trino.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = Trino.Icons,
    SourceTypeImage = Trino.Icons
];

Trino.Icons = [
    Icon16 = { Extension.Contents("Trino16.png"), Extension.Contents("Trino20.png"), Extension.Contents("Trino24.png"), Extension.Contents("Trino32.png") },
    Icon32 = { Extension.Contents("Trino32.png"), Extension.Contents("Trino40.png"), Extension.Contents("Trino48.png"), Extension.Contents("Trino64.png") }
];


//////////////////////
// HELPER FUNCTIONS //
//////////////////////
Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;


//The getNextPage function takes a single argument and is expected to return a nullable table
Table.GenerateByPage = (getNextPage as function) as table =>
    let        
        listOfPages = List.Generate(
            () => getNextPage(null),            // get the first page of data
            (lastPage) => lastPage <> null,     // stop when the function returns null
            (lastPage) => getNextPage(lastPage) // pass the previous page to the next function call
        ),
        // concatenate the pages together and filter out empty pages
        tableOfPages = Table.FromList(listOfPages, Splitter.SplitByNothing(), {"Column1"}),
        tableOfPagesFiltered = Table.SelectRows(tableOfPages, each Table.IsEmpty([Column1]) = false),
        firstRow = tableOfPagesFiltered{0}?
    in
        // tableOfPagesFiltered;
        // if we didn't get back any pages of data, return an empty table
        // otherwise set the table type based on the columns of the first page
        if (firstRow = null) then
            Table.FromRows({})
        else        
            Value.ReplaceType(
                Table.ExpandTableColumn(tableOfPagesFiltered, "Column1", Table.ColumnNames(firstRow[Column1])),
                Value.Type(firstRow[Column1])
            );


// Read all pages of data.
// After every page, we check the "NextLink" record on the metadata of the previous request.
// Table.GenerateByPage will keep asking for more pages until we return null.
GetAllPagesByNextLink = (url as text) as table =>    
    Table.GenerateByPage((previous) => 
        let
            // if previous is null, then this is our first page of data
            nextLink = if (previous = null) then url else Value.Metadata(previous)[NextLink]?,
            // if NextLink was set to null by the previous call, we know we have no more data
            page = if (nextLink <> null) then GetPage(nextLink) else null
        in
            page
    );

Value.WaitFor = (producer as function, interval as function, optional count as number) as any =>
    let
        list = List.Generate(
            () => {0, null},
            (state) => state{0} <> null and (count = null or state{0} < count),
            (state) => if state{1} <> null then {null, state{1}} else {1 + state{0}, Function.InvokeAfter(() => producer(state{0}), interval(state{0}))},
            (state) => state{1})
    in
        List.Last(list);

//////////////////////
///// EXTENSIONS /////
//////////////////////

Extension.LoadFunction = (name as text) =>
    let
        binary = Extension.Contents(name),
        asText = Text.FromBinary(binary)
    in
        Expression.Evaluate(asText, #shared);

// Diagnostics module contains multiple functions. We can take the ones we need.
Diagnostics = Extension.LoadFunction("Diagnostics.pqm");
Diagnostics.LogValue = Diagnostics[LogValue];
Diagnostics.LogFailure = Diagnostics[LogFailure];