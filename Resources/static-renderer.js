// Runs in JavaScriptCore with no DOM, network or file APIs; HTML is escaped, never executed.
function renderMarkdownSafely(source) {
  const escape=peekEscape, ids=new Set(), toc=[];
  const parser=new marked.Marked({gfm:true});
  parser.use({renderer:{
    html(token) { return escape(token.text); },
    heading(token) {
      const plain=token.text.replace(/<[^>]*>/g,'').replace(/[*_`~]/g,'');
      const root=plain.toLowerCase().trim().replace(/[^\p{L}\p{N}\s_-]/gu,'').replace(/\s/g,'-') || 'section';
      let id='pk-'+root, n=1;while(ids.has(id))id='pk-'+root+'-'+n++;
      ids.add(id);if(toc.length<100)toc.push({id,text:plain,depth:token.depth});
      return '<h'+token.depth+' id="'+escape(id)+'">'+this.parser.parseInline(token.tokens)+'</h'+token.depth+'>\n';
    },
    code(token) { const lang=(token.lang||'').split(/\s/)[0].toLowerCase();return '<pre><code>'+peekHighlight(token.text,lang)+'</code></pre>\n'; },
    link(token) {
      const text=this.parser.parseInline(token.tokens);
      if(!/^(https?:\/\/|mailto:|#)/i.test(token.href))return text;
      const href=token.href.startsWith('#') ? '#pk-'+token.href.slice(1) : token.href;
      return '<a rel="noreferrer noopener" href="'+escape(href)+'">'+text+'</a>';
    },
    image(token) {
      if(/^data:image\/(png|jpeg|gif|webp);base64,[A-Za-z0-9+/=\s]+$/i.test(token.href)) return '<img alt="'+escape(token.text||'')+'" src="'+escape(token.href)+'">';
      return '<span class="image-placeholder">▧ '+escape(token.text||'Image')+' · image not loaded</span>';
    }
  }});
  const body=parser.parse(source);
  const navigation=toc.length>1 ? '<details class="toc"><summary>Contents</summary><nav aria-label="Table of contents">'+toc.map(h=>'<a class="toc-level-'+h.depth+'" href="#'+escape(h.id)+'">'+escape(h.text)+'</a>').join('')+'</nav></details>' : '';
  return navigation+body;
}
