'use strict';
'require fs';
'require poll';
'require view';

function loadCss(path) {
    var head = document.head || document.getElementsByTagName('head')[0];
    var link = E('link', {
        'rel': 'stylesheet',
        'href': path,
        'type': 'text/css'
    });
    head.appendChild(link);
}

function errorHtml(err) {
    var msg = String(err).replace(/[&<>"']/g, function(ch) {
        return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch];
    });
    return '<!doctype html><html><body style="font-family:sans-serif;padding:24px"><h2>WiFi Clients unavailable</h2><p>' + msg + '</p></body></html>';
}

function loadPage() {
    return fs.exec_direct('/usr/sbin/wifi-clients-page').catch(errorHtml);
}

function renderPage(node, html) {
    var style = html.match(/<style[^>]*>([\s\S]*?)<\/style>/i);
    var body = html.match(/<body[^>]*>([\s\S]*?)<\/body>/i);
    var target = node.shadowRoot || node;
    var rootSelector = node.shadowRoot ? ':host' : '.wifi-clients-inline';
    var css = style ? style[1].replace(/(^|[,{]\s*)body(?=\s*[,{])/g, '$1' + rootSelector) : '';
    var content = (css ? '<style>' + css + '</style>' : '') + (body ? body[1] : html);
    target.innerHTML = content;
}

return view.extend({
    load: function() {
        loadCss(L.resource('view/zbt8803be/zbt-theme.css'));
        return loadPage();
    },

    render: function(html) {
        var node = E('div', { 'class': 'wifi-clients-inline zbt-app zbt-wifi-clients' });
        if (node.attachShadow)
            node.attachShadow({ mode: 'open' });
        renderPage(node, html);
        poll.add(function() {
            return loadPage().then(function(updated) {
                renderPage(node, updated);
            });
        }, 10);
        return node;
    },
    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
