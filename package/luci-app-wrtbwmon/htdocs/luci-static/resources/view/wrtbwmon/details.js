'use strict';
'require dom';
'require fs';
'require poll';
'require rpc';
'require ui';
'require validation';
'require view';

var cachedData = [];
var luciConfig = '/etc/luci-wrtbwmon.conf';
var hostNameFile = '/etc/wrtbwmon.user';
var columns = {
	thClient: _('Clients'),
	thMAC: _('MAC'),
	thDownload: _('Download'),
	thUpload: _('Upload'),
	thTotalDown: _('Total Down'),
	thTotalUp: _('Total Up'),
	thTotal: _('Total'),
	thFirstSeen: _('First Seen'),
	thLastSeen: _('Last Seen'),
	thActions: _('Actions')
};

var callLuciDHCPLeases = rpc.declare({
	object: 'luci-rpc',
	method: 'getDHCPLeases',
	expect: { '': {} }
});

var callLuciDSLStatus = rpc.declare({
	object: 'luci-rpc',
	method: 'getDSLStatus',
	expect: { '': {} }
});

var callGetDatabaseRaw = rpc.declare({
	object: 'luci.wrtbwmon',
	method: 'get_db_raw',
	params: [ 'protocol', 'date_filter' ]
});

var callRemoveDatabase = rpc.declare({
	object: 'luci.wrtbwmon',
	method: 'remove_db',
	params: [ 'protocol' ]
});

var callGetSpeedStats = rpc.declare({
	object: 'luci.wrtbwmon',
	method: 'get_speed_stats'
});

function $(tid) {
	return document.getElementById(tid);
}

function clickToResetDatabase(settings, table, updated, updating, ev) {
	if (confirm(_('This will delete the database file. Are you sure?'))) {
		return callRemoveDatabase(settings.protocol)
		.then(function() {
			updateData(settings, table, updated, updating, true);
		});
	}
}

function clickToSaveConfig(keylist, cstrs) {
	var data = {};

	for (var i = 0; i < keylist.length; i++) {
		data[keylist[i]] = cstrs[keylist[i]].getValue();
	}

	ui.showModal(_('Configuration'), [
		E('p', { 'class': 'spinning' }, _('Saving configuration data...'))
	]);

	return fs.write(luciConfig, JSON.stringify(data, undefined, '\t') + '\n')
	.catch(function(err) {
		ui.addNotification(null, E('p', {}, [ _('Unable to save %s: %s').format(luciConfig, err) ]));
	})
	.then(ui.hideModal)
	.then(function() { document.location.reload(); });
}

function clickToSelectInterval(settings, updating, ev) {
	if (ev.target.value > 0) {
		settings.interval = parseInt(ev.target.value);
		if (!poll.active()) poll.start();
	}
	else {
		poll.stop();
		setUpdateMessage(updating, -1);
	}
}

function clickToSelectProtocol(settings, table, updated, updating, ev) {
	settings.protocol = ev.target.value;
	updateData(settings, table, updated, updating, true);
}

function createOption(args, val) {
	var cstr = args[0], title = args[1], desc = args.slice(-1), widget, frame;
	widget = args.length == 4 ? new cstr(val, args[2]) : new cstr(val, args[2], args[3]);

	frame = E('div', {'class': 'cbi-value'}, [
		E('label', {'class': 'cbi-value-title'}, title),
		E('div', {'class': 'cbi-value-field'}, E('div', {}, widget.render()))
	]);

	if (desc && desc != '')
		dom.append(frame.lastChild, E('div', { 'class': 'cbi-value-description' }, desc));

	return [widget, frame];
}

function displayTable(tb, settings) {
	var elm, elmID, col, sortedBy, flag, IPVer;

	elm = tb.querySelector('.th.sorted');
	elmID = elm ? elm.id : 'thTotal';
	sortedBy = elm && elm.classList.contains('ascent') ? 'asc' : 'desc';

	col = Object.keys(columns).indexOf(elmID);
	IPVer = col == 0 ? settings.protocol : null;
	flag = sortedBy == 'desc' ? 1 : -1;

	cachedData[0].sort(sortTable.bind(this, col, IPVer, flag));

	//console.time('show');
	updateTable(tb, cachedData, '<em>%s</em>'.format(_('Collecting data...')), settings);
	//console.timeEnd('show');
	progressbar('downstream', cachedData[1][0], settings.downstream, settings.useBits, settings.useMultiple);
	progressbar('upstream', cachedData[1][1], settings.upstream, settings.useBits, settings.useMultiple);
}

