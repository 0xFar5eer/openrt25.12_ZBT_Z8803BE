'use strict';
'require view';
'require form';
'require uci';
'require ui';
'require fs';
'require rpc';
'require dom';

/*
 * luci-app-mlo - vendor-style MLD records CRUD.
 *
 * Concept:
 *   Each MLD (Multi-Link Device) is a virtual record with name / SSID /
 *   security / key / selected bands. Under the hood it maps to one
 *   wifi-iface section per selected band, all sharing:
 *     - option mld_ap '1'
 *     - option mld_id '<N>'     (same for every band in the MLD)
 *     - matching ssid / encryption / key
 *
 *   The app reads wireless uci, groups wifi-iface sections by
 *   (mld_id, ssid) to derive synthetic MLD records, and lets the user
 *   edit them as a single logical unit. Saves regenerate the
 *   underlying wifi-iface sections atomically.
 */

const BAND_ORDER = [ '2g', '5g', '6g' ];
const BAND_LABEL = {
	'2g': '2.4 GHz',
	'5g': '5 GHz',
	'6g': '6 GHz'
};
const ENC_LABEL = {
	'none': 'Open (no security)',
	'owe':  'OWE (open, encrypted)',
	'psk2': 'WPA2-PSK',
	'sae':  'WPA3-SAE',
	'sae-mixed': 'WPA2/WPA3 mixed'
};

function loadCss(path) {
	const head = document.head || document.getElementsByTagName('head')[0];
	const link = E('link', {
		'rel': 'stylesheet',
		'href': path,
		'type': 'text/css'
	});
	head.appendChild(link);
}

function radiosByBand() {
	/* returns { '2g': 'radio0', '5g': 'radio1', '6g': 'radio2' } */
	const out = {};
	uci.sections('wireless', 'wifi-device').forEach(function (d) {
		const b = d.band;
		if (b && !out[b]) out[b] = d['.name'];
	});
	return out;
}

function loadMlds() {
	/*
	 * OpenWrt's MLO model: a wifi-iface opts into MLO with
	 * `option mlo 1`. Each unique SSID that carries mlo=1 on
	 * multiple bands IS an MLD - there is no explicit "group id",
	 * the link id is the radio index (0/1/2) derived automatically.
	 *
	 * We key MLD records by SSID here so multiple SSIDs (e.g. Home
	 * and Guest) each form their own MLD.
	 */
	const mlds = {};        /* ssid -> MLD record */
	const standalone = [];
	uci.sections('wireless', 'wifi-iface').forEach(function (s) {
		if (s.mode && s.mode !== 'ap') return;
		if (s.mlo == '1' || s.mlo === 1 || s.mlo === true) {
			const key = s.ssid || '(no SSID)';
			if (!mlds[key]) {
				mlds[key] = {
					mld_id: key, /* just for display */
					ssid: s.ssid || '',
					encryption: s.encryption || 'none',
					key: s.key || '',
					bands: new Set(),
					sections: []
				};
			}
			const dev = s.device;
			const band = uci.get('wireless', dev, 'band');
			if (band) mlds[key].bands.add(band);
			mlds[key].sections.push(s['.name']);
		} else {
			standalone.push(s['.name']);
		}
	});
	return { mlds: mlds, standalone: standalone };
}

