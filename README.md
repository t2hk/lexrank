# LexRank implementation using MarkLogic10 CNTK 
This is the LexRank implementation for text summarization using CNTK of MarkLogic10.

## Overview
This is the LexRank implementation for text summarization using CNTK of MarkLogic10.
The word2vec is used for text vectorization.
This program is implemented in XQuery.

## Requirements 

* MarkLogic10 with GPU

If you run as a web application, you need:
* vue.js(https://jp.vuejs.org/index.html)
* axios(https://github.com/axios/axios)
* vue-table-2(https://github.com/matfish2/vue-tables-2)
* bootstrap(https://getbootstrap.com/)

# How to use
1. Load files you want to summarize into the MarkLogic.
   - The contents files are into ./news directory
   - See news_load.sh

2. Load word2vec onnx model and the vocabulary file into the MarkLogic. 
   
   - See https://github.com/t2hk/marklogic_cntk_word2vec

3. Load this project files(xqy, html, js) into the module database of the MarkLogic.

4. Get the required libs and load into the module database of the MarkLogic.

   - Javascript files are into ./js directory.
   - CSS files are into ./css directory.
   
5. Access to the lexrank.html via the MarkLogic HTTP server.