function formatSize(size, useBits, useMultiple) {
	// String.format automatically adds the i for KiB if the multiple is 1024
	return String.format('%%%s.2m%s'.format(useMultiple, (useBits ? 'bit' : 'B')), useBits ? size * 8 : size);
}

function formatSpeed(speed, useBits, useMultiple) {
	// Show Mbit/s first, then bytes/s in brackets
	var mbits = (speed * 8 / 1000000).toFixed(2);
	var bytesPerSec = formatSize(speed, false, useMultiple);
	return mbits + ' Mbit/s (' + bytesPerSec + '/s)';
}

function formatRelativeTimeFromEpoch(epoch) {
	// Format relative time from unix epoch timestamp (seconds since 1970-01-01 UTC)
	// This is timezone-safe: both epoch and Date.now() are in UTC
	if (!epoch || epoch === 0) return 'never';
	var nowSec = Math.floor(Date.now() / 1000);
	var diffSec = nowSec - epoch;

	if (diffSec < 0) return 'just now';

	var seconds = diffSec % 60;
	var minutes = Math.floor(diffSec / 60) % 60;
	var hours = Math.floor(diffSec / 3600) % 24;
	var days = Math.floor(diffSec / 86400);

	var parts = [];
	if (days > 0) parts.push(days + 'd');
	if (hours > 0) parts.push(hours + 'h');
	if (minutes > 0) parts.push(minutes + 'm');
	if (seconds > 0 && days === 0) parts.push(seconds + 's');

	if (parts.length === 0) return 'just now';
	return parts.join(' ') + ' ago';
}

function getDSLBandwidth() {
	return callLuciDSLStatus().then(function(res) {
		return {
			upstream : res.max_data_rate_up || null,
			downstream : res.max_data_rate_down || null
		};
	});
}

function handleConfig(ev) {
	ui.showModal(_('Configuration'), [
			E('p', { 'class': 'spinning' }, _('Loading configuration data...'))
	]);

	parseDefaultSettings(luciConfig)
	.then(function(settings) {
		var arglist, keylist = Object.keys(settings), res, cstrs = {}, node = [], body;

		arglist = [
			[ui.Select, _('Default Protocol'), {'ipv4': _('ipv4'), 'ipv6': _('ipv6')}, {}, ''],
			[ui.Select, _('Default Refresh Interval'), {'-1': _('Disabled'), '2': _('2 seconds'), '5': _('5 seconds'), '10': _('10 seconds'), '30': _('30 seconds')}, {sort: ['-1', '2', '5', '10', '30']}, ''],
			[ui.Dropdown, _('Default Columns'), columns, {multiple: true, sort: false, custom_placeholder: '', dropdown_items: 3}, ''],
			[ui.Checkbox, _('Show Zeros'), {value_enabled: true, value_disabled: false}, ''],
			[ui.Checkbox, _('Transfer Speed in Bits'), {value_enabled: true, value_disabled: false}, ''],
			[ui.Select, _('Multiple of Unit'), {'1000': _('SI - 1000'), '1024': _('IEC - 1024')}, {}, ''],
			[ui.Checkbox, _('Use DSL Bandwidth'), {value_enabled: true, value_disabled: false}, ''],
			[ui.Textfield, _('Upstream Bandwidth'), {datatype: 'ufloat'}, 'Mbps'],
			[ui.Textfield, _('Downstream Bandwidth'), {datatype: 'ufloat'}, 'Mbps'],
			[ui.DynamicList, _('Hide MAC Addresses'), '', {datatype: 'macaddr'}, '']
		]; // [constructor, label(, all_choices), options, description]

		for (var i = 0; i < keylist.length; i++) {
			res = createOption(arglist[i], settings[keylist[i]]);
			cstrs[keylist[i]] = res[0];
			node.push(res[1]);
		}

		body = [
			E('p', {}, _('Configure the default values for luci-app-wrtbwmon.')),
			E('div', {}, node),
			E('div', { 'class': 'right' }, [
				E('div', {
					'class': 'btn cbi-button-neutral',
					'click': ui.hideModal
				}, _('Cancel')),
				' ',
				E('div', {
					'class': 'btn cbi-button-positive',
					'click': clickToSaveConfig.bind(this, keylist, cstrs),
					'disabled': (L.hasViewPermission ? !L.hasViewPermission() : null) || null
				}, _('Save'))
			])
		];
		ui.showModal(_('Configuration'), body);
	})
}