function renderMldList(state, onEdit, onDelete, onAdd) {
	const radios = radiosByBand();
	const availableBands = BAND_ORDER.filter(b => radios[b]);
	const CELL = 'padding:0.75em 1em';
	const HEADCELL = CELL + ';font-weight:600;background:rgba(128,128,128,0.12)';

	const rows = [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th', 'style': HEADCELL }, _('SSID')),
			E('th', { 'class': 'th', 'style': HEADCELL }, _('Security')),
			E('th', { 'class': 'th', 'style': HEADCELL }, _('Bands linked')),
			E('th', { 'class': 'th cbi-section-actions', 'style': HEADCELL + ';text-align:right' },
				_('Actions'))
		])
	];

	const mldIds = Object.keys(state.mlds).sort();
	if (mldIds.length === 0) {
		rows.push(E('tr', { 'class': 'tr placeholder' }, [
			E('td', { 'class': 'td', 'colspan': 4, 'style': CELL + ';text-align:center' }, [
				E('em', {}, _('No MLO groups defined yet. Click "Add MLD" below to create one.'))
			])
		]));
	} else {
		mldIds.forEach(function (id) {
			const m = state.mlds[id];
			const bandsList = Array.from(m.bands).sort().map(b => BAND_LABEL[b] || b).join(', ');
			rows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'style': CELL },
					m.ssid || E('em', {}, _('(no SSID)'))),
				E('td', { 'class': 'td', 'style': CELL },
					ENC_LABEL[m.encryption] || m.encryption),
				E('td', { 'class': 'td', 'style': CELL },
					bandsList || E('em', {}, _('(none)'))),
				E('td', { 'class': 'td cbi-section-actions',
					'style': CELL + ';text-align:right;white-space:nowrap' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-edit',
						'style': 'margin-right:0.5em',
						'click': function () { onEdit(id); }
					}, _('Edit')),
					E('button', {
						'class': 'btn cbi-button cbi-button-remove',
						'click': function () { onDelete(id); }
					}, _('Delete'))
				])
			]));
		});
	}

	return E('div', { 'style': 'padding:0.5em 0' }, [
		E('h3', { 'style': 'margin-top:0;margin-bottom:0.75em' },
			_('WiFi 7 Multi-Link Operation (MLD Records)')),
		E('p', { 'style': 'margin-bottom:0.5em' },
			_('An MLD (Multi-Link Device) links several radio bands into a ' +
			  'single logical WiFi 7 network. Clients that support MLO can ' +
			  'use all linked bands simultaneously for higher throughput ' +
			  'and lower-latency failover. Older clients still see each band ' +
			  'as a regular standalone network.')),
		E('p', { 'class': 'hint', 'style': 'opacity:0.7;margin-bottom:0.25em' },
			_('Bands available on this device: %s.').format(
				availableBands.map(b => BAND_LABEL[b]).join(', ') || _('(none)'))),
		E('p', { 'class': 'hint', 'style': 'opacity:0.7;margin-bottom:0.25em' },
			_('This firmware negotiates EHT320 (320 MHz channels) on 6 GHz. ' +
			  'WiFi 7 clients (iPhone 16+, Pixel 9+, Intel BE200, MediaTek MT7925) ' +
			  'aggregate all MLD links. Non-MLO clients still associate via a ' +
			  'single preferred link and function normally.')),
		E('p', { 'class': 'hint', 'style': 'opacity:0.7;margin-bottom:1em' },
			_('MLO requires every linked band to share identical SSID, ' +
			  'encryption, PSK and PMF policy. The editor below enforces ' +
			  'this automatically when you save.')),
		E('table', {
			'class': 'table cbi-section-table',
			'style': 'width:100%;border-collapse:collapse'
		}, rows),
		E('div', { 'style': 'margin-top:1.25em' }, [
			E('button', {
				'class': 'btn cbi-button cbi-button-add',
				'click': function () { onAdd(); }
			}, _('+ Add MLD'))
		])
	]);
}

