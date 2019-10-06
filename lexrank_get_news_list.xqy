xquery version "1.0-ml";

let $path := xdmp:get-request-url()
let $news_dir := fn:tokenize($path, "=")[2]

let $result :=
for $x in xdmp:directory($news_dir, "infinity")
  let $doc_uri := xdmp:node-uri($x)

  let $contents := fn:tokenize($x, "\n")

  let $date := $contents[2]
  let $title := $contents[3]

  let $object := json:object()
  let $_ := map:put($object,"title",$title)
  let $_ := map:put($object,"date",$date)
  let $_ := map:put($object,"uri",$doc_uri)

  return xdmp:to-json($object)

return json:to-array(($result))
