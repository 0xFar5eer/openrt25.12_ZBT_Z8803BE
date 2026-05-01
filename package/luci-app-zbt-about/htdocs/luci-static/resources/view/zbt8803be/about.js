'use strict';
'require view';
'require rpc';
'require fs';

/*
 * luci-app-zbt-about - read-only "About this build" page.
 *
 * Shows the build version, kernel, GitHub releases URL, and credits to
 * the upstream contributors who made this firmware possible.
 */

const RELEASES_URL = 'https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE/releases';
const REPO_URL     = 'https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE';
const ISSUES_URL   = 'https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE/issues';
const CONTACT_URL  = 'https://t.me/Far5eer';

const callSystemBoard = rpc.declare({
	object: 'system',
	method: 'board',
	expect: { }
});

const callSystemInfo = rpc.declare({
	object: 'system',
	method: 'info',
	expect: { }
});

function row(label, value) {
	return E('div', { 'class': 'cbi-value' }, [
		E('label', { 'class': 'cbi-value-title' }, label),
		E('div', { 'class': 'cbi-value-field' }, value)
	]);
}

function link(href, text) {
	return E('a', {
		'href': href,
		'target': '_blank',
		'rel': 'noopener noreferrer'
	}, text || href);
}

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		return Promise.all([
			callSystemBoard().catch(function() { return {}; }),
			callSystemInfo().catch(function() { return {}; }),
			fs.read('/etc/openwrt_release').catch(function() { return ''; })
		]);
	},

	render: function(data) {
		const board   = data[0] || {};
		const info    = data[1] || {};
		const release = data[2] || '';

		const release_lines = {};
		release.split('\n').forEach(function(l) {
			const m = l.match(/^([A-Z_]+)='?(.*?)'?$/);
			if (m) release_lines[m[1]] = m[2];
		});

		const distrib = release_lines['DISTRIB_DESCRIPTION'] ||
			[ release_lines['DISTRIB_ID'], release_lines['DISTRIB_RELEASE'], release_lines['DISTRIB_REVISION'] ]
			.filter(Boolean).join(' ');

		// Mainline OpenWrt master is heading toward 25.12; until upstream
		// tags 25.12.0 the actual VERSION_NUMBER stays "SNAPSHOT".
		const branch = '25.12-SNAPSHOT (mainline master)';

		const memTotalMiB = info.memory && info.memory.total
			? Math.round(info.memory.total / 1048576)
			: null;

		const credits = [
			[ '@pttuan',
			  ' - upstream OpenWrt board port (',
			  link('https://github.com/openwrt/openwrt/pull/23053', 'openwrt#23053'),
			  '): DT-native fan, GPIO watchdog, thermal cooling maps, modern LED bindings.' ],
			[ link('https://github.com/FUjr/QModem', 'FUjr/QModem'),
			  ' - QModem Next modern JS UI shipped with this build, including the built-in SIM Switch page (', E('code', {}, 'AT+QUIMSLOT'), ').' ],
			[ link('https://github.com/OneB1t/Z8803BE-research', 'OneB1t/Z8803BE-research'),
			  ' - vendor firmware research that documented the dead opkg feeds and phone-home tunnel in stock 21.02-SNAPSHOT.' ],
			[ link('https://openwrt.org', 'OpenWrt mainline'),
			  ' - the underlying distribution this build is based on (no MediaTek vendor feed required).' ],
			[ link('https://github.com/immortalwrt/packages', 'ImmortalWrt'),
			  ' - additional package and LuCI overlays used during build.' ]
		];

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', _('About this build')),
			E('p', _('Custom OpenWrt build for the ZBTLink ZBT-Z8803BE WiFi 7 router.')),
			E('div', { 'class': 'alert-message warning' }, [
				E('strong', _('Community build.')),
				' ',
				_('This firmware is maintained by a single contributor outside of any vendor or OpenWrt Project. Expect rough edges. Bug reports and pull requests are very welcome.')
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', _('Build')),
				row(_('Hostname'),    board.hostname || '?'),
				row(_('Model'),       board.model || '?'),
				row(_('Board'),       (board.board_name || '?')),
				row(_('Distribution'), distrib || '?'),
				row(_('Branch'),       branch),
				row(_('Kernel'),      board.kernel || '?'),
				row(_('System'),      board.system || '?'),
				row(_('Uptime'),      info.uptime ? '%t'.format(info.uptime) : '?'),
				row(_('RAM (total)'), memTotalMiB ? memTotalMiB + ' MiB' : '?')
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', _('Releases')),
				E('p', [
					_('Latest images, manifests, checksums, and bilingual release notes (English / 中文):'),
					E('br'),
					link(RELEASES_URL)
				]),
				E('p', [
					_('Source code:'),
					' ',
					link(REPO_URL)
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', _('Support / contact')),
				E('p', _('PRs and issue reports are very welcome - this is a community build, so please file anything you spot:')),
				row(_('Issues'),  link(ISSUES_URL)),
				row(_('Telegram'), link(CONTACT_URL, '@Far5eer'))
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', _('Credits')),
				E('p', _('This build is a curated package list and small base-files overlay layered on top of mainline OpenWrt. Massive thanks to:')),
				E('ul', {},
					credits.map(function(parts) {
						return E('li', {}, parts);
					})
				),
				E('p', { 'class': 'cbi-section-descr' },
					_('Issues and pull requests welcome on the GitHub repository.'))
			])
		]);
	}
});
