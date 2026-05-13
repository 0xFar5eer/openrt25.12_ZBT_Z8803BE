'use strict';
'require view';
'require fs';
'require dom';
'require ui';

const SPEEDTEST_CMD = '/usr/sbin/zbt-speedtest-json';
let resultNode = null;
let statusNode = null;
let historyNode = null;
let appConfig = null;
let appHistory = [];

function loadCss(path) {
	const head = document.head || document.getElementsByTagName('head')[0];
	const link = E('link', {
		'rel': 'stylesheet',
		'href': path,
		'type': 'text/css'
	});
	head.appendChild(link);
}

function fmtMbps(v) {
	const n = Number(v || 0);
	if (!n)
		return '?';
	return n.toFixed(n >= 100 ? 1 : 2) + ' Mbps';
}

function fmtBytes(v) {
	const n = Number(v || 0);
	if (n >= 1000000000)
		return (n / 1000000000).toFixed(2) + ' GB';
	if (n >= 1000000)
		return (n / 1000000).toFixed(1) + ' MB';
	if (n >= 1000)
		return (n / 1000).toFixed(1) + ' KB';
	return n + ' B';
}

function fmtTime(epoch) {
	if (!epoch)
		return '?';
	return new Date(epoch * 1000).toLocaleString();
}

function joinSize(down, up) {
	return String(down || '') + ':' + String(up || '');
}

function fmtTransfer(bytes, seconds, connections) {
	return fmtBytes(bytes) + ' in ' + (seconds || '?') + 's, ' + (connections || '?') + ' connections';
}

function parseJson(text) {
	try {
		return JSON.parse(text || '{}');
	} catch (e) {
		return { ok: false, error: String(e), raw: text };
	}
}

function row(label, value) {
	return E('tr', {}, [ E('td', {}, label), E('td', {}, value || '?') ]);
}

function card(title, value, detail, good) {
	const color = good ? '#2e7d32' : '#ef6c00';
	return E('div', { 'style': 'flex:1 1 220px;border:1px solid rgba(0,0,0,0.12);border-radius:8px;padding:1em;background:rgba(127,127,127,0.04)' }, [
		E('div', { 'style': 'font-weight:600;margin-bottom:0.35em' }, title),
		E('div', { 'style': 'font-size:1.8em;font-weight:700;color:' + color }, value),
		detail ? E('div', { 'style': 'opacity:0.75;margin-top:0.35em' }, detail) : ''
	]);
}

function renderInterface(info) {
	if (!info)
		return '?';
	const bits = [];
	if (info.up)
		bits.push(_('up'));
	if (info.proto)
		bits.push(info.proto);
	if (info.device)
		bits.push('device ' + info.device);
	if (info.l3_device)
		bits.push('l3 ' + info.l3_device);
	if (info.ipv4_address && info.ipv4_address.length)
		bits.push(info.ipv4_address.join(', '));
	return bits.join(', ') || '?';
}

function selectedLabel(key) {
	const presets = (appConfig && appConfig.presets) || [];
	for (let i = 0; i < presets.length; i++)
		if (presets[i].key === key)
			return presets[i].label || key;
	return key || _('auto');
}

function renderHistory(history) {
	const rows = (history || []).map(function(item) {
		const server = item.server_sponsor || item.server_name || item.preset_label || item.preset || '?';
		const location = item.server_name ? item.server_name + (item.server_country ? ', ' + item.server_country : '') : (item.server_country || item.country || '?');
		return E('tr', {}, [
			E('td', {}, fmtTime(item.timestamp)),
			E('td', {}, item.country || '?'),
			E('td', {}, item.preset_label || item.preset || '?'),
			E('td', {}, server),
			E('td', {}, location),
			E('td', {}, fmtMbps(item.download_mbps)),
			E('td', {}, fmtMbps(item.upload_mbps)),
			E('td', {}, item.ping_ms ? Number(item.ping_ms).toFixed(1) + ' ms' : '?')
		]);
	});
	const tableRows = [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', {}, _('Time')),
			E('th', {}, _('Country')),
			E('th', {}, _('Preset')),
			E('th', {}, _('Server')),
			E('th', {}, _('Location')),
			E('th', {}, _('Download')),
			E('th', {}, _('Upload')),
			E('th', {}, _('Ping'))
		])
	].concat(rows);

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, _('Previous tests')),
		rows.length ? E('table', { 'class': 'table' }, tableRows) : E('p', { 'class': 'cbi-section-descr' }, _('No previous tests recorded yet.'))
	]);
}

function refreshHistory() {
	return fs.exec_direct(SPEEDTEST_CMD, [ '--history', '--history-limit', '25' ]).then(function(text) {
		const data = parseJson(text);
		appHistory = data.history || [];
		if (historyNode)
			dom.content(historyNode, renderHistory(appHistory));
	}).catch(function() {
		appHistory = [];
		if (historyNode)
			dom.content(historyNode, renderHistory(appHistory));
	});
}

