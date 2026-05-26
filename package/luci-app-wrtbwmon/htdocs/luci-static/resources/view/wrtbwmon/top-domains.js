'use strict';
'require view';
'require rpc';
'require ui';
'require dom';
'require poll';

var callGetTopDomains = rpc.declare({
	object: 'luci.wrtbwmon',
	method: 'get_top_domains',
	params: ['date_filter', 'limit']
});

function formatBytes(bytes) {
	if (bytes === 0) return '0 B';
	var k = 1024;
	var sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
	var i = Math.floor(Math.log(bytes) / Math.log(k));
	return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + sizes[i];
}

function formatTime(timestamp) {
	var date = new Date(timestamp * 1000);
	var now = new Date();
	var diff = Math.floor((now - date) / 1000);

	if (diff < 60) return diff + 's ago';
	if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
	if (diff < 86400) return Math.floor(diff / 3600) + 'h ago';
	return Math.floor(diff / 86400) + 'd ago';
}

function loadCss(path) {
	var head = document.head || document.getElementsByTagName('head')[0];
	var link = document.createElement('link');
	link.rel = 'stylesheet';
	link.href = path;
	link.type = 'text/css';
	head.appendChild(link);
}

return view.extend({
	load: function() {
		loadCss(L.resource('view/zbt8803be/zbt-theme.css'));
		loadCss(L.resource('view/wrtbwmon/domains.css'));
		return callGetTopDomains('today', 1000);
	},

	render: function(data) {
		var currentFilter = 'today';
		var domains = data.domains || [];
		var warning = data.warning || '';

		var filterLabels = {
			'today': _('Today'),
			'yesterday': _('Yesterday'),
			'last7days': _('Last 7 Days'),
			'thismonth': _('This Month'),
			'lastmonth': _('Last Month')
		};

		var labelUpdated = E('div', { 'class': 'last-updated' }, _('Last updated: ') + new Date().toLocaleTimeString());
		var warningBox = E('div', { 'class': 'alert-message warning', 'style': warning ? '' : 'display:none' }, warning);

		var filterButtons = Object.keys(filterLabels).map(function(filter) {
			return E('button', {
				'class': 'btn cbi-button date-filter-btn' + (filter === currentFilter ? ' active' : ''),
				'click': function() {
					currentFilter = filter;
					callGetTopDomains(filter, 1000).then(function(result) {
						domains = result.domains || [];
						warning = result.warning || '';
						updateTable(domains);
					});
					// Update button states
					document.querySelectorAll('.date-filter-btn').forEach(function(btn) {
						btn.classList.remove('active');
					});
					this.classList.add('active');
				}
			}, filterLabels[filter]);
		});

		var tableBody = E('tbody', { 'id': 'domain-table-body' });
		var currentSortColumn = 4; // Default sort by Total (index 4)
		var currentSortDirection = 'desc';

		function setSortedColumn(sorting) {
			var sorted = document.querySelector('.th.sorted') || sorting;

			if (sorting.isSameNode(sorted)) {
				sorting.classList.toggle('ascent');
			} else {
				sorting.classList.add('sorted');
				sorted.classList.remove('sorted', 'ascent');
			}
		}

		function sortDomains(domains, column, direction) {
			var sorted = domains.slice(); // Copy array
			sorted.sort(function(a, b) {
				var aVal, bVal;
				switch(column) {
					case 0: // Rank - don't sort, it's auto-generated
						return 0;
					case 1: // Domain
						aVal = a.domain;
						bVal = b.domain;
						break;
					case 2: // Download
						aVal = a.download;
						bVal = b.download;
						break;
					case 3: // Upload
						aVal = a.upload;
						bVal = b.upload;
						break;
					case 4: // Total
						aVal = a.total;
						bVal = b.total;
						break;
					case 5: // Last Seen
						aVal = a.last_seen;
						bVal = b.last_seen;
						break;
					default:
						return 0;
				}

				if (typeof aVal === 'string') {
					return direction === 'asc' ? aVal.localeCompare(bVal) : bVal.localeCompare(aVal);
				} else {
					return direction === 'asc' ? aVal - bVal : bVal - aVal;
				}
			});
			return sorted;
		}

		function updateTable(domains) {
			// Filter domains with recorded traffic
			var filteredDomains = domains.filter(function(domain) {
				return domain.total > 0;
			});
			dom.content(warningBox, warning);
			warningBox.style.display = warning ? '' : 'none';

			// Sort domains
			var sortedDomains = sortDomains(filteredDomains, currentSortColumn, currentSortDirection);

			// Calculate totals
			var totalTraffic = 0, totalDownload = 0, totalUpload = 0;

			sortedDomains.forEach(function(domain) {
				totalTraffic += domain.total;
				totalDownload += domain.download || 0;
				totalUpload += domain.upload || 0;
			});

			var rows = filteredDomains.length === 0
				? [E('tr', {}, E('td', { 'colspan': 6 }, _('No domain data available')))]
				: sortedDomains.map(function(domain, index) {
					return E('tr', {}, [
						E('td', {}, (index + 1).toString()),
						E('td', {}, domain.domain),
						E('td', {}, formatBytes(domain.download || 0)),
						E('td', {}, formatBytes(domain.upload || 0)),
						E('td', {}, formatBytes(domain.total)),
						E('td', {}, formatTime(domain.last_seen))
					]);
				});

			// Add totals row if we have data
			if (filteredDomains.length > 0) {
				rows.push(E('tr', { 'class': 'table-totals' }, [
					E('td', { 'colspan': 2 }, _('TOTAL')),
					E('td', {}, formatBytes(totalDownload)),
					E('td', {}, formatBytes(totalUpload)),
					E('td', {}, formatBytes(totalTraffic)),
					E('td', {}, '')
				]));
			}

			dom.content(tableBody, rows);
		}

		function refreshData() {
			callGetTopDomains(currentFilter, 1000).then(function(result) {
				domains = result.domains || [];
				warning = result.warning || '';
				updateTable(domains);
				labelUpdated.textContent = _('Last updated: ') + new Date().toLocaleTimeString();
			});
		}

		// Add polling for auto-refresh every 5 seconds
		poll.add(refreshData, 5);

		// Initial data load
		updateTable(domains);

		// Create sortable headers
		var headers = [
			E('th', { 'class': 'th' }, _('Rank')),
			E('th', {
				'class': 'th',
				'click': function(ev) {
					setSortedColumn(ev.target);
					currentSortColumn = 1;
					currentSortDirection = ev.target.classList.contains('ascent') ? 'asc' : 'desc';
					updateTable(domains);
				}
			}, _('Domain')),
			E('th', {
				'class': 'th',
				'click': function(ev) {
					setSortedColumn(ev.target);
					currentSortColumn = 2;
					currentSortDirection = ev.target.classList.contains('ascent') ? 'asc' : 'desc';
					updateTable(domains);
				}
			}, _('Download')),
			E('th', {
				'class': 'th',
				'click': function(ev) {
					setSortedColumn(ev.target);
					currentSortColumn = 3;
					currentSortDirection = ev.target.classList.contains('ascent') ? 'asc' : 'desc';
					updateTable(domains);
				}
			}, _('Upload')),
			E('th', {
				'class': 'th sorted',
				'click': function(ev) {
					setSortedColumn(ev.target);
					currentSortColumn = 4;
					currentSortDirection = ev.target.classList.contains('ascent') ? 'asc' : 'desc';
					updateTable(domains);
				}
			}, _('Total')),
			E('th', {
				'class': 'th',
				'click': function(ev) {
					setSortedColumn(ev.target);
					currentSortColumn = 5;
					currentSortDirection = ev.target.classList.contains('ascent') ? 'asc' : 'desc';
					updateTable(domains);
				}
			}, _('Last Seen'))
		];

		return E('div', { 'class': 'cbi-map zbt-app zbt-traffic' }, [
			E('h2', {}, _('Top 1000 Domains - All Devices')),
			labelUpdated,
			warningBox,
			E('div', { 'class': 'date-filter-buttons' }, filterButtons),
			E('table', { 'class': 'table' }, [
				E('thead', {}, [
					E('tr', {}, headers)
				]),
				tableBody
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
