xquery version "1.0-ml";

(:単語のインデックス値を取得する。:)
declare function local:word-to-index($word as xs:string){
  let $uris :=
  cts:uris((), (), 
    cts:and-query((
      cts:directory-query("/vocab/", "infinity"),
      cts:json-property-value-query("word", $word, "exact"))
    ))
  return fn:doc($uris)/index/number()
};

(:インデックスに対応する単語を取得する。:)
declare function local:index-to-word($index as xs:integer){
  let $uris :=
  cts:uris((), (), 
    cts:and-query((
      cts:directory-query("/vocab/", "infinity"),
      cts:json-property-value-query("index", $index))
    ))
  return fn:doc($uris)/word
};

(: top-k を求める。:)
declare function local:top-k($targets as json:array, $top-k as xs:integer){
  let $input-size := json:array-size($targets)

  let $input-variable := cntk:input-variable(cntk:shape(($input-size)), "float")
  let $top-k := cntk:top-k($input-variable, $top-k)
  let $output-variable := cntk:function-outputs($top-k)

  let $input-value := cntk:batch(cntk:shape(($input-size)), $targets, cntk:gpu(0), "float")
  let $input-value-pair := json:to-array(($input-variable, $input-value))

  let $result := cntk:evaluate($top-k, $input-value-pair, $output-variable , cntk:gpu(0))
  let $rv := cntk:value-to-array($output-variable, $result)
  return $rv
};

(:文書のトークナイズ:)
declare function local:tokenize-doc($uri as xs:string){
  let $doc := fn:doc($uri)
  let $sentences := fn:tokenize($doc, "\n")
  
  let $tokenized_sentences :=
  for $sentence in $sentences
    let $trimed := fn:normalize-space($sentence)
    let $tokenized := cts:tokenize($trimed)
    
    return
      if (fn:count($tokenized) > 0) then json:to-array(($tokenized))
      else ()
  return $tokenized_sentences
};

(:トークナイズされた文章の各単語をインデックス化する。:)
declare function local:convert-sentence-words-to-index($sentence as json:array){
  let $words := json:array-values($sentence)
  let $word_indexes :=
    for $word in $words
      let $index_word := local:word-to-index(xs:string($word))
      
      let $result := 
        if ($index_word[1] > 0) then $index_word[1]
        else 1
      return $result
  return json:to-array(($word_indexes))
};

(: 文章間のCosine距離を取得する。バッチ対応。:)
declare function local:cosine-similarity($source-vectors as json:array, $target-vectors as json:array){
  (: 比較する文章数 :)
  let $SENTENCE_SIZE := json:array-size($target-vectors)
  (: ベクトルサイズ :)
  let $VECTOR_SIZE := json:array-size($source-vectors[1])
  
  (: Cosine類似度モデルの定義 :)
  let $source-input-variable := cntk:input-variable(cntk:shape(($VECTOR_SIZE)), "float")
  let $target-input-variable := cntk:input-variable(cntk:shape(($VECTOR_SIZE)), "float")
  let $cosine-model := cntk:cosine-distance($source-input-variable, $target-input-variable)
  let $output-variable := cntk:function-output($cosine-model)
    
  (: 入力されたデータからバッチ処理データを組み立てる。:)
  let $source-values := for $i in (1 to json:array-size($source-vectors)) return $source-vectors[$i]
  let $target-values := for $i in (1 to json:array-size($target-vectors)) return $target-vectors[$i]
  let $continues := for $i in (1 to $SENTENCE_SIZE) return fn:true()
  
  let $source-bos := cntk:batch-of-sequences(cntk:shape(($VECTOR_SIZE)), json:to-array(($source-values)), $continues, cntk:gpu(0))
  let $target-bos := cntk:batch-of-sequences(cntk:shape(($VECTOR_SIZE)), json:to-array(($target-values)), $continues, cntk:gpu(0))
  let $source-input-pair := json:to-array(($source-input-variable, $source-bos))  
  let $target-input-pair := json:to-array(($target-input-variable, $target-bos))  
  
  let $input-pair := json:to-array(($source-input-pair, $target-input-pair))

  (: 単語のベクトル表現を取得する:)
  let $result := cntk:evaluate($cosine-model, $input-pair, $output-variable, cntk:gpu(0))  
  return cntk:value-to-array($output-variable, $result) 
};

(:全文章間のコサインル距離を求める。:)
declare function local:sentences-cosine-similarity($sentences_vector){
  let $SENTENCE_SIZE := fn:count($sentences_vector)
  
  let $sentence_cosine_sims :=
    for $i in (1 to $SENTENCE_SIZE)
      (:i番目の文章ベクトルを比較元とし、それを比較先の全文章分だけリスト化する :)
      let $source-vectors :=
        for $__ in (1 to $SENTENCE_SIZE)
          return $sentences_vector[$i]  

      return local:cosine-similarity(json:to-array(($source-vectors)), json:to-array(($sentences_vector)))

  return $sentence_cosine_sims
};

