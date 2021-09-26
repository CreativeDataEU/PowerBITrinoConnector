// Use this file to write queries to test your data connector
let
    result = Trino.Contents("https://DESKTOP-7J3798C:8443"),
    withRowCount = Table.AddIndexColumn(result, "Index")   
in
    withRowCount