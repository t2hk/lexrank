Vue.use(VueTables.ClientTable);
var app_doc = new Vue({
  el: '#app_doc',
  data: {
    doc : "Now loading...",
    summary : "Now summarizing..." 
  },
  mounted() {
    var uri = location.href.split("?uri=")[1];
    axios.get("/lexrank_get_doc.xqy?uri=" + uri)
    .then(response => this.doc = response.data)
  },
  created() {
    var uri = location.href.split("?uri=")[1];
    axios.get("/lexrank_get_summary.xqy?uri=" + uri)
    .then(response => this.summary = response.data)
  }
});

var vm = new Vue({
  el: '#app',
  data: {
      topics : null,
      news_list : [],
      news_list_cols :[
        'date',
        'title'
      ],
      news_list_options:{
        headings: {
          date: '日付',
          title: 'タイトル'
        },
        sortable: [ 'date'],
        texts:{ filterPlaceholder: '検索'}
      }
  },
  mounted() {
    axios.get("/lexrank_get_topics.xqy")
    .then(response => this.topics = response.data)
  },
  methods:{
    get_news_list: function(e) {
       let url = "/lexrank_get_news_list.xqy?news=" + e;
       console.log("url : " + url);
       axios.get(url)
       //.then(response => console.log(response.data))
       .then(response => this.news_list = response.data)
    }
  }
});