function renderResults(data) {
	if (!data || !Object.keys(data).length)
		return E('div', { 'class': 'cbi-section' }, [
			E('p', { 'class': 'cbi-section-descr' }, _('Choose a country, preset, and test size, then click Run speed test.'))
		]);

	const download = data.download || {};
	const upload = data.upload || {};
	const ping = data.ping || {};
	const route = data.route || {};
	const routeGet = route.route_get || {};
	const requested = data.requested || {};
	const server = data.server || {};
	const warnings = data.warnings || [];
	const tools = data.tools || {};
	const errors = [];
	if (data.error)
		errors.push(data.error);
	if (download.error)
		errors.push(_('Download: ') + download.error);
	if (upload.error)
		errors.push(_('Upload: ') + upload.error);
	if (ping.error)
		errors.push(_('Ping: ') + ping.error);

	return E([], [
		E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Latest result')),
			E('div', { 'style': 'display:flex;flex-wrap:wrap;gap:0.75em' }, [
				card(_('Download'), fmtMbps(download.mbps), download.bytes ? fmtTransfer(download.bytes, download.seconds, download.connections || requested.connections) : '', !!download.ok),
				card(_('Upload'), fmtMbps(upload.mbps), upload.bytes ? fmtTransfer(upload.bytes, upload.seconds, upload.connections || requested.connections) : '', !!upload.ok),
				card(_('Latency'), ping.avg_ms ? Number(ping.avg_ms).toFixed(1) + ' ms' : '?', ping.ok ? 'min ' + (ping.min_ms || '?') + 'ms / max ' + (ping.max_ms || '?') + 'ms' : _('latency unavailable'), !!ping.ok),
				card(_('Engine'), 'Speedtest.net', data.ok ? _('completed') : _('needs attention'), !!data.ok)
			])
		]),
		warnings.length ? E('div', { 'class': 'alert-message warning' }, warnings.join(' | ')) : '',
		errors.length ? E('div', { 'class': 'alert-message error' }, errors.join(' | ')) : '',
		E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Route and request')),
			E('table', { 'class': 'table' }, [
				row(_('Started'), fmtTime(data.started_at)),
				row(_('Duration'), (data.duration_s || 0) + ' s'),
				row(_('Country'), requested.country || '?'),
				row(_('Preset'), selectedLabel(requested.server)),
				row(_('Route device'), routeGet.dev || '?'),
				row(_('Gateway'), routeGet.via || '?'),
				row(_('Source address'), routeGet.src || '?'),
				row(_('WAN status'), renderInterface((data.interfaces || {}).wan)),
				row(_('Requested sample'), fmtBytes(requested.download_bytes) + ' down / ' + fmtBytes(requested.upload_bytes) + ' up'),
				row(_('Multi-connection count'), requested.connections || '?')
			])
		]),
		server.id ? E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Selected server')),
			E('table', { 'class': 'table' }, [
				row(_('Sponsor'), server.sponsor || '?'),
				row(_('Location'), (server.name || '?') + ', ' + (server.country || server.cc || '?')),
				row(_('Server ID'), server.id || '?'),
				row(_('Distance'), server.d ? Number(server.d).toFixed(1) + ' km' : '?'),
				row(_('Latency'), server.latency ? Number(server.latency).toFixed(1) + ' ms' : '?'),
				row(_('Host'), server.host || '?')
			])
		]) : '',
		E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Available tools')),
			E('table', { 'class': 'table' }, [
				row(_('python3'), tools.python3 || _('not installed')),
				row(_('ip'), tools.ip || _('not installed')),
				row(_('ifstatus'), tools.ifstatus || _('not installed'))
			])
		]),
		data.raw ? E('div', { 'class': 'cbi-section' }, [ E('h3', {}, _('Raw output')), E('pre', { 'style': 'white-space:pre-wrap' }, data.raw) ]) : ''
	]);
}

function buildOptions(items, valueFn, labelFn, selectedValue) {
	return (items || []).map(function(item) {
		const value = valueFn(item);
		const attrs = { 'value': value };
		if (String(value) === String(selectedValue))
			attrs.selected = 'selected';
		return E('option', attrs, labelFn(item));
	});
}