declare function local:power-method($cosine_matrix, $N, $p_old){
(:   
  let $N := 5
  let $cosine_matrix := 
    ((1, 2, 3, 4, 5), (1, 2, 3, 4, 5), (1, 2, 3, 4, 5), (1, 2, 3, 4, 5),(1, 2, 3, 4, 5))
  let $p_old := json:to-array((for $__ in (1 to $N) return (1.0 div $N)))
 :)

  let $error_tolerance := 10e-6  
  let $__ := xdmp:log(fn:concat("p_old:", $p_old))
  
  (:::::::::
    p = np.dot(CosineMatrix.T, p_old) の計算
  :::::::::)  
  let $input-variable-cosine-matrix := cntk:input-variable(cntk:shape(($N, $N)), "float")
  let $input-value-cos-mat := cntk:batch(cntk:shape(($N, $N)), json:to-array(($cosine_matrix)), cntk:gpu(0), "float")  
  let $input-pair-cos-mat := json:to-array(($input-variable-cosine-matrix, $input-value-cos-mat))

  let $input-variable-p-old := cntk:input-variable(cntk:shape(($N)), "float")
  let $input-value-p-old := cntk:batch(cntk:variable-shape($input-variable-p-old), json:to-array(($p_old)), cntk:gpu(0), "float")
  let $input-pair-p-old := json:to-array(($input-variable-p-old, $input-value-p-old))
  
  let $input-pair := json:to-array(($input-pair-cos-mat, $input-pair-p-old))

  let $p := cntk:times($input-variable-cosine-matrix, $input-variable-p-old, 1, -1)
  let $p-eval := cntk:evaluate($p, $input-pair, cntk:function-output($p), cntk:gpu(0))
  let $p-value := cntk:value-to-array(cntk:function-output($p), $p-eval)
  let $__ := xdmp:log(fn:concat("p : ", $p-value) )

  return
    (:::::::::::::::
      err = np.linalg.norm(p - p_old) の計算
    :::::::::::::::)
    let $p-minus-p_old := cntk:minus($p, $input-variable-p-old )
    let $p-minus-p_old-eval := cntk:evaluate($p-minus-p_old, $input-pair, cntk:function-output($p-minus-p_old), cntk:gpu(0))
    let $p-minus-p_old-value := cntk:value-to-array(cntk:function-output($p-minus-p_old), $p-minus-p_old-eval)
    let $__ := xdmp:log(fn:concat("p : ", $p-minus-p_old-value) )

    let $L2-norm := cntk:reduce-l2($p-minus-p_old, (cntk:axis(0)))
    let $L2-norm-eval := cntk:evaluate($L2-norm, $input-pair, cntk:function-output($L2-norm), cntk:gpu(0))
    let $err-value := cntk:value-to-array(cntk:function-output($L2-norm), $L2-norm-eval)
    let $__ := xdmp:log(fn:concat("err L2-norm : ", $err-value) )

    return
      if ($err-value[1] < $error_tolerance) then 
        local:power-method($cosine_matrix, $N, $p-value)  
      else $p-value 
};

