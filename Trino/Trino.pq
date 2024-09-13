//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////
/////////////                                                                    /////////////
/////////////    Title: Trino Connector for Power BI                             ///////////// 
/////////////    Created by: Patrick Pichler (patrick.pichler@creativedata.io)   ///////////// 
/////////////    Website: https://github.com/pichlerpa/PowerBITrinoConnector     ///////////// 
/////////////                                                                    ///////////// 
//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////

section Trino;

[DataSource.Kind="Trino", Publish="Trino.Publish"]
shared Trino.Contents = Value.ReplaceType(TrinoImpl, TrinoType);

shared TrinoType = type function (
    Host as (type text meta [
        DataSource.Path = true,
        Documentation.FieldCaption = "Host",
        Documentation.FieldDescription = "The host name of the Trino coordinator.",
        Documentation.SampleValues = {"trinohost"}
    ]),
    Port as (type number meta [
        DataSource.Path = true,
        Documentation.FieldCaption = "Port",
        Documentation.FieldDescription = "The port to connect the Trino coordinator. Default: http=8080, https=8443",
        Documentation.SampleValues = {8080}
    ]),
    optional Catalog as (type text meta [
        DataSource.Path = false,
        Documentation.FieldCaption = "Catalog",
        Documentation.FieldDescription = "The catalog name to run queries against. Default: All",
        Documentation.SampleValues = {"Hive"}
    ]),
    optional User as (type text meta [
        DataSource.Path = false,
        Documentation.FieldCaption = "User",
        Documentation.FieldDescription = "The user name associated with the query. Default: TrinoPBI",
        Documentation.SampleValues = {"TrinoPBI"}
    ]),
    optional Retries as (type number meta [
        DataSource.Path = false,
        Documentation.FieldCaption = "Retries",
        Documentation.FieldDescription = "The maximum number of attempts when sending requests to the host. Default: 5",
        Documentation.SampleValues = {5},
        Documentation.Visible = false
    ]),
    optional Timeout as (type number meta [
        DataSource.Path = false,
        Documentation.FieldCaption = "Timeout",
        Documentation.FieldDescription = "The maximum time to wait in seconds for the host to send data before giving up. Default: 100",
        Documentation.SampleValues = {100}
    ]),
    optional SQLQuery as (type text meta [
        DataSource.Path = false,
        Documentation.FieldCaption = "SQL Query",
        Documentation.FieldDescription = "The SQL query you want to execute to retrieve data.",
        Documentation.SampleValues = {"select custkey,name from tpch.sf1.customer"},
        Formatting.IsMultiLine = true
    ])
    )
    as table meta [
        Documentation.Name = "Trino",
        Documentation.LongDescription = "Trino Client REST API"        
    ];

DefaultUser = "TrinoPBI";
DefaultRetries = 5;
DefaultTimeout = 100;
DefaultDelayAPICallRetry = #duration(0,0,0,1/2);
Http = if (Extension.CurrentCredential()[AuthenticationKind]?) = "Implicit" then "http://" else "https://";

