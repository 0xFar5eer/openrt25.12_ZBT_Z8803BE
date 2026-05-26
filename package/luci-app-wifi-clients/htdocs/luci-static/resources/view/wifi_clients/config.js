'use strict';
'require form';
'require fs';
'require ui';
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

function restartService() {
	return fs.exec('/etc/init.d/wifi_clients', [ 'restart' ])
		.catch(function(err) {
			ui.addNotification(null, E('p', {}, _('Configuration was saved, but restarting the WiFi Clients refresh service failed: ') + String(err)), 'warning');
		});
}

return view.extend({
	load: function() {
		loadCss(L.resource('view/zbt8803be/zbt-theme.css'));
	},

	render: function() {
		var m, s, o;

		m = new form.Map('wifi-clients', _('WiFi Clients - Settings'), _('Add one router entry per WiFi router you want included in the dashboard output. Remote routers must be reachable over SSH from this router using the configured SSH key. For accurate device names, create DHCP static hosts for known clients and disable private or rotating MAC addresses on devices where long-term identity matters.'));

		s = m.section(form.NamedSection, 'general', 'general', _('General settings'));
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Enable automatic refresh'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'network_title', _('Network title'));
		o.default = _('WiFi network');
		o.rmempty = false;

		o = s.option(form.Value, 'cache_file', _('Cache file'));
		o.default = '/tmp/wifi-clients-cache.json';
		o.datatype = 'file';
		o.rmempty = false;

		o = s.option(form.Value, 'cache_max_age', _('Cache max age seconds'));
		o.datatype = 'uinteger';
		o.default = '60';
		o.rmempty = false;

		o = s.option(form.Value, 'refresh_interval', _('Refresh interval seconds'));
		o.datatype = 'range(30,3600)';
		o.default = '30';
		o.rmempty = false;

		o = s.option(form.Value, 'ssh_key', _('SSH key path'));
		o.default = '/root/.ssh/id_dropbear';
		o.datatype = 'file';
		o.rmempty = false;

		o = s.option(form.Value, 'ssh_connect_timeout', _('SSH connect timeout seconds'));
		o.datatype = 'range(1,30)';
		o.default = '3';
		o.rmempty = false;

		s = m.section(form.GridSection, 'router', _('Routers'), _('Use host localhost for the router running this firmware. For other routers, enter a hostname or IP address and authorize this router\'s SSH public key on the remote router. Setup scripts can also write these same UCI router sections.'));
		s.addremove = true;
		s.anonymous = false;
		s.nodescriptions = true;

		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'name', _('Name'));
		o.placeholder = _('Main Router');
		o.rmempty = false;

		o = s.option(form.Value, 'label', _('Display label'));
		o.placeholder = _('Main Router');
		o.rmempty = false;

		o = s.option(form.Value, 'host', _('Host'));
		o.placeholder = 'localhost';
		o.datatype = 'or(host,ipaddr)';
		o.rmempty = false;

		o = s.option(form.Value, 'sort_order', _('Sort order'));
		o.datatype = 'uinteger';
		o.default = '100';
		o.rmempty = false;

		return m.render().then(function(node) {
			node.classList.add('zbt-app', 'zbt-wifi-clients');
			return node;
		});
	},

	handleSaveApply: function(ev, mode) {
		var fn = L.bind(function() {
			restartService();
			document.removeEventListener('uci-applied', fn);
		});

		document.addEventListener('uci-applied', fn);
		this.super('handleSaveApply', [ ev, mode ]);
	},

	handleSave: function(ev) {
		return this.super('handleSave', [ ev ])
			.then(restartService);
	}
});
