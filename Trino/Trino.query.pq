// Use this file to write queries to test your data connector
let
    result = Trino.Contents("DESKTOP-7J3798C","8080"),
    withRowCount = Table.AddIndexColumn(result, "Index")   
in
    withRowCount