function loadCss(path) {
	var head = document.head || document.getElementsByTagName('head')[0];
	var link = E('link', {
		'rel': 'stylesheet',
		'href': path,
		'type': 'text/css'
	});

	head.appendChild(link);
}

function parseDatabase(raw, hosts, showZero, hideMACs) {
	var values = [],
	    totals = [0, 0, 0, 0, 0];

	if (!Array.isArray(raw)) return [values, totals];

	for (var i = 0; i < raw.length; i++) {
		var entry = raw[i];

		// Skip if showZero is false and total is 0
		if (!showZero && entry.total == 0) continue;

		// Skip if MAC is in hideMACs list
		if (hideMACs.indexOf(entry.mac) >= 0) continue;

		// Update totals
		totals[0] += parseInt(entry.download) || 0;
		totals[1] += parseInt(entry.upload) || 0;
		totals[2] += parseInt(entry.download) || 0;
		totals[3] += parseInt(entry.upload) || 0;
		totals[4] += parseInt(entry.total) || 0;

		// Build row: [ip, mac, download, upload, download, upload, total, first_seen, last_seen, hostname]
		// first_seen/last_seen are unix epoch timestamps (timezone-safe)
		var hostname = (entry.hostname !== undefined && entry.hostname !== null) ? entry.hostname :
		               (entry.mac.toLowerCase() in hosts ? hosts[entry.mac.toLowerCase()] : '');
		var row = [
			entry.ip || '',
			entry.mac || '',
			parseInt(entry.download) || 0,
			parseInt(entry.upload) || 0,
			parseInt(entry.download) || 0,
			parseInt(entry.upload) || 0,
			parseInt(entry.total) || 0,
			parseInt(entry.first_seen) || 0,
			parseInt(entry.last_seen) || 0,
			hostname
		];
		values.push(row);
	}
	return [values, totals];
}

function parseDefaultSettings(file) {
	var defaultColumns = ['thClient', 'thMAC', 'thDownload', 'thUpload', 'thTotal', 'thFirstSeen', 'thLastSeen', 'thActions'],
	    keylist = ['protocol', 'interval', 'showColumns', 'showZero', 'useBits', 'useMultiple', 'useDSL', 'upstream', 'downstream', 'hideMACs'],
	    valuelist = ['ipv4', '5', defaultColumns, true, false, '1000', false, '1000', '1000', []];

	return fs.read_direct(file, 'json').then(function(oldSettings) {
		var settings = {};
		for (var i = 0; i < keylist.length; i++) {
			if (!(keylist[i] in oldSettings))
				settings[keylist[i]] = valuelist[i];
			else
				settings[keylist[i]] = oldSettings[keylist[i]];
		}

		if (settings.useDSL) {
			return getDSLBandwidth().then(function(dsl) {
				for (var s in dsl)
					settings[s] = dsl[s];
				return settings;
			});
		}
		else {
			return settings;
		}
	})
	.catch(function() { return {} });
}

