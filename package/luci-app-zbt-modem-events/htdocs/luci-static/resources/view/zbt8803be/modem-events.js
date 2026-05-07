'use strict';
'require view';
'require fs';
'require poll';
'require dom';
'require ui';

const DATA_FILE = '/etc/zbt-modem-events/events.csv';
const LOGGER = '/usr/sbin/zbt-modem-events';
const RANGE_S = 604800;
const LIMIT = 500;

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

const SEVERITY = {
	ok: { emoji: '🟢', color: '#2e7d32', bg: 'rgba(46,125,50,0.12)', label: _('Recovered') },
	info: { emoji: '🔵', color: '#1565c0', bg: 'rgba(21,101,192,0.12)', label: _('Info') },
	warning: { emoji: '🟠', color: '#ef6c00', bg: 'rgba(239,108,0,0.14)', label: _('Warning') },
	danger: { emoji: '🔴', color: '#c62828', bg: 'rgba(198,40,40,0.14)', label: _('Critical') }
};

const TYPE_EMOJI = {
	monitor_check_failed: '⚠️',
	monitor_recovered: '✅',
	monitor_threshold: '🚨',
	monitor_action: '🚨',
	monitor_cooldown: '⏳',
	monitor_no_sim: '📵',
	auto_reboot: '🤖',
	auto_reboot_skipped: '⏭️',
	auto_reboot_failed: '❌',
	manual_reboot: '🧑‍🔧',
	manual_reboot_requested: '🧑‍🔧',
	manual_reboot_completed: '🧑‍🔧',
	reboot_failed: '❌',
	router_restart: '🔄',
	internet_ok: '🟢',
	internet_down: '🔴',
	internet_recovered: '🟢',
	usb: '🔌',
	health: '🩺'
};

function pad2(v) {
	return (v < 10 ? '0' : '') + v;
}

function formatTime(epoch) {
	const d = new Date(epoch * 1000);
	return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes()) + ':' + pad2(d.getSeconds());
}

function csvSplit(line) {
	const out = [];
	let cur = '';
	let quoted = false;
	for (let i = 0; i < line.length; i++) {
		const ch = line.charAt(i);
		if (quoted) {
			if (ch === '"') {
				if (line.charAt(i + 1) === '"') {
					cur += '"';
					i++;
				} else {
					quoted = false;
				}
			} else {
				cur += ch;
			}
		} else if (ch === ',') {
			out.push(cur);
			cur = '';
		} else if (ch === '"') {
			quoted = true;
		} else {
			cur += ch;
		}
	}
	out.push(cur);
	return out;
}

function isInternetEvent(ev) {
	switch (ev.type) {
	case 'router_restart':
	case 'internet_ok':
	case 'internet_down':
	case 'internet_recovered':
	case 'monitor_check_failed':
	case 'monitor_recovered':
	case 'monitor_threshold':
	case 'monitor_action':
	case 'monitor_cooldown':
	case 'monitor_no_sim':
	case 'auto_reboot':
	case 'auto_reboot_skipped':
	case 'auto_reboot_failed':
	case 'manual_reboot':
	case 'manual_reboot_requested':
	case 'manual_reboot_completed':
	case 'reboot_failed':
		return true;
	default:
		return false;
	}
}

function parseEvents(text) {
	const now = Math.floor(Date.now() / 1000);
	const cutoff = now - RANGE_S;
	const lines = String(text || '').trim().split(/\n+/);
	const events = [];

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		if (!line || line.indexOf('epoch,') === 0)
			continue;
		const p = csvSplit(line);
		if (p.length < 7)
			continue;
		const epoch = parseInt(p[0], 10);
		if (!epoch || epoch < cutoff)
			continue;
		const ev = {
			epoch: epoch,
			source: p[1] || '',
			type: p[2] || '',
			severity: p[3] || 'info',
			modem: p[4] || '',
			title: p[5] || '',
			detail: p[6] || ''
		};
		if (!isInternetEvent(ev))
			continue;
		events.push(ev);
	}

	return events.sort(function(a, b) { return b.epoch - a.epoch; }).slice(0, LIMIT);
}