function openMldEditor(existing, onSave) {
	const radios = radiosByBand();
	const availableBands = BAND_ORDER.filter(b => radios[b]);

	const initial = existing || {
		ssid: '',
		encryption: 'sae',
		key: '12345678',
		bands: new Set(availableBands)
	};

	const INPUT_STYLE = 'width:100%;box-sizing:border-box;padding:0.5em';
	const LABEL_STYLE = 'display:block;font-weight:600;margin-bottom:0.35em;text-align:left';
	const ROW_STYLE   = 'margin-bottom:1em';

	function formRow(labelText, field, id) {
		return E('div', { 'class': 'mlo-row', 'style': ROW_STYLE }, [
			E('label', { 'for': id, 'style': LABEL_STYLE }, labelText),
			field
		]);
	}

	const ssidEl = E('input', {
		'id': 'mlo-ssid',
		'type': 'text',
		'class': 'cbi-input-text',
		'value': initial.ssid,
		'placeholder': 'MyWiFi7',
		'style': INPUT_STYLE
	});

	const encEl = E('select', {
		'id': 'mlo-enc',
		'class': 'cbi-input-select',
		'style': INPUT_STYLE
	}, Object.keys(ENC_LABEL).map(function (k) {
		return E('option', { 'value': k, 'selected': k === initial.encryption ? 'selected' : null },
			ENC_LABEL[k]);
	}));

	const keyEl = E('input', {
		'id': 'mlo-key',
		'type': 'text',
		'class': 'cbi-input-text',
		'value': initial.key,
		'placeholder': _('at least 8 characters'),
		'style': INPUT_STYLE
	});

	const bandChecks = availableBands.map(function (b) {
		return E('label', {
			'style': 'display:inline-flex;align-items:center;gap:0.4em;margin-right:1.25em;margin-bottom:0.25em;cursor:pointer'
		}, [
			E('input', {
				'type': 'checkbox',
				'value': b,
				'checked': initial.bands.has(b) ? 'checked' : null,
				'style': 'width:auto;margin:0'
			}),
			BAND_LABEL[b]
		]);
	});

	const bandBox = E('div', {
		'style': 'display:flex;flex-wrap:wrap;padding:0.4em 0'
	}, bandChecks);

	const warn = E('div', {
		'class': 'alert-message warning',
		'style': 'display:none;margin-top:0.5em'
	});

	/* Build rows so we can hide the key row as a whole when not needed */
	const ssidRow  = formRow(_('SSID'),             ssidEl,  'mlo-ssid');
	const encRow   = formRow(_('Security'),         encEl,   'mlo-enc');
	const keyRow   = formRow(_('Key / Passphrase'), keyEl,   'mlo-key');
	const bandsRow = formRow(_('Linked bands'),     bandBox, null);

	function syncKeyVisibility() {
		const needsKey = /^(psk2|sae|sae-mixed)$/.test(encEl.value);
		keyRow.style.display = needsKey ? '' : 'none';
	}
	encEl.addEventListener('change', syncKeyVisibility);

	function collect() {
		return {
			ssid: ssidEl.value.trim(),
			encryption: encEl.value,
			key: keyEl.value,
			bands: new Set(Array.from(bandChecks)
				.map(l => l.querySelector('input'))
				.filter(cb => cb.checked)
				.map(cb => cb.value))
		};
	}

	ui.showModal(existing ? _('Edit MLD') : _('Add MLD'), [
		E('p', { 'style': 'margin:0 0 1.25em 0' },
			existing
				? _('Editing MLD "%s". Changes will regenerate the underlying wireless sections on Save & Apply.').format(initial.ssid)
				: _('Create a new Multi-Link Device. All selected bands will advertise the same SSID and share the same security.')),
		ssidRow,
		encRow,
		keyRow,
		bandsRow,
		warn,
		E('div', { 'style': 'display:flex;justify-content:flex-end;gap:0.5em;margin-top:1.5em' }, [
			E('button', {
				'class': 'btn',
				'click': ui.hideModal
			}, _('Cancel')),
			E('button', {
				'class': 'btn cbi-button cbi-button-positive',
				'click': function () {
					const rec = collect();
					if (!rec.ssid) {
						warn.style.display = '';
						warn.textContent = _('SSID cannot be empty.');
						return;
					}
					if (/^(psk2|sae|sae-mixed)$/.test(rec.encryption) && rec.key.length < 8) {
						warn.style.display = '';
						warn.textContent = _('PSK key must be at least 8 characters.');
						return;
					}
					if (rec.bands.size === 0) {
						warn.style.display = '';
						warn.textContent = _('Select at least one band.');
						return;
					}
					if (rec.bands.size === 1) {
						warn.style.display = '';
						warn.textContent = _('MLO requires at least 2 linked bands. Add another band or disable MLO for this SSID.');
						return;
					}
					ui.hideModal();
					onSave(rec);
				}
			}, _('Save'))
		])
	]);
	syncKeyVisibility();
}

/*
 * Apply an MLD record into uci.wireless by (re)writing its wifi-iface
 * sections. Removes old sections belonging to this mld_id, then
 * creates fresh ones for the selected bands.
 */
function ssid_to_slug(ssid) {
	/* make a valid-ish uci section name from an SSID */
	return 'mld_' + String(ssid || 'unnamed')
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, '_')
		.replace(/^_+|_+$/g, '')
		.slice(0, 20);
}