function progressbar(query, v, m, useBits, useMultiple) {
	// v = B/s, m = Mb/s
	var pg = $(query),
	    vn = (v * 8) || 0,
	    mn = (m || 100) * Math.pow(1000, 2),
	    fv = formatSpeed(v, useBits, useMultiple),
	    pc = '%.2f'.format((100 / mn) * vn),
	    wt = Math.floor(pc > 100 ? 100 : pc),
	    bgc = (pc >= 95 ? 'red' : (pc >= 80 ? 'darkorange' : (pc >= 60 ? 'yellow' : 'lime')));
	if (pg) {
		pg.firstElementChild.style.width = wt + '%';
		pg.firstElementChild.style.background = bgc;
		pg.setAttribute('title', '%s (%f%%)'.format(fv, pc));
	}
}

function setupThisDOM(settings, table) {
	document.addEventListener('poll-stop', function() {
		$('selectInterval').value = -1;
	});

	document.addEventListener('poll-start', function() {
		$('selectInterval').value = settings.interval;
	});

	table.querySelectorAll('.th').forEach(function(e) {
		if (e) {
			e.addEventListener('click', function (ev) {
				setSortedColumn(ev.target);
				displayTable(table, settings);
			});

			if (settings.showColumns.indexOf(e.id) >= 0)
				e.classList.remove('hide');
			else
				e.classList.add('hide');

		}
	});
}

function renameFile(str, tag) {
	var n = str.lastIndexOf('/'), fn = n > -1 ? str.slice(n + 1) : str, dir = n > -1 ? str.slice(0, n + 1) : '';
	var n = fn.lastIndexOf('.'), bn = n > -1 ? fn.slice(0, n) : fn;
	var n = fn.lastIndexOf('.'), en = n > -1 ? fn.slice(n + 1) : '';
	return dir + bn + '.' + tag + (en ? '.' + en : '');
}

function resolveCustomizedHostName() {
	return fs.stat(hostNameFile).then(function() {
		return fs.read_direct(hostNameFile).then(function(raw) {
			var arr = raw.trim().split(/\r?\n/), hosts = {}, row;
			for (var i = 0; i < arr.length; i++) {
				row = arr[i].split(',');
				if (row.length == 2 && row[0])
					hosts[row[0].toLowerCase()] = row[1];
			}
			return hosts;
		})
	})
	.catch(function() { return []; });
}

function resolveHostNameByMACAddr() {
	return Promise.all([
		resolveCustomizedHostName(),
		callLuciDHCPLeases()
	]).then(function(res) {
		var hosts = res[0];
		for (var key in res[1]) {
			var leases = Array.isArray(res[1][key]) ? res[1][key] : [];
			for (var i = 0; i < leases.length; i++) {
				if(leases[i].macaddr) {
					var macaddr = leases[i].macaddr.toLowerCase();
					if (!(macaddr in hosts) && Boolean(leases[i].hostname))
						hosts[macaddr] = leases[i].hostname;
				}
			}
		}
		return hosts;
	});
}

function setSortedColumn(sorting) {
	var sorted = document.querySelector('.th.sorted') || $('thTotal');

	if (sorting.isSameNode(sorted)) {
		sorting.classList.toggle('ascent');
	}
	else {
		sorting.classList.add('sorted');
		sorted.classList.remove('sorted', 'ascent');
	}
}

function setUpdateMessage(e, sec) {
	if (!e) return;
	e.innerHTML = sec < 0 ? '' : _('Updating again in %s second(s).').format('<b>' + sec + '</b>');
}

function sortTable(col, IPVer, flag, x, y) {
	var byCol = x[col] == y[col] ? 1 : col;
	var a = x[byCol], b = y[byCol];

	if (!IPVer || byCol != 0) {
		// Convert to string for regex check, handle numbers directly
		if (typeof a === 'number' && typeof b === 'number') {
			// Both are already numbers, no conversion needed
		} else {
			// Convert to strings and check if they're numeric
			var aStr = String(a), bStr = String(b);
			if (!(aStr.match(/\D/g) || bStr.match(/\D/g)))
				a = parseInt(a), b = parseInt(b);
		}
	}
	else {
		IPVer == 'ipv4'
		? (a = validation.parseIPv4(a) || [0, 0, 0, 0], b = validation.parseIPv4(b) || [0, 0, 0, 0])
		: (a = validation.parseIPv6(a) || [0, 0, 0, 0, 0, 0, 0, 0], b = validation.parseIPv6(b) || [0, 0, 0, 0, 0, 0, 0, 0]);
	}

	if (Array.isArray(a) && Array.isArray(b)) {
		for (var i = 0; i < a.length; i++) {
			if (a[i] != b[i]) {
				return (b[i] - a[i]) * flag;
			}
		}
		return 0;
	}

	return a == b ? 0 : (a < b ? 1 : -1) * flag;
}

