'use strict';
'require view';
'require fs';
'require poll';
'require dom';

const HEALTH_CMD = '/usr/sbin/zbt-health-json';
let contentNode = null;
let statusNode = null;

function loadCss(path) {
	const head = document.head || document.getElementsByTagName('head')[0];
	const link = E('link', {
		'rel': 'stylesheet',
		'href': path,
		'type': 'text/css'
	});
	head.appendChild(link);
}

function pctValue(v) {
	const n = parseInt(String(v || '0').replace('%', ''), 10);
	return isNaN(n) ? 0 : n;
}

function fmtKiB(kb) {
	const n = Number(kb || 0);
	if (n >= 1048576)
		return (n / 1048576).toFixed(1) + ' GiB';
	if (n >= 1024)
		return (n / 1024).toFixed(1) + ' MiB';
	return n + ' KiB';
}

function fmtDuration(s) {
	s = Number(s || 0);
	const d = Math.floor(s / 86400);
	s %= 86400;
	const h = Math.floor(s / 3600);
	s %= 3600;
	const m = Math.floor(s / 60);
	if (d)
		return '%dd %dh %dm'.format(d, h, m);
	if (h)
		return '%dh %dm'.format(h, m);
	return '%dm'.format(m);
}

function ratio(used, total) {
	used = Number(used || 0);
	total = Number(total || 0);
	if (!total)
		return 0;
	return Math.round((used / total) * 100);
}

function colorForPct(p) {
	if (p >= 90)
		return '#c62828';
	if (p >= 75)
		return '#ef6c00';
	return '#2e7d32';
}

function card(title, value, detail, pct) {
	const color = colorForPct(Number(pct || 0));
	return E('div', { 'style': 'flex:1 1 220px;border:1px solid rgba(0,0,0,0.12);border-radius:8px;padding:1em;background:rgba(127,127,127,0.04)' }, [
		E('div', { 'style': 'font-weight:600;margin-bottom:0.35em' }, title),
		E('div', { 'style': 'font-size:1.8em;font-weight:700;color:%s'.format(color) }, value),
		detail ? E('div', { 'style': 'opacity:0.75;margin-top:0.35em' }, detail) : ''
	]);
}

function row(label, value) {
	return E('tr', {}, [ E('td', {}, label), E('td', {}, value) ]);
}

function table(title, rows) {
	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, title),
		E('table', { 'class': 'table' }, rows)
	]);
}

function parseHealth(text) {
	try {
		return JSON.parse(text || '{}');
	} catch (e) {
		return {};
	}
}

function renderHealth(h) {
	const fsinfo = h.filesystems || {};
	const overlay = fsinfo.overlay || {};
	const root = fsinfo.root || {};
	const tmp = fsinfo.tmp || {};
	const mem = h.memory || {};
	const swap = h.swap || {};
	const conntrack = h.conntrack || {};
	const hotspots = h.storage_hotspots || {};
	const memUsed = Math.max(0, Number(mem.total_kb || 0) - Number(mem.available_kb || 0));
	const memPct = ratio(memUsed, mem.total_kb);
	const overlayPct = pctValue(overlay.used_pct);
	const rootPct = pctValue(root.used_pct);
	const tmpPct = pctValue(tmp.used_pct);
	const connPct = ratio(conntrack.count, conntrack.max);

	return E([], [
		E('p', { 'class': 'cbi-section-descr' }, _('Current router health snapshot. Values refresh automatically and do not write history to overlay.')),
		E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Health summary')),
			E('div', { 'style': 'display:flex;flex-wrap:wrap;gap:0.75em' }, [
				card(_('Overlay'), overlay.used_pct || '?', '%s used, %s free'.format(fmtKiB(overlay.used_kb), fmtKiB(overlay.available_kb)), overlayPct),
				card(_('RAM'), memPct + '%', '%s used, %s available'.format(fmtKiB(memUsed), fmtKiB(mem.available_kb)), memPct),
				card(_('Root filesystem'), root.used_pct || '?', '%s used, %s free'.format(fmtKiB(root.used_kb), fmtKiB(root.available_kb)), rootPct),
				card(_('Connections'), connPct + '%', '%s / %s conntrack entries'.format(conntrack.count || 0, conntrack.max || 0), connPct)
			])
		]),
		table(_('System'), [
			row(_('Uptime'), fmtDuration(h.uptime)),
			row(_('Load average'), h.loadavg || '?')
		]),
		table(_('Storage / overlay'), [
			row(_('Overlay'), '%s used of %s (%s), %s free'.format(fmtKiB(overlay.used_kb), fmtKiB(overlay.total_kb), overlay.used_pct || '?', fmtKiB(overlay.available_kb))),
			row(_('Root filesystem'), '%s used of %s (%s), %s free'.format(fmtKiB(root.used_kb), fmtKiB(root.total_kb), root.used_pct || '?', fmtKiB(root.available_kb))),
			row(_('Temporary filesystem'), '%s used of %s (%s), %s free'.format(fmtKiB(tmp.used_kb), fmtKiB(tmp.total_kb), tmp.used_pct || '?', fmtKiB(tmp.available_kb)))
		]),
		table(_('RAM'), [
			row(_('Memory total'), fmtKiB(mem.total_kb)),
			row(_('Memory used'), fmtKiB(memUsed)),
			row(_('Memory available'), fmtKiB(mem.available_kb)),
			row(_('Swap total'), fmtKiB(swap.total_kb)),
			row(_('Swap free'), fmtKiB(swap.free_kb))
		]),
		table(_('Overlay write hotspots'), [
			row(_('/var/log'), fmtKiB(hotspots.var_log_kb)),
			row(_('AdGuardHome work directory'), fmtKiB(hotspots.adguard_work_kb)),
			row(_('AdGuardHome statistics database'), fmtKiB(hotspots.adguard_stats_kb)),
			row(_('AdGuardHome disk query log'), fmtKiB(hotspots.adguard_querylog_kb)),
			row(_('AdGuardHome log files'), fmtKiB(hotspots.adguard_log_kb)),
			row(_('Traffic Statistics database'), fmtKiB(hotspots.wrtbwmon_db_kb)),
			row(_('Traffic Statistics directory'), fmtKiB(hotspots.wrtbwmon_dir_kb)),
			row(_('Modem Events store'), fmtKiB(hotspots.modem_events_kb)),
			row(_('Temperature store'), fmtKiB(hotspots.temperature_kb))
		])
	]);
}

function loadHealth() {
	return L.resolveDefault(fs.exec_direct(HEALTH_CMD, []), '').then(parseHealth);
}

function refresh() {
	return loadHealth().then(function(h) {
		if (contentNode)
			dom.content(contentNode, renderHealth(h));
		if (statusNode)
			dom.content(statusNode, _('Updated'));
	});
}

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		loadCss(L.resource('view/zbt8803be/zbt-theme.css'));
		return loadHealth();
	},

	render: function(data) {
		statusNode = E('span', {}, _('OK'));
		contentNode = E('div', {}, renderHealth(data));
		poll.add(refresh, 15);
		return E('div', { 'class': 'cbi-map zbt-app zbt-health' }, [
			E('h2', _('Router Health')),
			E('p', { 'class': 'cbi-section-descr' }, [ _('Status: '), statusNode ]),
			contentNode
		]);
	}
});