function applyMld(rec) {
	const radios = radiosByBand();
	const target_ssid = rec.ssid;
	const slug = ssid_to_slug(target_ssid);
	const allBands = BAND_ORDER.filter(b => radios[b]);

	/*
	 * Remember which bands this MLD covered BEFORE we rewrite it, so
	 * that un-ticking a band in an edit converts that band to a
	 * standalone AP (same SSID, no mlo=1) rather than deleting the
	 * network entirely. Bands the user never added to the MLD stay
	 * untouched.
	 */
	const hadBefore = new Set();
	uci.sections('wireless', 'wifi-iface').forEach(function (s) {
		if (s.mode !== 'sta' && s.ssid === target_ssid &&
		    (s.mlo == '1' || s.mlo === 1)) {
			const band = uci.get('wireless', s.device, 'band');
			if (band) hadBefore.add(band);
		}
	});

	/*
	 * Supersede any existing wifi-iface broadcasting this SSID
	 * (MLO or standalone) so we get a clean slate to rewrite.
	 */
	uci.sections('wireless', 'wifi-iface').forEach(function (s) {
		if (s.mode !== 'sta' && s.ssid === target_ssid) {
			uci.remove('wireless', s['.name']);
		}
	});

	/*
	 * For every available band:
	 *   - ticked now        -> create MLO section (mlo=1)
	 *   - unticked now, but was in the MLD last save -> create as
	 *     a standalone AP (same SSID + security, no mlo=1).
	 *   - unticked now and never in the MLD -> skip.
	 *
	 * OpenWrt's ap.uc translates `option mlo 1` into hostapd's
	 * mld_ap=1 + mld_link_id=<radio>, grouping all mlo sections
	 * with the same SSID into one MLD.
	 */
	allBands.forEach(function (band) {
		const dev = radios[band];
		if (!dev) return;
		const inMlo = rec.bands.has(band);
		const keepAsStandalone = !inMlo && hadBefore.has(band);
		if (!inMlo && !keepAsStandalone) return;

		const iface = slug + '_' + band;
		uci.add('wireless', 'wifi-iface', iface);
		uci.set('wireless', iface, 'device', dev);
		uci.set('wireless', iface, 'network', 'lan');
		uci.set('wireless', iface, 'mode', 'ap');
		uci.set('wireless', iface, 'ssid', rec.ssid);
		uci.set('wireless', iface, 'encryption', rec.encryption);
		if (/^(psk2|sae|sae-mixed)$/.test(rec.encryption)) {
			uci.set('wireless', iface, 'key', rec.key);
		}
		/*
		 * PMF policy per band:
		 *   - 6 GHz: PMF=2 required (802.11ax spec).
		 *   - Pure SAE or OWE on any band: PMF=2.
		 *   - SAE-mixed on 2.4/5 GHz: PMF=1 (optional, keeps WPA2
		 *     clients working).
		 *   - psk2 / none: no PMF.
		 */
		let pmf = null;
		if (band === '6g')                             pmf = '2';
		else if (/^(sae|owe)$/.test(rec.encryption))   pmf = '2';
		else if (rec.encryption === 'sae-mixed')       pmf = '1';
		if (pmf) uci.set('wireless', iface, 'ieee80211w', pmf);

		if (inMlo) uci.set('wireless', iface, 'mlo', '1');
		uci.set('wireless', iface, 'disabled', '0');
	});
}

function deleteMld(ssid_key) {
	uci.sections('wireless', 'wifi-iface').forEach(function (s) {
		if ((s.mlo == '1' || s.mlo === 1) && s.ssid === ssid_key) {
			uci.remove('wireless', s['.name']);
		}
	});
}

return view.extend({
	load: function () {
		loadCss(L.resource('view/zbt8803be/zbt-theme.css'));
		return uci.load('wireless');
	},

	render: function () {
		const container = E('div', { 'id': 'mlo-root', 'class': 'zbt-app zbt-mlo' });

		const self = this;
		function refresh() {
			const state = loadMlds();
			const mount = document.getElementById('mlo-root') || container;
			dom.content(mount, renderMldList(
				state,
				function editMld(id) {
					const rec = state.mlds[id];
					openMldEditor(rec, function saved(updated) {
						applyMld(updated);
						refresh();
					});
				},
				function removeMld(id) {
					if (!confirm(_('Delete MLD group %s? The underlying wifi-iface sections will be removed on Save & Apply.').format(id)))
						return;
					deleteMld(id);
					refresh();
				},
				function addMld() {
					openMldEditor(null, function saved(rec) {
						applyMld(rec);
						refresh();
					});
				}
			));
		}

		setTimeout(refresh, 0);
		return E('div', { 'class': 'cbi-map zbt-app zbt-mlo' }, [
			container,
			E('div', { 'class': 'cbi-page-actions', 'style': 'margin-top:1.5em' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-save cbi-button-positive',
					'click': function () {
						return uci.save()
							.then(() => ui.changes.apply())
							.catch(err => ui.addNotification(null, E('p', {}, err.message || String(err)), 'danger'));
					}
				}, _('Save & Apply')),
				' ',
				E('button', {
					'class': 'btn',
					'click': function () { return uci.reset().then(refresh); }
				}, _('Reset'))
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