function updateData(settings, table, updated, updating, warningBox, once) {
	var tick = poll.tick,
	    interval = settings.interval,
	    sec = (interval - tick % interval) % interval;
	if (!sec || once) {
		Promise.all([
			callGetDatabaseRaw(settings.protocol, settings.dateFilter || 'today'),
			resolveHostNameByMACAddr()
		])
		.then(function(res) {
			// res[0] may be {data: [...]} or the array directly
			var rawData = Array.isArray(res[0]) ? res[0] : (res[0].data || []);
			var warning = Array.isArray(res[0]) ? '' : (res[0].warning || '');
			if (warningBox) {
				dom.content(warningBox, warning);
				warningBox.style.display = warning ? '' : 'none';
			}
			cachedData = parseDatabase(rawData, res[1], settings.showZero, settings.hideMACs);
			displayTable(table, settings);
			updated.textContent = _('Last updated at %s.').format(new Date().toLocaleTimeString());
		});
	}
	else if (cachedData.length) {
		// Between data fetches: re-render table to update relative times
		displayTable(table, settings);
	}

	setUpdateMessage(updating, sec);
	if (!sec)
		setTimeout(setUpdateMessage.bind(this, updating, interval), 100);
}

function updateTable(tb, values, placeholder, settings) {
	var fragment = document.createDocumentFragment(), nodeLen = tb.childElementCount - 2;
	var formData = values[0], tbTitle = tb.firstElementChild, newNode, childTD;

	// Update the table data.
	for (var i = 0; i < formData.length; i++) {
		if (i < nodeLen) {
			newNode = tbTitle.nextElementSibling;
		}
		else {
			if (nodeLen > 0) {
				newNode = fragment.firstChild.cloneNode(true);
			}
			else {
				newNode = document.createElement('tr');
				childTD = document.createElement('td');
				for (var j = 0; j < tbTitle.children.length; j++) {
					childTD.className = 'td' + (settings.showColumns.indexOf(tbTitle.children[j].id) >= 0 ? '' : ' hide');
					childTD.setAttribute('data-title', tbTitle.children[j].textContent);
					newNode.appendChild(childTD.cloneNode(true));
				}
			}
			newNode.className = 'tr cbi-rowstyle-%d'.format(i % 2 ? 2 : 1);
		}

		childTD = newNode.firstElementChild;
		childTD.title = formData[i].slice(-1);
		// Store hostname and MAC for later use
		// formData[i][9] is hostname - use it directly, only default to 'N/A' if undefined or null
		var hostname = (formData[i][9] !== undefined && formData[i][9] !== null) ? formData[i][9] : 'N/A';
		var mac = formData[i][1]; // MAC address is at index 1
		for (var j = 0; j < tbTitle.childElementCount; j++, childTD = childTD.nextElementSibling) {
			switch (j) {
				case 2:
				case 3:
					// Columns 2 and 3 are cumulative Download/Upload, not speeds
					childTD.textContent = formatSize(formData[i][j], settings.useBits, settings.useMultiple);
					break;
				case 4:
				case 5:
				case 6:
					childTD.textContent = formatSize(formData[i][j], settings.useBits, settings.useMultiple);
					break;
				case 7:
				case 8:
					// formData[i][j] is a unix epoch timestamp (seconds)
					var relativeTime = formatRelativeTimeFromEpoch(formData[i][j]);
					childTD.textContent = relativeTime;
					break;
				case 9:
					// Actions column - add View Domains button
					dom.content(childTD, E('button', {
						'class': 'btn cbi-button-action',
						'click': function(macAddr) {
							return function() {
								window.location.href = L.url('admin/services/traffic/device-domains') + '?mac=' + encodeURIComponent(macAddr);
							};
						}(mac)
					}, _('View Domains')));
					break;
				default:
					if (j === 0) {
						// Column 0 is Client (IP), show with hostname if available
						if (hostname && hostname !== '') {
							childTD.textContent = formData[i][j] + ' (' + hostname + ')';
						} else {
							childTD.textContent = formData[i][j];
						}
					} else {
						childTD.textContent = formData[i][j];
					}
			}
		}
		fragment.appendChild(newNode);
	}

	// Remove the table data which has been deleted from the database.
	while (tb.childElementCount > 1) {
		tb.removeChild(tbTitle.nextElementSibling);
	}

	//Append the totals or placeholder row.
	if (formData.length == 0) {
		newNode = document.createElement('tr');
		newNode.className = 'tr placeholder';
		childTD = document.createElement('td');
		childTD.className = 'td';
		childTD.innerHTML = placeholder;
		newNode.appendChild(childTD);
	}
	else{
		newNode = fragment.firstChild.cloneNode(true);
		newNode.className = 'tr table-totals';

		newNode.children[0].textContent = _('TOTAL') + (settings.showColumns.indexOf('thMAC') >= 0 ? '' : ': ' + formData.length);
		newNode.children[1].textContent = formData.length + ' ' + _('Clients');

		for (var j = 0; j < tbTitle.childElementCount; j++) {
			switch(j) {
				case 0:
				case 1:
					newNode.children[j].removeAttribute('title');
					newNode.children[j].style.fontWeight = 'bold';
					break;
				case 2:
				case 3:
					newNode.children[j].textContent = formatSize(values[1][j - 2], settings.useBits, settings.useMultiple);
					break;
				case 4:
				case 5:
				case 6:
					newNode.children[j].textContent = formatSize(values[1][j - 2], settings.useBits, settings.useMultiple);
					break;
				case 9:
					// Actions column in totals row - leave empty
					newNode.children[j].textContent = '';
					newNode.children[j].removeAttribute('data-title');
					break;
				default:
					newNode.children[j].textContent = '';
					newNode.children[j].removeAttribute('data-title');
			}
		}
	}

	fragment.appendChild(newNode);
	tb.appendChild(fragment);
}

