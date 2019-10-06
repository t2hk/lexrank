xquery version "1.0-ml";

let $path := xdmp:get-request-url()
let $doc_uri := fn:tokenize($path, "=")[2]

return fn:doc($doc_uri)
