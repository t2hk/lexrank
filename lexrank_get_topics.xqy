xquery version "1.0-ml";

let $map_dir := map:map()

let $__ :=
  for $x in xdmp:directory("/news/", "infinity")
    let $path := fn:tokenize( xdmp:node-uri($x) , "/" )
    let $dir := $path[3]
    return map:put($map_dir, $dir, fn:concat($path[1], "/", $path[2], "/", $path[3], "/"))

(:
let $topics := map:keys($map_dir)
return json:to-array(($topics))
:)

return xdmp:to-json($map_dir)


