'use strict';
'require view';
'require form';
'require uci';

return view.extend({
	load: function() {
		return Promise.all([uci.load('qmodem_ttl'), uci.load('qmodem')]);
	},

	render: function() {
		var m = new form.Map('qmodem_ttl', _('TTL Configuration'),
			_('Set TTL independently for each modem. An unchecked modem is not modified by this feature. The selected value sets IPv4 TTL and IPv6 Hop Limit on packets leaving that physical modem, including router-originated traffic. Wired WAN TTL is not modified.'));

		['4_1', '2_1'].forEach(function(id, index) {
			var title = index === 0 ? _('Modem 1') : _('Modem 2');
			var label = uci.get('qmodem', id, 'display_name') ||
				uci.get('qmodem', 'slot_' + id, 'display_name');
			if (label && label !== title) title += ' — ' + label;
			var s = m.section(form.NamedSection, id, 'modem', title);
			s.addremove = false;
			s.description = _('This setting follows the physical slot across reconnects. It does not power on, enable dialing, or redial the modem.');
			var o = s.option(form.Flag, 'enable', _('Enable TTL Modification'));
			o.default = '0';
			o.rmempty = false;
			o = s.option(form.ListValue, 'mode', _('TTL Mode'));
			o.value('auto', _('Automatic (64 / 65)'));
			o.value('manual', _('Custom value'));
			o.default = 'auto';
			o.rmempty = false;
			o.retain = true;
			o.depends('enable', '1');
			o.description = _('Automatic keeps the inherited address-based recommendation: 65 for recognized modem NAT addresses, otherwise 64. It is a heuristic, not a carrier guarantee. Custom values are never changed automatically.');
			o = s.option(form.Value, 'ttl', _('TTL / Hop Limit'));
			o.datatype = 'range(1,255)';
			o.validate = function(section, value) {
				return /^[1-9][0-9]{0,2}$/.test(value) && Number(value) <= 255 ? true :
					_('Enter a whole number from 1 to 255 without leading zeroes.');
			};
			o.default = '64';
			o.placeholder = '64';
			o.rmempty = false;
			o.retain = true;
			o.depends({ enable: '1', mode: 'manual' });
			o.description = _('Use a value from 1 to 255. The two modems can use different values.');
		});

		var notes = m.section(form.NamedSection, 'main', 'main', _('Important Notes'));
		var warning = notes.option(form.DummyValue, '_notes');
		warning.cfgvalue = function() {
			return _('Enabling either modem’s TTL modification disables software and hardware flow offloading globally so packets pass through the TTL rules. This may reduce routing performance. Disabling both removes these TTL rules; offloading is not automatically re-enabled. Save & Apply changes firewall rules only, without restarting either modem. Upgraded global settings are migrated; old standalone TTL files are preserved in /etc/qmodem-ttl-backup.');
		};
		return m.render();
	}
});