function severityInfo(severity) {
	return SEVERITY[severity] || SEVERITY.info;
}

function eventEmoji(ev) {
	return TYPE_EMOJI[ev.type] || severityInfo(ev.severity).emoji;
}

function eventStyle(ev) {
	const sev = severityInfo(ev.severity);
	return 'border-left:4px solid ' + sev.color + ';background:' + sev.bg;
}

function issueStarts(ev) {
	if (ev.type === 'internet_down' || ev.type === 'monitor_check_failed' || ev.type === 'monitor_threshold')
		return true;
	return false;
}

function recoveryEnds(ev) {
	if (ev.type === 'internet_ok' || ev.type === 'internet_recovered' || ev.type === 'monitor_recovered')
		return true;
	return false;
}

function eventLabel(ev) {
	if (ev.type === 'internet_ok')
		return _('OK');
	if (ev.type === 'router_restart')
		return _('Router restart');
	if (ev.type === 'manual_reboot_completed')
		return _('Completed');
	if (recoveryEnds(ev))
		return _('Recovered');
	return severityInfo(ev.severity).label;
}

function estimatedDowntime(events) {
	const asc = events.slice().sort(function(a, b) { return a.epoch - b.epoch; });
	const ranges = [];
	let start = null;
	const now = Math.floor(Date.now() / 1000);

	asc.forEach(function(ev) {
		if (ev.type === 'router_restart')
			start = null;
		else if (issueStarts(ev) && start === null)
			start = ev.epoch;
		else if (recoveryEnds(ev) && start !== null) {
			ranges.push([ start, ev.epoch ]);
			start = null;
		}
	});

	if (start !== null)
		ranges.push([ start, now ]);

	return ranges.reduce(function(sum, r) {
		return sum + Math.max(0, r[1] - r[0]);
	}, 0);
}

function formatDuration(seconds) {
	seconds = Math.max(0, Math.floor(seconds || 0));
	const days = Math.floor(seconds / 86400);
	seconds %= 86400;
	const hours = Math.floor(seconds / 3600);
	seconds %= 3600;
	const minutes = Math.floor(seconds / 60);
	if (days)
		return days + 'd ' + hours + 'h';
	if (hours)
		return hours + 'h ' + minutes + 'm';
	return minutes + 'm';
}

function counts(events) {
	const out = { total: events.length, danger: 0, warning: 0, ok: 0, monitor: 0, auto: 0, manual: 0, downtime: estimatedDowntime(events) };
	events.forEach(function(ev) {
		if (ev.severity === 'danger') out.danger++;
		else if (ev.severity === 'warning') out.warning++;
		if (ev.type === 'internet_ok' || ev.type === 'internet_recovered' || ev.type === 'monitor_recovered') out.ok++;
		if (ev.source === 'monitor') out.monitor++;
		if (ev.type === 'auto_reboot') out.auto++;
		if (ev.type === 'manual_reboot' || ev.type === 'manual_reboot_requested') out.manual++;
	});
	return out;
}

function renderCard(label, value, emoji, color) {
	return E('div', { 'style': 'min-width:11em;flex:1;padding:1em;border-radius:10px;background:rgba(128,128,128,0.10);border-top:3px solid ' + color }, [
		E('div', { 'style': 'font-size:1.75em;line-height:1' }, emoji),
		E('div', { 'style': 'font-size:1.6em;font-weight:700;margin-top:0.25em' }, String(value)),
		E('div', { 'style': 'opacity:0.75' }, label)
	]);
}