TrinoImpl = (Host as text, Port as number, optional Catalog as text, optional User as text, optional Retries as number, optional Timeout as number, optional SQLQuery as text) as table =>
    let
        Url = Http & Host & ":" & Number.ToText(Port) & "/v1/statement",
        Table = 
            if SQLQuery is null then 
                TrinoNavTable(Url, Catalog, User, Retries, Timeout)
            else 
                let
                    User = if User is null and (Extension.CurrentCredential()[AuthenticationKind]?) <> "UsernamePassword" then DefaultUser 
                        else if User is null and (Extension.CurrentCredential()[AuthenticationKind]?) = "UsernamePassword" then Extension.CurrentCredential()[Username] 
                        else User,
                    Retries = if Retries is null then DefaultRetries else Retries,
                    Timeout = if Timeout is null then DefaultTimeout else Timeout,
                    response = Value.WaitFor(
                        (iteration) =>
                            let
                                isRetry = if iteration > 0 then true else false,
                                response = Web.Contents(Url,
                                    [
                                        Content = Text.ToBinary(SQLQuery),
                                        Headers = [#"X-Trino-User" = User],
                                        Timeout = #duration(0, 0, 0, Timeout),
                                        IsRetry = isRetry
                                    ]
                                ),
                                buffered = Binary.Buffer(response),
                                responseCode = Value.Metadata(response)[Response.Status],
                                actualResult = if buffered <> null and responseCode = 200 then buffered else null
                            in
                                actualResult,
                        (iteration) => DefaultDelayAPICallRetry,
                        Retries
                    ),
                    body = Json.Document(response),
                    Source = if (Record.HasFields(body, {"error"})) then error body[error][message] else GetAllPagesByNextLink(body[nextUri], User, Retries, Timeout)
                in
                    Source
    in
        Table;


PostStatementCatalogs = (url as text, optional Catalog as text, optional User as text, optional Retries as number, optional Timeout as number) as table =>    
    let
        response = Value.WaitFor(
                (iteration) =>
                    let
                        isRetry = if iteration > 0 then true else false,
                        response = Web.Contents(url,
                            [
                                 Content = Text.ToBinary("show catalogs")
                                ,Headers = [#"X-Trino-User" = User]
                                ,Timeout = #duration(0, 0, 0, Timeout)
                                ,IsRetry = isRetry
                            ]
                        ),                        
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => DefaultDelayAPICallRetry,
                Retries),
        body = Json.Document(response),
        Source = if (Record.HasFields(body, {"error"})) then error body[error][message] else GetAllPagesByNextLink(body[nextUri],User,Retries,Timeout)        
     in
        if Catalog = null then Source else #table({"Catalog"}, {{Catalog}});

PostStatementSchemas = (url as text, Catalog as text, User as text, Retries as number, Timeout as number) as table  =>    
    let
        response = Value.WaitFor(
                (iteration) =>
                    let
                        isRetry = if iteration > 0 then true else false,
                        response = Web.Contents(url,
                            [
                                 Content = Text.ToBinary("select schema_name from """ & Catalog & """.information_schema.schemata")
                                ,Headers = [#"X-Trino-User" = User]
                                ,Timeout = #duration(0, 0, 0, Timeout)
                                ,IsRetry = isRetry
                            ]
                        ),
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => DefaultDelayAPICallRetry,
                Retries),
        body = Json.Document(response),
        Source = if (Record.HasFields(body, {"error"})) then error body[error][message] else GetAllPagesByNextLink(body[nextUri],User,Retries,Timeout)
     in
        Source;

PostStatementTables = (url as text, Catalog as text, Schema as text, User as text, Retries as number, Timeout as number) as table  =>    
    let
        response = Value.WaitFor(
                (iteration) =>
                    let
                        isRetry = if iteration > 0 then true else false,
                        response = Web.Contents(url, 
                            [
                                 Content = Text.ToBinary("select table_name, table_schema from """ & Catalog & """.information_schema.tables where table_schema = '" & Schema & "'")
                                ,Headers = [#"X-Trino-User" = User]
                                ,Timeout = #duration(0, 0, 0, Timeout)
                                ,IsRetry = isRetry
                            ]
                        ), 
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => DefaultDelayAPICallRetry,
                Retries),
        body = Json.Document(response),
        Source = if (Record.HasFields(body, {"error"})) then error body[error][message] else GetAllPagesByNextLink(body[nextUri],User,Retries,Timeout)

     in
        Source;

PostStatementQueryColumnNames = (url as text, Catalog as text, schema as text, table as text, User as text, Retries as number, Timeout as number) as table  => 
    let      
       response = Value.WaitFor(
                (iteration) =>
                    let
                        isRetry = if iteration > 0 then true else false,
                        response = Web.Contents(url, 
                            [
                                 Content = Text.ToBinary("select column_name from """ & Catalog & """.information_schema.columns where table_schema = '" & schema & "' and table_name = '" & table & "' order by ordinal_position")
                                ,Headers = [#"X-Trino-User" = User]
                                ,Timeout = #duration(0, 0, 0, Timeout)
                                ,IsRetry = isRetry
                            ]
                        ), 
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => DefaultDelayAPICallRetry,
                Retries),
        body = Json.Document(response),
        Source = if (Record.HasFields(body, {"error"})) then error body[error][message] else GetAllPagesByNextLink(body[nextUri],User,Retries,Timeout)
     in
        Source;

PostStatementQueryTables = (url as text, Catalog as text, schema as text, table as text, User as text, Retries as number, Timeout as number) as table  =>    
    let   
        //get and prepare column names
        ColumnNamesTable = PostStatementQueryColumnNames(url,Catalog,schema,table,User,Retries,Timeout),
        ColumnNameAddedCustom = Table.AddColumn(ColumnNamesTable, "group", each "group"),
        ColumnNameGroupedRows = Table.Group(ColumnNameAddedCustom, {"group"}, {{"column_name_group", each _, type table [column_name=nullable text, group=text]}}),
        DataAddedCustom = Table.AddColumn(ColumnNameGroupedRows, "column_name", each Table.Column([column_name_group], "column_name")),
        ColumnNameString = Table.TransformColumns(DataAddedCustom, {"column_name", each """" & Text.Combine(List.Transform(_, Text.From), """,""") & """", type text}),
        ColumnNameStringSelect = Table.SelectColumns(ColumnNameString,"column_name"),
        ColumnNameStringSelectString = Record.Field(ColumnNameStringSelect{0}, "column_name") as text,

        //trigger query using column names
        response = Value.WaitFor(
                (iteration) =>
                    let
                        isRetry = if iteration > 0 then true else false,
                        response = Web.Contents(url, 
                            [
                                 Content = Text.ToBinary("select " & ColumnNameStringSelectString & " from """ & Catalog & """.""" & schema & """.""" & table & """")
                                ,Headers = [#"X-Trino-User" = User]
                                ,Timeout = #duration(0, 0, 0, Timeout)
                                ,IsRetry = isRetry
                            ]
                        ), 
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => DefaultDelayAPICallRetry,
                Retries),
        body = Json.Document(response),
        Source = if (Record.HasFields(body, {"error"})) then error body[error][message] else GetAllPagesByNextLink(body[nextUri],User,Retries,Timeout)
     in
        Source;

GetPage = (url as text, User as text, Retries as number, Timeout as number) as table =>
    let        
        response = Value.WaitFor(
                (iteration) =>
                    let
                        isRetry = if iteration > 0 then true else false,
                        response = Web.Contents(url, 
                            [
                                 Headers = [#"X-Trino-User" = User]
                                ,Timeout = #duration(0, 0, 0, Timeout)
                                ,IsRetry = isRetry                             
                            ]
                        ), 
                        buffered = Binary.Buffer(response),
                        responseCode = Value.Metadata(response)[Response.Status],
                        actualResult = if buffered <> null and responseCode = 200 then buffered else null
                    in
                        actualResult,
                (iteration) => DefaultDelayAPICallRetry,
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
                        else if Value.Equals([type], "date") then type date //DATE
                        else if Value.Equals([type], "time") then type time //TIME, TIME(P)
                        else if Value.Equals([type], "timestamp") then type datetime //TIMESTAMP, TIMESTAMP(P) 
                        else if Text.Contains([type], "with time zone") then type text //TIMESTAMP(P) WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, TIME WITH TIME ZONE                  
                        else if Text.Contains([type], "real") then type number //REAL
                        else if Text.Contains([type], "double") then type number //DOUBLE  
                        else if Text.Contains([type], "varbinary") then type binary //VARBINARY
                        else type text), //INTERVAL YEAR TO MONTH, INTERVAL DAY TO SECOND, IPADDRESS, UUID

                    // Prepare the list for TransformColumnTypes and filter out columns with type containing "MAP", "JSON", "ARRAY", or "ROW" otherwise error occurs
                    ColumnTableMappingFiltered = Table.SelectRows(ColumnTableMapping, each not (
                        Text.Contains([type], "array") or
                        Text.Contains([type], "map") or
                        Text.Contains([type], "json") or
                        Text.Contains([type], "row")
                    )),
                    ColumnTableMappingTranspose = Table.Transpose(Table.SelectColumns(ColumnTableMappingFiltered, {"name", "typeMapping"})),
                    ColumnTableMappingTransposeList = Table.ToColumns(ColumnTableMappingTranspose),

                    // Prepare corresponding data
                    DataTableConvert = Record.ToTable(body),
                    DataTableFilteredRows = Table.SelectRows(DataTableConvert, each ([Name] = "data")),
                    DataTableConvertExpandedValue = Table.ExpandListColumn(DataTableFilteredRows, "Value"),
                    DataTableFilteredRowsAddedCustom = Table.AddColumn(DataTableConvertExpandedValue, "Custom", each Table.Transpose(Table.FromList([Value], Splitter.SplitByNothing(), null, null, ExtraValues.Error))),
                    Data = Table.SelectColumns(DataTableFilteredRowsAddedCustom, {"Custom"}),

                    // Bring together columns and data
                    ColumnTableColumnsList = List.Generate(()=> [Counter=1], each [Counter] <= Table.RowCount(ColumnTable), each [Counter=[Counter]+1], each "Column" & Number.ToText([Counter])),
                    DataTableFilteredRowsExpandedCustom = Table.ExpandTableColumn(Data, "Custom", ColumnTableColumnsList),
                    DataTableReName = Table.RenameColumns(DataTableFilteredRowsExpandedCustom, List.Zip({Table.ColumnNames(DataTableFilteredRowsExpandedCustom), ColumnTable[name]})),

                    // Apply column type transformations
                    DataTableReType = Table.TransformColumnTypes(DataTableReName, ColumnTableMappingTransposeList)
                in
                    DataTableReType
            else if (Record.HasFields(body, {"error"})) then 
                let
                    Output = error Error.Record("Trino Error: " & body[error][errorName], body[error][message], body[error][failureInfo][stack])
                in
                    Output
            else
                #table({},{})                     
    in
        DataTable meta [NextLink = nextLink];

///////////////////////
///// NAVIGATION //////
///////////////////////

TrinoNavTable = (url as text, optional Catalog as text, optional User as text, optional Retries as number, optional Timeout as number) as table =>
    let
        User = if User is null and (Extension.CurrentCredential()[AuthenticationKind]?) <> "UsernamePassword" then DefaultUser 
               else if User is null and (Extension.CurrentCredential()[AuthenticationKind]?) = "UsernamePassword" then Extension.CurrentCredential()[Username] 
               else User,
        Retries = if Retries is null then DefaultRetries else Retries,
        Timeout = if Timeout is null then DefaultTimeout else Timeout,
        catalogs = PostStatementCatalogs(url,Catalog,User,Retries,Timeout),
        catalogsRename = Table.RenameColumns(catalogs, {Table.ColumnNames(#"catalogs"){0},"Name"}),
        catalogsRenameSort = Table.Sort(catalogsRename, {"Name"}),
        NameKeyColumn = Table.DuplicateColumn(catalogsRenameSort,"Name","NameKey", type text),
        UrlColumn = Table.AddColumn(NameKeyColumn,"Url", each url),
        UserColumn = Table.AddColumn(UrlColumn,"User", each User),
        RetriesColumn = Table.AddColumn(UserColumn,"Retries", each Retries),
        TimeoutColumn = Table.AddColumn(RetriesColumn,"Timeout", each Timeout),
        //DataColumn = Table.AddColumn(UrlColumn ,"Data", each TrinoNavTableLeaf(url,[Name])),
        ItemKindColumn = Table.AddColumn(TimeoutColumn,"ItemKind", each "Database"),
        ItemNameColumn = Table.AddColumn(ItemKindColumn,"ItemName", each "Database"),
        IsLeafColumn = Table.AddColumn(ItemNameColumn,"IsLeaf", each false),
        source = IsLeafColumn,
        //navTable = Table.ToNavigationTable(source, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
        AsNavigationView = Table.NavigationTableView(() => source, {"Url","NameKey","User","Retries","Timeout"}, TrinoNavTableLeaf, [
            Name = each [Name],
            ItemKind = each [ItemKind],
            ItemName = each [ItemName],
            IsLeaf = each [IsLeaf]
        ])
    in
        AsNavigationView;

TrinoNavTableLeaf = (url as text, Catalog as text, optional User as text, optional Retries as number, optional Timeout as number)  as table =>
    let      
        User = if User is null and (Extension.CurrentCredential()[AuthenticationKind]?) <> "UsernamePassword" then DefaultUser 
               else if User is null and (Extension.CurrentCredential()[AuthenticationKind]?) = "UsernamePassword" then Extension.CurrentCredential()[Username] 
               else User,
        Retries = if Retries is null then DefaultRetries else Retries,
        Timeout = if Timeout is null then DefaultTimeout else Timeout,
        schemas = PostStatementSchemas(url,Catalog,User,Retries,Timeout),
        schemasConc = Table.AddColumn(schemas, "Name", each [schema_name]),
        tablesConcSort = Table.Sort(schemasConc, {"Name"}),        
        NameKeyColumn = Table.DuplicateColumn(tablesConcSort,"Name","NameKey", type text),
        UrlColumn = Table.AddColumn(NameKeyColumn,"Url", each url),
        CatalogColumn = Table.AddColumn(UrlColumn,"Catalog", each Catalog),
        UserColumn = Table.AddColumn(CatalogColumn,"User", each User),
        RetriesColumn = Table.AddColumn(UserColumn,"Retries", each Retries),
        TimeoutColumn = Table.AddColumn(RetriesColumn,"Timeout", each Timeout),
        //DataColumn = Table.AddColumn(UrlColumn,"Data", each TrinoNavTableLeafLeaf(url,Catalog,[schema_name])),
        ItemKindColumn = Table.AddColumn(TimeoutColumn,"ItemKind", each "Folder"),
        ItemNameColumn = Table.AddColumn(ItemKindColumn,"ItemName", each "Folder"),
        IsLeafColumn = Table.AddColumn(ItemNameColumn,"IsLeaf", each false),
        source = IsLeafColumn,
        //navTable = Table.ToNavigationTable(source, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf"),
        AsNavigationView = Table.NavigationTableView(() => source, {"Url","Catalog","NameKey","User","Retries","Timeout"}, TrinoNavTableLeafLeaf, [
            Name = each [Name],
            ItemKind = each [ItemKind],
            ItemName = each [ItemName],
            IsLeaf = each [IsLeaf]
        ])
    in
        AsNavigationView;

TrinoNavTableLeafLeaf = (url as text, Catalog as text, Schema as text, optional User as text, optional Retries as number, optional Timeout as number)  as table =>
    let
        User = if User is null and (Extension.CurrentCredential()[AuthenticationKind]?) <> "UsernamePassword" then DefaultUser 
               else if User is null and (Extension.CurrentCredential()[AuthenticationKind]?) = "UsernamePassword" then Extension.CurrentCredential()[Username] 
               else User,
        Retries = if Retries is null then DefaultRetries else Retries,
        Timeout = if Timeout is null then DefaultTimeout else Timeout,
        tables = PostStatementTables(url,Catalog,Schema,User,Retries,Timeout),
        tablesConc = Table.AddColumn(tables, "Name", each [table_schema] & "." & [table_name]),
        tablesConcSort = Table.Sort(tablesConc, {"Name"}),   
        NameKeyColumn = Table.DuplicateColumn(tablesConcSort,"Name","NameKey", type text),
        UrlColumn = Table.AddColumn(NameKeyColumn,"Url", each url),
        CatalogColumn = Table.AddColumn(UrlColumn,"Catalog", each Catalog),
        SchemaColumn = Table.AddColumn(CatalogColumn, "Schema", each [table_schema]),
        TableColumn = Table.AddColumn(SchemaColumn, "Table", each [table_name]),
        UserColumn = Table.AddColumn(TableColumn,"User", each User),
        RetriesColumn = Table.AddColumn(UserColumn,"Retries", each Retries),
        TimeoutColumn = Table.AddColumn(RetriesColumn,"Timeout", each Timeout),
        //DataColumn = Table.AddColumn(tablesConcSort,"Data", each Diagnostics.LogFailure("Error in GetEntity", () => PostStatementQueryTables(url,Catalog,[table_schema],[table_name]))),
        //DataColumn = Table.AddColumn(tablesConcSort,"Data", each PostStatementQueryTables(url,Catalog,[table_schema],[table_name])),
        ItemKindColumn = Table.AddColumn(TimeoutColumn,"ItemKind", each "Table"),
        ItemNameColumn = Table.AddColumn(ItemKindColumn,"ItemName", each "Table"),
        IsLeafColumn = Table.AddColumn(ItemNameColumn,"IsLeaf", each true),        
        source = IsLeafColumn,
        //navTable = Table.ToNavigationTable(source, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
        AsNavigationView = Table.NavigationTableView(() => source, {"Url","Catalog","Schema","Table","User","Retries","Timeout"},  PostStatementQueryTables, [
             Name = each [Name],
             ItemKind = each [ItemKind],
             ItemName = each [ItemName],
             IsLeaf = each [IsLeaf]
        ])
    in
        AsNavigationView;  


//////////////////////
//// DATA SOURCE /////
//////////////////////

// OAuth2 values
redirect_uri = "https://oauth.powerbi.com/views/oauthredirect.html";
client_id = Text.FromBinary(Extension.Contents("oauth_config_client_id.txt"));
client_secret = Text.FromBinary(Extension.Contents("oauth_config_client_secret.txt"));
authorize_uri = Text.FromBinary(Extension.Contents("oauth_config_authorize_uri.txt"));
scopes = Text.FromBinary(Extension.Contents("oauth_config_scopes.txt"));
token_uri = Text.FromBinary(Extension.Contents("oauth_config_token_uri.txt"));

//Data Source Kind description
Trino = [
    Authentication = [
        OAuth = [
            StartLogin = StartLogin,
            FinishLogin = FinishLogin
        ],
        UsernamePassword = [
            UsernameLabel = Extension.LoadString("UsernameLabelText"),
            PasswordLabel = Extension.LoadString("PasswordLabelText")
        ],   
        Implicit = []
    ],  
   TestConnection = (dataSourcePath) =>
        let
            json = Json.Document(dataSourcePath),
            host = json[Host],
            port = json[Port]
        in
            { "Trino.Contents", host, port }
    //Label = "Trino"
];

// OAuth helper functions: StartLogin, FinishLogin, Token Method
StartLogin = (resourceUrl, state, display) =>
    let
        AuthorizeUrl = authorize_uri & "?" & Uri.BuildQueryString([
            response_type = "code",
            client_id = client_id,  
            redirect_uri = redirect_uri,
            state = state,
            scope = scopes
        ])
    in
        [
            LoginUri = AuthorizeUrl,
            CallbackUri = redirect_uri,
            WindowHeight = 720,
            WindowWidth = 1024,
            Context = null
        ];

FinishLogin = (context, callbackUri, state) =>
    let
        Parts = Uri.Parts(callbackUri)[Query]
    in
        TokenMethod(Parts[code]);

// Base64Encode(client_id:client_secret)
// https://docs.aws.amazon.com/cognito/latest/developerguide/token-endpoint.html
client_id_secret = client_id & ":" & client_secret;
client_id_secret_bytes = Text.ToBinary(client_id_secret);
client_id_secret_base64 = Binary.ToText(client_id_secret_bytes);

TokenMethod = (code) =>
    let
        Response = Web.Contents(token_uri, [
            Content = Text.ToBinary(Uri.BuildQueryString([
                grant_type = "authorization_code",
                client_id = client_id,
                code = code,
                redirect_uri = redirect_uri])),
            Headers=[
                #"Content-Type" = "application/x-www-form-urlencoded",
                #"Authorization" = "Basic " & client_id_secret_base64]]),
        Parts = Json.Document(Response)
    in
        Parts;

// Data Source UI publishing description
Trino.Publish = [
    Beta = true,
    Category = "Database",
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

// In this implementation, 'response' will be the parsed body of the response after the call to Json.Document.
// Look for the 'nextUri' field and simply return null if it doesn't exist.
GetNextLink = (response) as nullable text => Record.FieldOrDefault(response, "nextUri");

// Read all pages of data.
// After every page, we check the "NextLink" record on the metadata of the previous request.
// Table.GenerateByPage will keep asking for more pages until we return null.
GetAllPagesByNextLink = (url as text, User as text, Retries as number, Timeout as number) as table =>    
    Table.GenerateByPage((previous) => 
        let
            User = if User is null then DefaultUser else User,
            // if previous is null, then this is our first page of data
            nextLink = if (previous = null) then url else Value.Metadata(previous)[NextLink]?,
            // if NextLink was set to null by the previous call, we know we have no more data
            page = if (nextLink <> null) then GetPage(nextLink,User,Retries,Timeout) else null
        in
            page
    );

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


// This is intended to be a reusable helper which takes a constructor for the base navigation table,
// a list of key columns whose values uniquely describe a row in the navigation table, a constructor
// for the table to returned as data for a given row in the navigation table, and a record with a
// description of how to construct the output navigation table.
//
// The baseTable constructor will only be invoked if necessary, such as when initially returning the
// navigation table. If a user query is something like "navTable{[Key1=Value1, Key2=Value2]}[Data]",
// then the code will not call the baseTable function and instead just call dataCtor(Value1, Value2).
//
// Obviously, dataCtor itself could return another navigation table.
//
// Disclaimer: this hasn't been as extensively tested as I'd like -- and in fact, I found and fixed a
// bug while setting up the test case above.

Table.NavigationTableView =
(
    baseTable as function,
    keyColumns as list,
    dataCtor as function,
    descriptor as record
) as table =>
    let
        transformDescriptor = (key, value) =>
            let
                map = [
                    Name = "NavigationTable.NameColumn",
                    Data = "NavigationTable.DataColumn",
                    Tags = "NavigationTable.TagsColumn",
                    ItemKind = "NavigationTable.ItemKindColumn",
                    ItemName = "Preview.DelayColumn",
                    IsLeaf = "NavigationTable.IsLeafColumn"
                ]
            in
                if value is list
                    then [Name=value{0}, Ctor=value{1}, MetadataName = Record.FieldOrDefault(map, key)]
                    else [Name=key, Ctor=value, MetadataName = Record.FieldOrDefault(map, key)],
        fields = List.Combine({
            List.Transform(keyColumns, (key) => [Name=key, Ctor=(row) => Record.Field(row, key), MetadataName=null]),
            if Record.HasFields(descriptor, {"Data"}) then {}
                else {transformDescriptor("Data", (row) => Function.Invoke(dataCtor, Record.ToList(Record.SelectFields(row, keyColumns))))},
            Table.TransformRows(Record.ToTable(descriptor), each transformDescriptor([Name], [Value]))
        }),
        metadata = List.Accumulate(fields, [], (m, d) => let n = d[MetadataName] in if n = null then m else Record.AddField(m, n, d[Name])),
        tableKeys = List.Transform(fields, each [Name]),
        tableValues = List.Transform(fields, each [Ctor]),
        tableType = Type.ReplaceTableKeys(
            Value.Type(#table(tableKeys, {})),
            {[Columns=keyColumns, Primary=true]}
        ) meta metadata,
        reduceAnd = (ast) => if ast[Kind] = "Binary" and ast[Operator] = "And" then List.Combine({@reduceAnd(ast[Left]), @reduceAnd(ast[Right])}) else {ast},
        matchFieldAccess = (ast) => if ast[Kind] = "FieldAccess" and ast[Expression] = RowExpression.Row then ast[MemberName] else ...,
        matchConstant = (ast) => if ast[Kind] = "Constant" then ast[Value] else ...,
        matchIndex = (ast) => if ast[Kind] = "Binary" and ast[Operator] = "Equals"
            then
                if ast[Left][Kind] = "FieldAccess"
                    then Record.AddField([], matchFieldAccess(ast[Left]), matchConstant(ast[Right]))
                    else Record.AddField([], matchFieldAccess(ast[Right]), matchConstant(ast[Left]))
            else ...,
        lazyRecord = (recordCtor, keys, baseRecord) =>
            let record = recordCtor() in List.Accumulate(keys, [], (r, f) => Record.AddField(r, f, () => (if Record.FieldOrDefault(baseRecord, f, null) <> null then Record.FieldOrDefault(baseRecord, f, null) else Record.Field(record, f)), true)),
        getIndex = (selector, keys) => Record.SelectFields(Record.Combine(List.Transform(reduceAnd(RowExpression.From(selector)), matchIndex)), keys)
    in
        Table.View(null, [
            GetType = () => tableType,
            GetRows = () => #table(tableType, List.Transform(Table.ToRecords(baseTable()), (row) => List.Transform(tableValues, (ctor) => ctor(row)))),
            OnSelectRows = (selector) =>
                let
                    index = try getIndex(selector, keyColumns) otherwise [],
                    default = Table.SelectRows(GetRows(), selector)
                in
                    if Record.FieldCount(index) <> List.Count(keyColumns) then default
                    else Table.FromRecords({
                        index & lazyRecord(
                            () => Table.First(default),
                            List.Skip(tableKeys, Record.FieldCount(index)),
                            Record.AddField([], "Data", () => Function.Invoke(dataCtor, Record.ToList(index)), true))
                        },
                        tableType)
        ]);


Value.WaitFor = (producer as function, interval as function, optional count as number) as any =>
    let
        list = List.Generate(
            () => {0, null},
            (state) => state{0} <> null and (count = null or state{0} < count),
            (state) => if state{1} <> null then {null, state{1}} else {1 + state{0}, Function.InvokeAfter(() => producer(state{0}), interval(state{0}))},
            (state) => state{1})
    in
        List.Last(list);


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