function runTest() {
	const sizeParts = (document.getElementById('zbt-speedtest-size').value || '').split(':');
	const country = document.getElementById('zbt-speedtest-country').value.trim() || 'PH';
	const server = document.getElementById('zbt-speedtest-server').value || 'auto';
	const connections = document.getElementById('zbt-speedtest-connections').value || '4';
	const args = [
		'--download-bytes', sizeParts[0] || '25000000',
		'--upload-bytes', sizeParts[1] || '5000000',
		'--country', country,
		'--server', server,
		'--connections', connections,
		'--save'
	];

	if (statusNode)
		dom.content(statusNode, _('running'));
	ui.showModal(_('Running speed test'), [
		E('p', { 'class': 'spinning' }, _('Testing from the router. This may take up to a minute.')),
		E('p', {}, _('Router-based tests can be lower than client-device tests because they use router CPU and a small sample size.'))
	]);

	return fs.exec_direct(SPEEDTEST_CMD, args).then(function(text) {
		const data = parseJson(text);
		ui.hideModal();
		if (statusNode)
			dom.content(statusNode, data.ok ? _('completed') : _('completed with errors'));
		if (resultNode)
			dom.content(resultNode, renderResults(data));
		return refreshHistory();
	}).catch(function(err) {
		ui.hideModal();
		if (statusNode)
			dom.content(statusNode, _('failed'));
		if (resultNode)
			dom.content(resultNode, renderResults({ ok: false, error: err.message || String(err) }));
	});
}

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		loadCss(L.resource('view/zbt8803be/zbt-theme.css'));
		return fs.exec_direct(SPEEDTEST_CMD, [ '--config' ]).then(function(text) {
			appConfig = parseJson(text);
			if (!appConfig.ok)
				appConfig = null;
			return refreshHistory();
		}).catch(function() {
			appConfig = null;
			return refreshHistory();
		});
	},

	render: function() {
		const general = (appConfig && appConfig.general) || {};
		const presets = (appConfig && appConfig.presets) || [ { key: 'auto', label: _('Auto (selected country)'), country: '', mode: 'auto' } ];
		const sizes = (appConfig && appConfig.sizes) || [
			{ label: _('Quick (10 MB down / 2 MB up)'), download_bytes: '10000000', upload_bytes: '2000000' },
			{ label: _('Standard (25 MB down / 5 MB up)'), download_bytes: '25000000', upload_bytes: '5000000' },
			{ label: _('Large (100 MB down / 20 MB up)'), download_bytes: '100000000', upload_bytes: '20000000' }
		];
		const selectedSize = joinSize(general.download_bytes || '25000000', general.upload_bytes || '5000000');

		statusNode = E('span', {}, _('idle'));
		resultNode = E('div', {}, renderResults({}));
		historyNode = E('div', {}, renderHistory(appHistory));
		return E('div', { 'class': 'cbi-map zbt-app zbt-speedtest' }, [
			E('h2', _('Speed Test')),
			E('p', { 'class': 'cbi-section-descr' }, [ _('Engine: Speedtest.net. Status: '), statusNode ]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Run test')),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title', 'for': 'zbt-speedtest-size' }, _('Test size')),
					E('div', { 'class': 'cbi-value-field' }, [
						E('select', { 'id': 'zbt-speedtest-size', 'class': 'cbi-input-select' }, buildOptions(sizes, function(size) {
							return joinSize(size.download_bytes, size.upload_bytes);
						}, function(size) {
							return _(size.label);
						}, selectedSize))
					])
				]),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title', 'for': 'zbt-speedtest-country' }, _('Country')),
					E('div', { 'class': 'cbi-value-field' }, [
						E('input', { 'id': 'zbt-speedtest-country', 'class': 'cbi-input-text', 'value': general.country || 'PH' }),
						E('div', { 'class': 'cbi-value-description' }, _('Used by Auto (selected country). Two-letter country codes are supported, e.g. PH, SG, MY.'))
					])
				]),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title', 'for': 'zbt-speedtest-server' }, _('Preset')),
					E('div', { 'class': 'cbi-value-field' }, [
						E('select', { 'id': 'zbt-speedtest-server', 'class': 'cbi-input-select' }, buildOptions(presets, function(preset) {
							return preset.key;
						}, function(preset) {
							return preset.label || preset.key;
						}, general.preset || 'auto')),
						E('div', { 'class': 'cbi-value-description' }, _('Auto uses the country above. Country presets use Speedtest.net servers in that country. PH presets pin known Globe/Smart endpoints.'))
					])
				]),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title', 'for': 'zbt-speedtest-connections' }, _('Connections')),
					E('div', { 'class': 'cbi-value-field' }, [
						E('select', { 'id': 'zbt-speedtest-connections', 'class': 'cbi-input-select' }, buildOptions([ '1', '2', '4', '8' ], function(v) {
							return v;
						}, function(v) {
							return v === '1' ? _('1 connection') : v + ' ' + _('connections');
						}, general.connections || '4'))
					])
				]),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, ' '),
					E('div', { 'class': 'cbi-value-field' }, [
						E('button', { 'class': 'btn cbi-button-action', 'click': ui.createHandlerFn(this, runTest) }, _('Run speed test'))
					])
				])
			]),
			resultNode,
			historyNode
		]);
	}
});
