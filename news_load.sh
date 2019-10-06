HOST=localhost
PORT=8201
USER=admin
PASS=admin
LOAD_FILES_DIR=./news

mlcp.sh import \
-host ${HOST} \
-port ${PORT} -username ${USER} -password ${PASS} \
-input_file_path ${LOAD_FILES_DIR} \
-mode local \
-document_type text \
-output_uri_replace "${LOAD_FILES_DIR},''"
 
