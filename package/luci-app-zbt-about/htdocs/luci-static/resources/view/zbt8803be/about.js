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
const BUILD_CHANNEL = 'ZBT-Z8803BE community build';
const OPENWRT_BASE = 'OpenWrt main branch with MediaTek kernel 6.18';

function loadCss(path) {
	const head = document.head || document.getElementsByTagName('head')[0];
	const link = E('link', {
		'rel': 'stylesheet',
		'href': path,
		'type': 'text/css'
	});
	head.appendChild(link);
}

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

function list(items) {
	return E('ul', { 'style': 'margin:0.75em 0 0 1.25em;padding-left:1.25em;max-width:100%' },
		items.map(function(item) {
			return E('li', { 'style': 'margin:0.35em 0;line-height:1.45;overflow-wrap:anywhere' }, item);
		}));
}

function card(title, items) {
	return E('div', { 'class': 'cbi-section', 'style': 'overflow-wrap:anywhere' }, [
		E('h3', title),
		list(items)
	]);
}

function creditGrid(items) {
	const rows = [];
	items.forEach(function(item) {
		rows.push(E('div', { 'class': 'zbt-credit-row' }, [
			E('span', { 'class': 'zbt-credits-name' }, item[0]),
			E('span', { 'class': 'zbt-credit-separator' }, ' - '),
			E('span', { 'class': 'zbt-credits-text' }, item[1])
		]));
	});
	return E('div', { 'class': 'zbt-credits-list' }, rows);
}

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		loadCss(L.resource('view/zbt8803be/zbt-theme.css'));
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

		const branch = 'OpenWrt main';

		const featureGroups = [
			[ _('Platform / board support'), [
				_('Mainline OpenWrt main base for ZBTLink ZBT-Z8803BE, target mediatek/filogic, kernel 6.18, no MediaTek vendor feed required.'),
				_('Board DTS/image profile, NAND sysupgrade support, LED/network/GPIO switch defaults, modem LED services, APK feed defaults, shell/banner defaults, and first-boot LuCI defaults.'),
				_('WiFi 7 tri-band defaults: 2.4 GHz ch11/EHT20, 5 GHz ch149/EHT80, 6 GHz ch37/EHT160, country PH, no firmware-side txpower/channel clamps.')
			] ],
			[ _('LuCI / observability'), [
				_('Top-level About page, Argon dark theme/config, HTTPS LuCI, package manager, curated Services menu ordering, and direct Services views for WiFi history and System Statistics.'),
				_('Shared ZBT LuCI theme applied across custom firmware apps with consistent cards, tables, buttons, Traffic Statistics filters, and inset About credits.'),
				_('ZBT Health page with overlay/storage/RAM/conntrack/uptime checks plus write-hotspot visibility for wrtbwmon and AdGuard Home data.'),
				_('Temperature monitor with tmpfs history, max-temperature avoid-limit overlays, 7-level fan policy, and modem/WiFi/SoC sensor summaries.'),
				_('Modem Events history with router restart boundaries, recovery counters, downtime estimates, qmodem monitor actions, and internet probe state.')
			] ],
			[ _('Traffic, DNS, and QoS'), [
				_('wrtbwmon Traffic Statistics with daily SQLite schema, device traffic, live speed stats, per-device domain views, top domains, domain tracking defaults, and warning messages when monitoring/domain data is disabled or empty.'),
				_('AdGuard Home integration with bounded memory query log/statistics settings and robust query-log parsing for current answer/value/client_info formats.'),
				_('QoSmate remains available for manual tuning, but defaults stay disabled for the public wired-WAN profile.')
			] ],
			[ _('Modem and WAN resilience'), [
				_('QModem Next JS UI with SMS, Monitor, AT Debug, modem controls, and opt-in cellular monitoring helpers.'),
				_('QMI/MBIM/NCM/MHI/USB modem stack with sms_tool_q, tom_modem, quectel-CM-5G-M, modem event hooks, and WAN-only defaults: wired WAN metric 10, dormant cellular metric 200 with no default route.'),
				_('On this exact Z8803BE-T variant SIM1 is wired to modem1 and SIM2 is wired to modem2, so SIM switching is intentionally disabled.')
			] ],
			[ _('Included package families'), [
				_('Network services: WireGuard, DDNS, AdGuard Home, youtubeUnblock, Samba, Diskman, statistics, wifihistory, MLO tooling, diagnostics, and CLI utilities.'),
				_('Developer/runtime convenience: git, git-http, and a BusyBox-compatible install shim for setup scripts and ad-hoc deployments.'),
				_('Custom ZBT LuCI apps: About, Health, Temperature, Modem Events, WiFi Clients, and Traffic Statistics.'),
				_('Build overlays: FUjr/QModem, selected ImmortalWrt packages/LuCI overlays, vendored autocore/cpufreq/QoSmate/MLO tooling, and board-specific base-files customizations.')
			] ],
			[ _('Fixes and hardening vs stock/vendor firmware'), [
				_('Moves away from old vendor 21.02-SNAPSHOT behavior and dead vendor feeds toward current OpenWrt main.'),
				_('Hardened modem monitoring to avoid no-SIM reset loops, early boot restart storms, and DNS-dependent false failures.'),
				_('BusyBox-compatible deployments avoid GNU install assumptions; setup scripts copy files with cp/chmod and firmware includes an install compatibility shim.'),
				_('Improved LuCI UX: no duplicate About alias under System, no recursive WiFi Clients iframe, clear Traffic Statistics warnings, and safer direct Services menu placement.'),
				_('Detailed crash flight recording is intentionally not built into the public firmware; private investigation tooling is installed only by setup scripts after flashing.')
			] ]
		];

		const memTotalMiB = info.memory && info.memory.total
			? Math.round(info.memory.total / 1048576)
			: null;

		const credits = [
			[ link('https://github.com/pttuan', '@pttuan'),
			  [ _('upstream OpenWrt board port'), ' (',
			  link('https://github.com/openwrt/openwrt/pull/23053', 'openwrt#23053'),
			  '): ', _('DT-native fan, GPIO watchdog, thermal cooling maps, modern LED bindings.') ] ],
			[ link('https://github.com/sjanulonoks', '@sjanulonoks'),
			  _('fan-control suggestion and general release testing that helped tune and validate this ZBT-Z8803BE build.') ],
			[ link('https://github.com/FUjr/QModem', 'FUjr/QModem'),
			  _('QModem Next modern JS UI shipped with this build; on this exact Z8803BE-T variant SIM1 is wired to modem1 and SIM2 is wired to modem2, so SIM switching is disabled.') ],
			[ link('https://github.com/OneB1t/Z8803BE-research', 'OneB1t/Z8803BE-research'),
			  _('vendor firmware research that documented the dead opkg feeds and phone-home tunnel in stock 21.02-SNAPSHOT.') ],
			[ link('https://openwrt.org', 'OpenWrt mainline'),
			  _('the underlying distribution this build is based on (no MediaTek vendor feed required).') ],
			[ link('https://github.com/immortalwrt/packages', 'ImmortalWrt'),
			  _('additional package and LuCI overlays used during build.') ]
		];

		const sections = [
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
				row(_('Build channel'), BUILD_CHANNEL),
				row(_('OpenWrt base'), OPENWRT_BASE),
				row(_('Branch'),       branch),
				row(_('Kernel'),      board.kernel || '?'),
				row(_('System'),      board.system || '?'),
				row(_('Uptime'),      info.uptime ? '%t'.format(info.uptime) : '?'),
				row(_('RAM (total)'), memTotalMiB ? memTotalMiB + ' MiB' : '?')
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', _('What is added vs stock OpenWrt')),
				E('p', _('This page is the canonical in-firmware summary. Release notes use the same categories and add image checksums, flash instructions, and per-release validation.'))
			])
		].concat(featureGroups.map(function(group) {
			return card(group[0], group[1]);
		}), [
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

			E('div', { 'class': 'cbi-section', 'style': 'overflow-wrap:anywhere' }, [
				E('h3', _('Credits')),
				E('p', _('This build is a curated package list and small base-files overlay layered on top of mainline OpenWrt. Massive thanks to:')),
				creditGrid(credits),
				E('p', { 'class': 'cbi-section-descr' },
					_('Issues and pull requests welcome on the GitHub repository.'))
			])
		]);

		return E('div', { 'class': 'cbi-map zbt-app zbt-about' }, sections);
	}
});
