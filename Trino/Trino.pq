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
    Server as (type text meta [
        Documentation.FieldCaption = "Host",
        Documentation.FieldDescription = "Coordinater name including TCP port to connect (Defaults: http=8080, https=8443)",
        Documentation.SampleValues = {"http://trinohost:8080"}
    ]),
    optional Catalog as (type text meta [
        Documentation.FieldCaption = "Catalog",
        Documentation.FieldDescription = "Catalog name to run queries against",
        Documentation.SampleValues = {"Hive"}
    ])
    )
    as table meta [
        Documentation.Name = "Trino",
        Documentation.LongDescription = "Trino Client REST API"        
    ];

TrinoImpl = (Server as text, optional Catalog as text) as table =>
    let
        table = TrinoNavTable(Server, Catalog)   
    in
        table;


Header = [
    //#"X-Trino-User" = "Trino"
    //, #"X-Trino-Client-Capabilities" = "PARAMETRIC_DATETIME"
    //, #"X-Forwarded-Proto" = "https",
    //#"Authorization" = "Basic " & Text.From(Extension.CurrentCredential()[Username]) & ":" & Text.From(Extension.CurrentCredential()[Password])
];


duration = #duration(0,0,0,1/10);

PostStatementCatalogs = (url as text, optional Catalog as text) as table =>    
    Table.Buffer(let
        response = Value.WaitFor(
                (iteration) =>
                    let
                        responsePrepare = () => Web.Contents(url & "/v1/statement", 
                            [
                                Content=Text.ToBinary("SHOW CATALOGS"),
                                Headers=Header,
                                ManualStatusHandling = {200,400,401,403,404,429,500,503}
                            ]
                        ),
                        response = Function.InvokeAfter(responsePrepare, duration),
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => duration,
                5),
        body = Json.Document(response),
        Source = if (Record.HasFields(body, {"error"})) then error body[error][message] else GetAllPagesByNextLink(body[nextUri])        
     in
        if Catalog = null then Source else #table({"Catalog"}, {{Catalog}}));

PostStatementSchemas = (url as text, Catalog as text) as table  =>    
    Table.Buffer(let
         response = Value.WaitFor(
                (iteration) =>
                    let
                        responsePrepare = () => Web.Contents(url & "/v1/statement", 
                            [
                                Content=Text.ToBinary("Select schema_name from " & Catalog & ".information_schema.schemata"),
                                Headers=Header,
                                ManualStatusHandling = {200,400,401,403,404,429,500,503}
                            ]
                        ), 
                        response = Function.InvokeAfter(responsePrepare, duration),
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => duration,
                5),
        body = Json.Document(response),
        Source = if (Record.HasFields(body, {"error"})) then error body[error][message] else GetAllPagesByNextLink(body[nextUri])

     in
        Source);

PostStatementTables = (url as text, Catalog as text, Schema as text) as table  =>    
    let
        response = Value.WaitFor(
                (iteration) =>
                    let
                        responsePrepare = () => Web.Contents(url & "/v1/statement", 
                            [
                                Content=Text.ToBinary("Select table_name, table_schema from " & Catalog & ".information_schema.tables where table_schema = '" & Schema & "'"),
                                Headers=Header,
                                ManualStatusHandling = {200,400,401,403,404,429,500,503}
                            ]
                        ), 
                        response = Function.InvokeAfter(responsePrepare, duration),
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => duration,
                5),
        body = Json.Document(response),
        Source = if (Record.HasFields(body, {"error"})) then error body[error][message] else GetAllPagesByNextLink(body[nextUri])

     in
        Source;


PostStatementQueryTables = (url as text, Catalog as text, schema as text, table as text) as table  =>    
    let
        response = Value.WaitFor(
                (iteration) =>
                    let
                        responsePrepare = () => Web.Contents(url & "/v1/statement", 
                            [
                                Content=Text.ToBinary("Select * from " & Catalog & "." & schema & "." & table),
                                Headers=Header,
                                ManualStatusHandling = {200,400,401,403,404,429,500,503}
                            ]
                        ), 
                        response = Function.InvokeAfter(responsePrepare, duration),
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => duration,
                5),
        body = Json.Document(response),
        Source = if (Record.HasFields(body, {"error"})) then error body[error][message] else GetAllPagesByNextLink(body[nextUri])

     in
        Source;

// In this implementation, 'response' will be the parsed body of the response after the call to Json.Document.
// Look for the 'nextUri' field and simply return null if it doesn't exist.
GetNextLink = (response) as nullable text => Record.FieldOrDefault(response, "nextUri");

GetPage = (url as text) as table =>
    let
        response = Value.WaitFor(
                (iteration) =>
                    let
                        responsePrepare = () => Web.Contents(url, 
                            [
                                Headers=Header,
                                ManualStatusHandling = {200,400,401,403,404,429,500,503}
                            ]
                        ), 
                        response = Function.InvokeAfter(responsePrepare, duration),
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => duration,
                5),
        body = Json.Document(response),
        nextLink = GetNextLink(body), 

        DataTable =
            if (Record.HasFields(body, {"columns","data"}) and not List.IsEmpty(body[data])) then
                let
                         //Preparte Columns Table
                        ColumnTableConvert = try Record.ToTable(body) otherwise null,
                        ColumnTableExpandedValue = try Table.ExpandListColumn(ColumnTableConvert, "Value") otherwise null,
                        ColumnTableFilteredRows = try Table.SelectRows(ColumnTableExpandedValue, each ([Name] = "columns")) otherwise null,
                        ColumnTableFilteredRowsExpandedValue = Table.ExpandRecordColumn(ColumnTableFilteredRows, "Value", {"name", "type"}, {"name", "type"}),
                        ColumnTable = Table.RemoveColumns(ColumnTableFilteredRowsExpandedValue,{"Name"}),

                        //Preparte Data Table
                        DataTableConvert = try Record.ToTable(body) otherwise null,
                        DataTableConvertExpandedValue = try Table.ExpandListColumn(DataTableConvert, "Value") otherwise null,
                        DataTableFilteredRows = try Table.SelectRows(DataTableConvertExpandedValue, each ([Name] = "data")) otherwise null,
                        DataTableFilteredRowsAddedCustom = Table.AddColumn(DataTableFilteredRows, "Custom", each Table.Transpose(Table.FromList([Value], Splitter.SplitByNothing(), null, null, ExtraValues.Error))),
                        Data = Table.SelectColumns(DataTableFilteredRowsAddedCustom,{"Name", "Custom"}),

                        //Bring Columns and Data together
                        ColumnTableColumnsList = List.Generate(()=> [Counter=1], each [Counter] <= Table.RowCount(ColumnTable), each [Counter=[Counter]+1], each "Column" & Number.ToText([Counter])),
                        DataTableFilteredRowsExpandedCustom = Table.ExpandTableColumn(Data, "Custom", ColumnTableColumnsList),
                        DataTableFilteredRowsRemovedColumns = Table.RemoveColumns(DataTableFilteredRowsExpandedCustom,{"Name"}),
                        DataTable = Table.RenameColumns(DataTableFilteredRowsRemovedColumns,List.Zip({Table.ColumnNames(DataTableFilteredRowsRemovedColumns),ColumnTable[name]}))
                    in
                        DataTable                
            else
                #table({},{})                     
    in
        DataTable meta [NextLink = nextLink];

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

// The getNextPage function takes a single argument and is expected to return a nullable table
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

TrinoNavTable = (url as text, optional Catalog as text) as table =>
    let
        catalogs = PostStatementCatalogs(url,Catalog),
        catalogsRename = Table.RenameColumns(catalogs, {Table.ColumnNames(#"catalogs"){0},"Name"}),
        catalogsRenameSort = Table.Sort(catalogsRename, {"Name"}),
        DataColumn = Table.AddColumn(catalogsRenameSort,"Data", each TrinoNavTableLeaf(url,[Name])),
        ItemKindColumn = Table.AddColumn(DataColumn,"ItemKind", each "Database"),
        ItemNameColumn = Table.AddColumn(ItemKindColumn,"ItemName", each "Database"),
        IsLeafColumn = Table.AddColumn(ItemNameColumn,"IsLeaf", each false),
        source = IsLeafColumn,
        navTable = Table.ToNavigationTable(source, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable;


TrinoNavTableLeaf = (url as text, Catalog as text) as table =>
    let
        schemas = PostStatementSchemas(url,Catalog),
        schemasConc = Table.AddColumn(schemas, "Name", each [schema_name]),
        tablesConcSort = Table.Sort(schemasConc, {"Name"}),
        DataColumn = Table.AddColumn(tablesConcSort,"Data", each TrinoNavTableLeafLeaf(url,Catalog,[schema_name])),
        ItemKindColumn = Table.AddColumn(DataColumn,"ItemKind", each "Folder"),
        ItemNameColumn = Table.AddColumn(ItemKindColumn,"ItemName", each "Folder"),
        IsLeafColumn = Table.AddColumn(ItemNameColumn,"IsLeaf", each false),
        source = IsLeafColumn,
        navTable = Table.ToNavigationTable(source, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable;

TrinoNavTableLeafLeaf = (url as text, Catalog as text, Schema as text) as table =>
    let
        tables = PostStatementTables(url,Catalog,Schema),
        tablesConc = Table.AddColumn(tables, "Name", each [table_schema] & "." & [table_name]),
        tablesConcSort = Table.Sort(tablesConc, {"Name"}),
        DataColumn = Table.AddColumn(tablesConcSort,"Data", each PostStatementQueryTables(url,Catalog,[table_schema],[table_name])),
        ItemKindColumn = Table.AddColumn(DataColumn,"ItemKind", each "Table"),
        ItemNameColumn = Table.AddColumn(ItemKindColumn,"ItemName", each "Table"),
        IsLeafColumn = Table.AddColumn(ItemNameColumn,"IsLeaf", each true),
        source = IsLeafColumn,
        navTable = Table.ToNavigationTable(source, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable;

Value.WaitFor = (producer as function, interval as function, optional count as number) as any =>
    let
        list = List.Generate(
            () => {0, null},
            (state) => state{0} <> null and (count = null or state{0} < count),
            (state) => if state{1} <> null then {null, state{1}} else {1 + state{0}, Function.InvokeAfter(() => producer(state{0}), interval(state{0}))},
            (state) => state{1})
    in
        List.Last(list);


