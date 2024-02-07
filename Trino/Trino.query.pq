// Use this file to write queries to test your data connector
let
    result = Trino.Contents("localhost",8080),
    //result = Trino.Contents("localhost",8080,"Hive","TrinoPBI",5,100,"Select 1"),
    withRowCount = Table.AddIndexColumn(result, "Index")   
in
    withRowCount