function initOption(options, selected) {
	var res = [], attr = {};
	for (var idx in options) {
		attr.value = idx;
		attr.selected = idx == selected ? '' : null;
		res.push(E('option', attr, options[idx]));
	}
	return res;
}

return view.extend({
	load: function() {
		return Promise.all([
			parseDefaultSettings(luciConfig),
			loadCss(L.resource('view/zbt8803be/zbt-theme.css')),
			loadCss(L.resource('view/wrtbwmon/wrtbwmon.css')),
			loadCss(L.resource('view/wrtbwmon/domains.css'))
		]);
	},

	render: function(data) {
		var settings = data[0];
		var currentFilter = 'today';

		var filterLabels = {
			'today': _('Today'),
			'yesterday': _('Yesterday'),
			'last7days': _('Last 7 Days'),
			'thismonth': _('This Month'),
			'lastmonth': _('Last Month')
		};

		function formatSpeed(bytesPerSec) {
			if (bytesPerSec === 0) return '0 Mbit/s (0 B/s)';
			var k = 1024;
			var sizes = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
			var i = Math.floor(Math.log(bytesPerSec) / Math.log(k));
			var speed = (bytesPerSec / Math.pow(k, i)).toFixed(2);
			var mbit = ((bytesPerSec * 8) / 1000000).toFixed(2);
			return mbit + ' Mbit/s (' + speed + ' ' + sizes[i] + ')';
		}

		var speedStats = E('div', { 'class': 'speed-stats' }, [
			E('div', { 'class': 'speed-item' }, [
				E('span', { 'class': 'speed-label' }, _('Download:')),
				E('span', { 'class': 'speed-value', 'id': 'speed-download' }, '0 Mbit/s (0 B/s)')
			]),
			E('div', { 'class': 'speed-item' }, [
				E('span', { 'class': 'speed-label' }, _('Upload:')),
				E('span', { 'class': 'speed-value', 'id': 'speed-upload' }, '0 Mbit/s (0 B/s)')
			]),
			E('div', { 'class': 'speed-item' }, [
				E('span', { 'class': 'speed-label' }, _('Total:')),
				E('span', { 'class': 'speed-value', 'id': 'speed-total' }, '0 Mbit/s (0 B/s)')
			])
		]);

		function updateSpeedStats() {
			callGetSpeedStats().then(function(speedData) {
				if (speedData && typeof speedData === 'object') {
					var downloadSpeed = speedData.download_speed || 0;
					var uploadSpeed = speedData.upload_speed || 0;
					var totalSpeed = speedData.total_speed || 0;

					var downloadEl = document.getElementById('speed-download');
					var uploadEl = document.getElementById('speed-upload');
					var totalEl = document.getElementById('speed-total');

					if (downloadEl) downloadEl.textContent = formatSpeed(downloadSpeed);
					if (uploadEl) uploadEl.textContent = formatSpeed(uploadSpeed);
					if (totalEl) totalEl.textContent = formatSpeed(totalSpeed);
				}
			}).catch(function(err) {
				console.error('Failed to fetch speed stats:', err);
			});
		}

		// Update speed stats every 5 seconds
		poll.add(updateSpeedStats, 5);
		updateSpeedStats(); // Initial update

		var labelUpdated = E('div', { 'class': 'last-updated' }, _('Last updated: ') + new Date().toLocaleTimeString());
		var labelUpdating = E('label'); // Placeholder for compatibility
		var warningBox = E('div', { 'class': 'alert-message warning', 'style': 'display:none' });

		var filterButtons = Object.keys(filterLabels).map(function(filter) {
			return E('button', {
				'class': 'btn cbi-button date-filter-btn' + (filter === currentFilter ? ' active' : ''),
				'click': function() {
					currentFilter = filter;
					settings.dateFilter = filter;
					updateData(settings, table, labelUpdated, labelUpdating, warningBox, true);
					// Update button states
					document.querySelectorAll('.date-filter-btn').forEach(function(btn) {
						btn.classList.remove('active');
					});
					this.classList.add('active');
				}
			}, filterLabels[filter]);
		});

		var table = E('table', { 'class': 'table', 'id': 'traffic' }, [
					E('tr', { 'class': 'tr table-titles' }, [
						E('th', { 'class': 'th', 'id': 'thClient' }, _('Clients')),
						E('th', { 'class': 'th hide', 'id': 'thMAC' }, _('MAC')),
						E('th', { 'class': 'th', 'id': 'thDownload' }, _('Download')),
						E('th', { 'class': 'th', 'id': 'thUpload' }, _('Upload')),
						E('th', { 'class': 'th', 'id': 'thTotalDown' }, _('Total Down')),
						E('th', { 'class': 'th', 'id': 'thTotalUp' }, _('Total Up')),
						E('th', { 'class': 'th sorted', 'id': 'thTotal' }, _('Total')),
						E('th', { 'class': 'th hide', 'id': 'thFirstSeen' }, _('First Seen')),
						E('th', { 'class': 'th hide', 'id': 'thLastSeen' }, _('Last Seen')),
						E('th', { 'class': 'th', 'id': 'thActions' }, _('Actions'))
					]),
					E('tr', {'class': 'tr placeholder'}, [
						E('td', { 'class': 'td' }, E('em', {}, _('Collecting data...')))
					])
				]);

		poll.add(updateData.bind(this, settings, table, labelUpdated, labelUpdating, warningBox, false), 5);
		setupThisDOM(settings, table);

		// Initial data load
		updateData(settings, table, labelUpdated, labelUpdating, warningBox, true);

		return E('div', { 'class': 'cbi-map zbt-app zbt-traffic' }, [
			E('h2', {}, _('Device Traffic')),
			labelUpdated,
			warningBox,
			speedStats,
			E('div', { 'class': 'date-filter-buttons' }, filterButtons),
			table
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