(:文章間の類似度のマトリクスを算出し、LexRankを算出する。:)
declare function local:get-lex-rank($indexed_sentences as json:array){
  (: 当該モデルで学習した単語数 :)
  let $VOCAB_SIZE := fn:count(cts:uris((), (), cts:directory-query("/vocab/", "infinity") )) + 3
  
  (:学習データの準備:)
  let $model := cntk:function(fn:doc("/model/wiki_w2v_model.onnx")/binary(), cntk:gpu(0), "onnx")
  
  (: モデルの入力パラメータ型 :)
  let $input-variable := cntk:input-variable(cntk:shape((1)), "float")

  (:ターゲットの単語をOne-Hot表現に変換するレイヤー:)
  let $onehot := cntk:one-hot-op($input-variable, $VOCAB_SIZE, fn:false(), cntk:axis(0))

  (: 埋め込みレイヤーの定義 :)
  let $emb-input-variable := cntk:input-variable(cntk:shape(($VOCAB_SIZE)), "float")
  let $emb-map := map:map()
  let $__ := map:put($emb-map, "weight", cntk:constant-value(cntk:function-constants($model)))
  let $emb-layer := cntk:embedding-layer($onehot, $emb-map)

  (: モデルの出力パラメータ型 :)
  let $output-variable := cntk:function-output($emb-layer)

  let $sentences := json:array-values($indexed_sentences)
  
  (:文章のベクトル表現を算出する。:)
  let $sentences_vector := 
    for $indexed_words in $sentences
      (: 入力されたデータからバッチ処理データを組み立てる。 :)
      let $values := for $i in (1 to json:array-size($indexed_words)) return  json:to-array((xs:integer($indexed_words[$i])))
      let $continues := for $i in (1 to json:array-size($indexed_words)) return fn:true()
      let $bos := cntk:batch-of-sequences(cntk:variable-shape($input-variable), json:to-array(($values)), $continues, cntk:gpu(0))
      let $input-value-pair := json:to-array(($input-variable, $bos))

      (: 単語のベクトル表現を取得する :)
      let $_word-vectors := cntk:evaluate($emb-layer, $input-value-pair, $output-variable, cntk:gpu(0))
      let $word-vectors := cntk:value-to-array($output-variable, $_word-vectors)

      (: 取得した単語ベクトルの平均を求め、文章のベクトルとする。 :)
      let $input-mean-variable := cntk:input-variable(cntk:shape((json:array-size($word-vectors))), "float")
      let $vector-mean := cntk:reduce-mean($input-mean-variable, cntk:axis(0))
      let $output-mean-variable := cntk:function-output($vector-mean)    
      let $input-value := cntk:batch(cntk:shape((json:array-size($word-vectors))), json:to-array(($word-vectors)), cntk:gpu(0), "float")  
      let $input-value-pair := json:to-array(($input-mean-variable, $input-value))
      let $_mean-vector := cntk:evaluate($vector-mean, $input-value-pair, $output-mean-variable, cntk:gpu(0))
      return cntk:value-to-array($output-mean-variable, $_mean-vector)
  
  (:文章間のコサイン類似度を算出する。:)
  let $sentences_count := json:array-size($indexed_sentences)
  let $sentences_cos_sim := local:sentences-cosine-similarity($sentences_vector)
  
  let $SENTENCE_THRESHOLD := 0.04
  let $degree := map:map()

  (:::::
     i番目の文章と全文章のコサイン距離を評価する。
     比較先の文章はj番目である。
     degreeはi番目の文章について、関連性の高い文章の数である。
  :::::)
  let $sentences_cosine_matrix :=
    for $sentence_cos_sims at $i in $sentences_cos_sim
      let $__ := map:put($degree, xs:string($i), 0)      
      let $_sentence_cos_sims := json:array-values($sentence_cos_sims)
      let $sentence_cosine_matrix := 
        for $sentence_cos_sim at $j in $_sentence_cos_sims

          (:文書間の類似度が閾値を超えていたら1、超えていなければ0とする。1の場合はdegreeをカウントアップする。:)
          return
            if ($sentence_cos_sim > $SENTENCE_THRESHOLD) then 
              let $current_degree := map:get($degree, xs:string($i))
              let $new_degree := $current_degree + 1
              let $__ := map:put($degree, xs:string($i), $new_degree)
              return 1
            else 0

      return json:to-array(($sentence_cosine_matrix))
        
  (: LexRank を算出する :)
  let $cosine_matrix := 
    for $i in (1 to $sentences_count)
      let $i_degree := map:get($degree, xs:string($i))
      let $_cosine_matrix :=
        for $j in (1 to $sentences_count)
          return $sentences_cosine_matrix[$i][$j] div $i_degree
      return $_cosine_matrix
      
  let $p_old := json:to-array(( for $i in (1 to $sentences_count) return (1.0 div $sentences_count) ))
  let $lex-rank := local:power-method($cosine_matrix, $sentences_count, $p_old)
  
  return $lex-rank 
};

let $path := xdmp:get-request-url()
let $doc_uri := fn:tokenize($path, "=")[2]

(:文書を文章毎にトークナイズする。:)
(:
let $tokenized_sentences := local:tokenize-doc("/news/kaden-channel/kaden-channel-6017943.txt")
:)
let $tokenized_sentences := local:tokenize-doc($doc_uri)

let $indexed_sentences :=
  for $tokenized_sentence in $tokenized_sentences
    return local:convert-sentence-words-to-index($tokenized_sentence)

let $lexrank := local:get-lex-rank(json:to-array(($indexed_sentences)))

let $top-k-result := local:top-k(json:to-array(($lexrank)), 3)

let $top-k-rank := $top-k-result[1][1]
let $top-k-indexes := $top-k-result[2][1]

return
for $i in (1 to fn:count($top-k-indexes))
  let $sentence_index := $top-k-indexes[$i]
  let $summary_sentence := fn:string-join(json:array-values($tokenized_sentences[$sentence_index]), "")

  return fn:concat("[", $sentence_index, "] ", $summary_sentence)
(:
  return fn:concat("[", $sentence_index, "] [",$top-k-rank[$i], "] ", $summary_sentence)
:)

