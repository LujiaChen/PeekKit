// Independent, bounded lexical highlighting. Emits escaped text and fixed span classes only.
function peekEscape(value) { return String(value).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;'); }
function peekHighlight(source, language) {
  if (source.length > 65536 || !/^(swift|javascript|js|typescript|ts|json|python|py|bash|sh|shell|c|cpp|css)$/.test(language)) return peekEscape(source);
  const keywords = new Set('let var func return import class struct enum protocol extension if else guard switch case default for while in try catch throw throws async await actor public private static final true false nil null const function new typeof export from def lambda with as pass None True False int void auto include'.split(' '));
  let out='', i=0;
  while(i < source.length) {
    const begin=i, ch=source[i]; let kind='';
    if (ch==='"' || ch==="'") { kind='string'; i++; while(i<source.length) { if(source[i]==='\\') {i=Math.min(i+2,source.length);continue;} if(source[i++]===ch) break; } }
    else if (source.slice(i,i+2)==='//' || (ch==='#' && /^(python|py|bash|sh|shell)$/.test(language))) {kind='comment';while(i<source.length && source[i]!=='\n')i++;}
    else if(source.slice(i,i+2)==='/*') {kind='comment';i+=2;while(i<source.length && source.slice(i,i+2)!=='*/')i++;i=Math.min(source.length,i+2);}
    else if(/[A-Za-z_$]/.test(ch)) { i++;while(i<source.length && /[A-Za-z0-9_$]/.test(source[i]))i++;if(keywords.has(source.slice(begin,i)))kind='keyword'; }
    else if(/[0-9]/.test(ch)) {kind='number';i++;while(i<source.length && /[0-9.a-fA-FxX_]/.test(source[i]))i++;}
    else i++;
    const value=peekEscape(source.slice(begin,i));out += kind ? '<span class="tok-'+kind+'">'+value+'</span>' : value;
  }
  return out;
}