function renderSummary(events) {
	const c = counts(events);
	return E('div', { 'class': 'cbi-section' }, [
		E('h3', _('Last 7 days summary')),
		E('div', { 'style': 'display:flex;flex-wrap:wrap;gap:0.75em' }, [
			renderCard(_('Events'), c.total, '📋', '#607d8b'),
			renderCard(_('Estimated downtime'), formatDuration(c.downtime), '⏱️', '#ad1457'),
			renderCard(_('Monitor checks / actions'), c.monitor, '🛰️', '#1565c0'),
			renderCard(_('Warnings'), c.warning, '🟠', '#ef6c00'),
			renderCard(_('Critical'), c.danger, '🔴', '#c62828'),
			renderCard(_('Auto reboots'), c.auto, '🤖', '#6a1b9a'),
			renderCard(_('Manual reboots'), c.manual, '🧑‍🔧', '#00838f'),
			renderCard(_('OK / recovered'), c.ok, '🟢', '#2e7d32')
		])
	]);
}

function renderEvents(events) {
	const rows = [ E('tr', { 'class': 'tr table-titles' }, [
		E('th', { 'class': 'th' }, _('Time')),
		E('th', { 'class': 'th' }, _('Event')),
		E('th', { 'class': 'th' }, _('Source')),
		E('th', { 'class': 'th' }, _('Modem')),
		E('th', { 'class': 'th' }, _('Details'))
	]) ];

	if (!events.length) {
		rows.push(E('tr', { 'class': 'tr placeholder' }, [
			E('td', { 'class': 'td', 'colspan': 5, 'style': 'text-align:center;padding:1.5em' }, E('em', {}, _('No modem internet events recorded in the last 7 days.')))
		]));
	} else {
		events.forEach(function(ev) {
			const sev = severityInfo(ev.severity);
			rows.push(E('tr', { 'class': 'tr', 'style': eventStyle(ev) }, [
				E('td', { 'class': 'td', 'style': 'white-space:nowrap' }, formatTime(ev.epoch)),
				E('td', { 'class': 'td' }, [
					E('span', { 'style': 'font-size:1.25em;margin-right:0.35em' }, eventEmoji(ev)),
					E('strong', { 'style': 'color:' + sev.color }, ev.title || ev.type),
					E('div', { 'style': 'opacity:0.72;font-size:0.9em' }, eventLabel(ev) + ' · ' + ev.type)
				]),
				E('td', { 'class': 'td' }, ev.source || '-'),
				E('td', { 'class': 'td' }, ev.modem || '-'),
				E('td', { 'class': 'td' }, ev.detail || '-')
			]));
		});
	}

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', _('Recent events')),
		E('table', { 'class': 'table cbi-section-table' }, rows)
	]);
}

function renderContent(events) {
	return E([], [
		E('p', { 'class': 'cbi-section-descr' }, _('This page shows modem internet downtime, recovery, monitor action, and router restart events recorded in the last 7 days. Low-level USB, driver, and startup health noise is hidden from this view.')),
		renderSummary(events),
		renderEvents(events)
	]);
}

function loadData(runSample) {
	const sample = runSample ? fs.exec_direct(LOGGER, [ 'sample' ]).catch(function() { return ''; }) : Promise.resolve('');
	return sample.then(function() {
		return L.resolveDefault(fs.read_direct(DATA_FILE), '');
	});
}

function refresh(runSample) {
	if (statusNode)
		statusNode.textContent = _('Loading...');
	return loadData(runSample).then(function(text) {
		if (contentNode)
			dom.content(contentNode, renderContent(parseEvents(text)));
		if (statusNode)
			statusNode.textContent = _('OK');
	}).catch(function(err) {
		if (statusNode)
			statusNode.textContent = _('Error');
		ui.addNotification(null, E('p', {}, err.message || String(err)), 'danger');
	});
}

return view.extend({
	load: function() {
		loadCss(L.resource('view/zbt8803be/zbt-theme.css'));
		return loadData(true);
	},

	render: function(text) {
		statusNode = E('span', {}, _('OK'));
		contentNode = E('div', {}, renderContent(parseEvents(text)));
		poll.add(function() {
			return refresh(true);
		}, 60);
		return E('div', { 'class': 'cbi-map zbt-app zbt-modem-events' }, [
			E('h2', _('Modem Events')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:0.75em' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function() { return refresh(true); } }, _('Refresh')),
					E('span', {}, [ _('Status'), ': ', statusNode ])
				])
			]),
			contentNode
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
