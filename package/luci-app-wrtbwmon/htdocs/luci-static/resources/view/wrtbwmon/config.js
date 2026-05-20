'use strict';
'require form';
'require rpc';
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

var callApplyConfig = rpc.declare({
	object: 'luci.wrtbwmon',
	method: 'apply_config'
});

return view.extend({
	load: function() {
		loadCss(L.resource('view/zbt8803be/zbt-theme.css'));
	},

	render: function() {
		var m, s, o;

		m = new form.Map('wrtbwmon', _('Traffic Statistics - Setup'), _('Traffic monitoring is disabled by default because per-client nftables accounting may reduce Internet or LAN throughput on some routers. Enable it temporarily when you need to find which client is over-consuming traffic, globally or by domain, then disable it again when finished. For best per-device tracking, assign static DHCP leases for known devices so each device keeps the same IP/MAC identity. Also disable private or rotating MAC addresses on Samsung, Apple, and similar clients when you want history to stay grouped correctly.'));

		s = m.section(form.NamedSection, 'general', 'general', _('General settings'));
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Enable traffic monitoring'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Flag, 'domain_tracking', _('Enable domain tracking'), _('Enables DNS query logging and per-device domain counters.'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'db_file', _('Database path'));
		o.value('/etc/wrtbwmon/traffic.db');
		o.default = '/etc/wrtbwmon/traffic.db';
		o.rmempty = false;

		o = s.option(form.Value, 'db_keep_days', _('Traffic retention days'));
		o.datatype = 'uinteger';
		o.default = '90';
		o.rmempty = false;

		o = s.option(form.Flag, 'cleanup_enabled', _('Enable daily cleanup'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'cleanup_inactive_days', _('Inactive device cleanup days'));
		o.datatype = 'uinteger';
		o.default = '90';
		o.rmempty = false;

		o = s.option(form.Value, 'domain_cache_ttl', _('Domain cache TTL seconds'));
		o.datatype = 'uinteger';
		o.default = '604800';
		o.depends('domain_tracking', '1');
		o.rmempty = false;

		o = s.option(form.ListValue, 'dns_backend', _('DNS backend'), _('Auto prefers the local AdGuard Home query log at 127.0.0.1:3000 without API keys when it is available and exposes real client IPs; otherwise it falls back to dnsmasq for general OpenWrt setups.'));
		o.value('auto', _('Auto'));
		o.value('dnsmasq', _('dnsmasq'));
		o.value('adguard', _('AdGuard Home'));
		o.default = 'auto';
		o.depends('domain_tracking', '1');
		o.rmempty = false;

		o = s.option(form.ListValue, 'log_level', _('Log level'));
		o.value('debug', _('Debug'));
		o.value('info', _('Info'));
		o.value('warn', _('Warning'));
		o.value('error', _('Error'));
		o.default = 'info';
		o.rmempty = false;

		return m.render().then(function(node) {
			node.classList.add('zbt-app', 'zbt-traffic');
			return node;
		});
	},

	handleSaveApply: function(ev, mode) {
		var fn = L.bind(function() {
			callApplyConfig();
			document.removeEventListener('uci-applied', fn);
		});

		document.addEventListener('uci-applied', fn);
		this.super('handleSaveApply', [ ev, mode ]);
	},

	handleSave: function(ev) {
		return this.super('handleSave', [ ev ])
			.then(callApplyConfig);
	}
});
