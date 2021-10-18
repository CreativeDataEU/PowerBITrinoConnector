// Use this file to write queries to test your data connector
let
    result = Trino.Contents("localhost",8080),
    withRowCount = Table.AddIndexColumn(result, "Index")   
in
    withRowCount