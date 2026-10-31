'use strict';
(() => {
  const markdown = new TextDecoder().decode(Uint8Array.from(atob(markdownBase64), c => c.charCodeAt(0)));
  const article = document.getElementById('rendered');
  const source = document.getElementById('source');
  const previewTab = document.getElementById('preview-tab');
  const sourceTab = document.getElementById('source-tab');
  // Document HTML is untrusted. Only the bundled renderer scripts may execute.
  article.innerHTML = DOMPurify.sanitize(article.innerHTML, {
    USE_PROFILES: { html: true },
    FORBID_TAGS: ['style', 'form', 'button', 'textarea', 'select', 'video', 'audio'],
    FORBID_ATTR: ['style', 'name', 'srcset', 'autofocus'],
    ALLOW_DATA_ATTR: false
  });
  source.querySelector('code').textContent = markdown;
  article.querySelectorAll('a').forEach(link => {
    const href = link.getAttribute('href') || '';
    if (!/^(https?:|mailto:|#)/i.test(href)) link.removeAttribute('href');
    link.removeAttribute('target');
    link.rel = 'noreferrer noopener';
  });
  // Avoid silently fetching tracking images or reading unrelated local files.
  article.querySelectorAll('img').forEach(img => {
    const src = img.getAttribute('src') || '';
    if (!/^data:image\/(png|jpeg|gif|webp);base64,/i.test(src)) {
      const placeholder = document.createElement('span');
      placeholder.className = 'image-placeholder';
      placeholder.textContent = '▧ ' + (img.getAttribute('alt') || 'Image') + ' · image not loaded';
      img.replaceWith(placeholder);
    }
  });
  article.querySelectorAll('a[href^="#"]').forEach(link => link.addEventListener('click', event => {
    event.preventDefault();
    let id; try { id = decodeURIComponent(link.getAttribute('href').slice(1)); } catch { return; }
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
  }));
  const words = markdown.trim() ? markdown.trim().split(/\s+/u).length : 0;
  document.getElementById('reading-time').textContent = words ? Math.max(1, Math.ceil(words / 220)) + ' min read' : '';
  document.getElementById('empty').hidden = Boolean(markdown.trim());
  let previousScroll = [0, 0], currentTab = 0;
  function selectTab(index) {
    previousScroll[currentTab] = window.scrollY; currentTab = index;
    article.hidden = index === 1; source.hidden = index === 0;
    previewTab.setAttribute('aria-selected', String(index === 0));
    sourceTab.setAttribute('aria-selected', String(index === 1));
    window.scrollTo(0, previousScroll[index]);
  }
  previewTab.addEventListener('click', () => selectTab(0));
  sourceTab.addEventListener('click', () => selectTab(1));
  document.querySelector('.tabs').addEventListener('keydown', event => {
    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
      event.preventDefault(); selectTab(currentTab === 0 ? 1 : 0); (currentTab === 0 ? previewTab : sourceTab).focus();
    }
  });
  let fontSize = 16;
  document.getElementById('smaller').addEventListener('click', () => { fontSize = Math.max(12, fontSize - 1); document.documentElement.style.setProperty('--font-size', fontSize + 'px'); });
  document.getElementById('larger').addEventListener('click', () => { fontSize = Math.min(24, fontSize + 1); document.documentElement.style.setProperty('--font-size', fontSize + 'px'); });
  window.peekKitReady = true;
})();
