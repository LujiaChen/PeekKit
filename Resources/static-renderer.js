// Runs in JavaScriptCore, which has no DOM, network, or file APIs.
function renderMarkdownSafely(source) {
  const escape = value => String(value || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  const parser = new marked.Marked({ gfm: true });
  parser.use({ renderer: {
    html(token) { return escape(token.text); },
    link(token) {
      const text = this.parser.parseInline(token.tokens);
      if (!/^(https?:\/\/|mailto:|#)/i.test(token.href)) return text;
      return '<a rel="noreferrer noopener" href="' + escape(token.href) + '">' + text + '</a>';
    },
    image(token) {
      if (/^data:image\/(png|jpeg|gif|webp);base64,[A-Za-z0-9+/=\s]+$/i.test(token.href)) {
        return '<img alt="' + escape(token.text) + '" src="' + escape(token.href) + '">';
      }
      return '<span class="image-placeholder">▧ ' + escape(token.text || 'Image') + ' · image not loaded</span>';
    }
  }});
  return parser.parse(source);
}
