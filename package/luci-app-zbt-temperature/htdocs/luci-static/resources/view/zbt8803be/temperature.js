'use strict';
'require view';
'require fs';
'require poll';
'require dom';
'require ui';

const DATA_FILE = '/var/log/zbt-temperature/readings.csv';
const LOGGER = '/usr/sbin/zbt-temperature-log';
const COLORS = [ '#e53935', '#1e88e5', '#43a047', '#fb8c00', '#8e24aa', '#00acc1', '#6d4c41', '#3949ab', '#7cb342', '#d81b60', '#00897b', '#f4511e', '#5e35b1', '#039be5', '#c0ca33', '#757575' ];
const CHART_HEIGHT = 320;
const CHART_MARGIN = { left: 52, right: 18, top: 18, bottom: 38 };
const TEMP_LIMITS = [
	{ group: 'modem', pattern: /^(sdr|mmw)/i, limit: 75 },
	{ group: 'modem', pattern: /^(aoss|ctile|sys-therm)/i, limit: 80 },
	{ group: 'modem', pattern: /^(cpuss|ethphy|mvmss|mdmq6|mdmss)/i, limit: 85 },
	{ group: 'modem', pattern: /.*/, limit: 80 },
	{ group: 'wifi', pattern: /.*/, limit: 85 },
	{ group: 'system', pattern: /cpu|thermal|soc/i, limit: 90 }
];
const RANGES = [
	[ 3600, _('Last hour') ],
	[ 21600, _('Last 6 hours') ],
	[ 86400, _('Last 24 hours') ],
	[ 604800, _('Last 7 days (1 min points)') ],
	[ 0, _('All data') ]
];

let selectedRange = 604800;
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

function pad2(v) {
	return (v < 10 ? '0' : '') + v;
}

function formatTime(epoch) {
	const d = new Date(epoch * 1000);
	return pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
}

function formatShortTime(epoch) {
	const d = new Date(epoch * 1000);
	if (selectedRange > 86400 || selectedRange === 0)
		return pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
	return pad2(d.getHours()) + ':' + pad2(d.getMinutes());
}

function parseRows(text) {
	const map = {};
	const lines = String(text || '').trim().split(/\n+/);

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		if (!line || line.indexOf('epoch,') === 0)
			continue;

		const parts = line.split(',');
		if (parts.length < 5)
			continue;

		const epoch = Math.floor(parseInt(parts[0], 10) / 60) * 60;
		const group = parts[1];
		const hasUnit = /^[A-Za-z%°/]+$/.test(parts[parts.length - 1]);
		if (!hasUnit)
			continue;
		const valueIndex = parts.length - 2;
		const name = parts.slice(2, valueIndex).join(',');
		const value = parseFloat(parts[valueIndex]);
		const unit = parts[parts.length - 1];

		if (!epoch || !group || !name || isNaN(value))
			continue;

		map[epoch + '\t' + group + '\t' + name] = {
			epoch: epoch,
			group: group,
			name: name,
			value: value,
			unit: unit
		};
	}

	return Object.keys(map).map(function(k) { return map[k]; }).sort(function(a, b) {
		if (a.epoch !== b.epoch)
			return a.epoch - b.epoch;
		if (a.group !== b.group)
			return a.group < b.group ? -1 : 1;
		return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
	});
}

function filterRows(rows) {
	if (!rows.length || !selectedRange)
		return rows;

	const latest = rows.reduce(function(max, row) {
		return row.epoch > max ? row.epoch : max;
	}, 0);
	const cutoff = latest - selectedRange;
	return rows.filter(function(row) { return row.epoch >= cutoff; });
}

function uniqueValues(rows, field) {
	const seen = {};
	const out = [];
	rows.forEach(function(row) {
		if (!seen[row[field]]) {
			seen[row[field]] = true;
			out.push(row[field]);
		}
	});
	return out.sort();
}

function groupTitle(group) {
	switch (group) {
	case 'fan': return _('Fan');
	case 'modem': return _('Modem');
	case 'wifi': return _('WiFi radios');
	case 'system': return _('System');
	default: return group;
	}
}

function sensorStats(rows) {
	const stats = {};
	rows.forEach(function(row) {
		const key = row.group + '\t' + row.name;
		if (!stats[key]) {
			stats[key] = {
				group: row.group,
				name: row.name,
				unit: row.unit || 'C',
				min: row.value,
				max: row.value,
				latest: row.value,
				latestEpoch: row.epoch
			};
		}
		stats[key].min = Math.min(stats[key].min, row.value);
		stats[key].max = Math.max(stats[key].max, row.value);
		if (row.epoch >= stats[key].latestEpoch) {
			stats[key].latest = row.value;
			stats[key].latestEpoch = row.epoch;
		}
	});
	return Object.keys(stats).map(function(k) { return stats[k]; }).sort(function(a, b) {
		if (a.group !== b.group)
			return a.group < b.group ? -1 : 1;
		return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
	});
}

function unitSuffix(unit) {
	return unit === '%' ? '%' : '°C';
}

function sensorLimit(group, name, unit) {
	if (unit === '%')
		return null;

	for (let i = 0; i < TEMP_LIMITS.length; i++) {
		const rule = TEMP_LIMITS[i];
		if (rule.group === group && rule.pattern.test(name))
			return rule.limit;
	}

	return null;
}

function chartLimits(chart) {
	const limits = {};

	chart.names.forEach(function(name) {
		const limit = sensorLimit(chart.group, name, chart.sensorUnits[name] || chart.unit);
		if (limit !== null)
			limits[limit] = true;
	});

	return Object.keys(limits).map(function(v) { return parseFloat(v); }).sort(function(a, b) { return a - b; });
}

function nearestPoint(series, epoch) {
	let best = null;
	let bestDelta = Infinity;

	for (let i = 0; i < series.length; i++) {
		const delta = Math.abs(series[i].epoch - epoch);
		if (delta < bestDelta) {
			best = series[i];
			bestDelta = delta;
		}
	}

	return bestDelta <= 90 ? best : null;
}

function drawChart(canvas, chart, retry) {
	retry = retry || 0;

	const rect = canvas.getBoundingClientRect();
	const width = Math.floor(rect.width || canvas.parentNode.clientWidth || 0);
	if (width < 120 && retry < 20) {
		window.setTimeout(function() {
			drawChart(canvas, chart, retry + 1);
		}, 100);
		return;
	}

	const dpr = window.devicePixelRatio || 1;
	const h = CHART_HEIGHT;
	const w = Math.max(320, width || 900);
	canvas.width = Math.floor(w * dpr);
	canvas.height = Math.floor(h * dpr);
	canvas.style.height = h + 'px';

	const ctx = canvas.getContext('2d');
	ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
	ctx.clearRect(0, 0, w, h);

	const style = window.getComputedStyle(canvas);
	const textColor = style.color || '#ddd';
	const gridColor = style.borderTopColor || 'rgba(128,128,128,0.3)';
	const ml = CHART_MARGIN.left;
	const mr = CHART_MARGIN.right;
	const mt = CHART_MARGIN.top;
	const mb = CHART_MARGIN.bottom;
	const pw = w - ml - mr;
	const ph = h - mt - mb;
	const spanT = Math.max(60, chart.maxT - chart.minT);
	const spanV = Math.max(1, chart.maxV - chart.minV);

	function x(t) { return ml + ((t - chart.minT) / spanT) * pw; }
	function y(v) { return mt + (1 - ((v - chart.minV) / spanV)) * ph; }

	ctx.font = '12px sans-serif';
	ctx.lineWidth = 1;
	ctx.strokeStyle = gridColor;
	ctx.fillStyle = textColor;
	ctx.globalAlpha = 0.55;

	for (let i = 0; i <= 4; i++) {
		const v = chart.minV + (spanV * i / 4);
		const yy = y(v);
		ctx.beginPath();
		ctx.moveTo(ml, yy);
		ctx.lineTo(w - mr, yy);
		ctx.stroke();
		ctx.fillText(v.toFixed(0) + unitSuffix(chart.unit), 6, yy + 4);
	}

	ctx.textAlign = 'center';
	[ chart.minT, Math.round((chart.minT + chart.maxT) / 2), chart.maxT ].forEach(function(t) {
		ctx.fillText(formatShortTime(t), x(t), h - 12);
	});

	const limits = chartLimits(chart);
	if (limits.length) {
		ctx.save();
		ctx.strokeStyle = '#d32f2f';
		ctx.fillStyle = '#d32f2f';
		ctx.setLineDash([ 7, 5 ]);
		ctx.globalAlpha = 0.85;
		ctx.textAlign = 'right';
		limits.forEach(function(limit) {
			const yy = y(limit);
			ctx.beginPath();
			ctx.moveTo(ml, yy);
			ctx.lineTo(w - mr, yy);
			ctx.stroke();
			ctx.fillText(_('avoid') + ' ' + limit.toFixed(0) + '°C', w - mr - 4, yy - 5);
		});
		ctx.restore();
	}

	ctx.globalAlpha = 1;
	chart.names.forEach(function(name, idx) {
		const series = chart.series[name] || [];
		if (!series.length)
			return;

		ctx.beginPath();
		ctx.strokeStyle = COLORS[idx % COLORS.length];
		ctx.lineWidth = 2;

		series.forEach(function(row, n) {
			const xx = x(row.epoch);
			const yy = y(row.value);
			if (n === 0)
				ctx.moveTo(xx, yy);
			else
				ctx.lineTo(xx, yy);
		});

		ctx.stroke();
	});

	if (chart.hoverEpoch) {
		const hoverX = x(chart.hoverEpoch);
		ctx.save();
		ctx.strokeStyle = textColor;
		ctx.globalAlpha = 0.45;
		ctx.lineWidth = 1;
		ctx.beginPath();
		ctx.moveTo(hoverX, mt);
		ctx.lineTo(hoverX, mt + ph);
		ctx.stroke();
		ctx.restore();
	}
}

function scheduleChartDraw(canvas, chart) {
	window.setTimeout(function() {
		drawChart(canvas, chart, 0);
	}, 0);
}

function bindChartHover(canvas, tooltip, chart) {
	function update(ev) {
		const rect = canvas.getBoundingClientRect();
		const width = rect.width || canvas.parentNode.clientWidth || 900;
		const ml = CHART_MARGIN.left;
		const mr = CHART_MARGIN.right;
		const pw = width - ml - mr;
		const spanT = Math.max(60, chart.maxT - chart.minT);
		const localX = ev.clientX - rect.left;

		if (localX < ml || localX > width - mr) {
			chart.hoverEpoch = null;
			tooltip.style.display = 'none';
			drawChart(canvas, chart, 0);
			return;
		}

		const epoch = Math.round((chart.minT + ((localX - ml) / pw) * spanT) / 60) * 60;
		const values = [];

		chart.names.forEach(function(name, idx) {
			const point = nearestPoint(chart.series[name] || [], epoch);
			if (point) {
				const limit = sensorLimit(point.group, point.name, point.unit || chart.unit);
				values.push(E('div', { 'style': 'white-space:nowrap' }, [
					E('span', { 'style': 'display:inline-block;width:0.75em;height:0.75em;border-radius:50%;background:' + COLORS[idx % COLORS.length] + ';margin-right:0.35em' }),
					name + ': ' + point.value.toFixed(1) + unitSuffix(point.unit || chart.unit) + (limit !== null ? ' / ' + _('limit') + ' ' + limit.toFixed(0) + '°C' : '')
				]));
			}
		});

		chart.hoverEpoch = epoch;
		dom.content(tooltip, [
			E('strong', {}, formatTime(epoch)),
			values.length ? E('div', { 'style': 'margin-top:0.35em' }, values) : E('div', { 'style': 'margin-top:0.35em' }, _('No sample at this minute'))
		]);
		tooltip.style.display = 'block';
		tooltip.style.left = Math.min(Math.max(8, localX + 14), Math.max(8, width - 260)) + 'px';
		tooltip.style.top = '12px';
		drawChart(canvas, chart, 0);
	}

	canvas.addEventListener('mousemove', update);
	canvas.addEventListener('mouseleave', function() {
		chart.hoverEpoch = null;
		tooltip.style.display = 'none';
		drawChart(canvas, chart, 0);
	});
}

function renderChart(group, rows, chartMinT, chartMaxT) {
	const groupRows = rows.filter(function(row) { return row.group === group; });
	if (!groupRows.length)
		return E('div', { 'class': 'cbi-section' }, [ E('h3', groupTitle(group)), E('p', {}, _('No readings yet.')) ]);

	const names = uniqueValues(groupRows, 'name');
	const unit = groupRows[0].unit || 'C';
	const sensorUnits = {};
	const values = groupRows.map(function(row) { return row.value; });
	const groupLatest = groupRows.reduce(function(m, row) { return row.epoch > m ? row.epoch : m; }, 0);
	const groupEarliest = groupRows.reduce(function(m, row) { return row.epoch < m ? row.epoch : m; }, groupLatest);
	const minT = (typeof chartMinT === 'number' && chartMinT > 0) ? chartMinT : groupEarliest;
	const maxT = (typeof chartMaxT === 'number' && chartMaxT > 0) ? chartMaxT : groupLatest;
	let minV = Math.min.apply(null, values);
	let maxV = Math.max.apply(null, values);

	groupRows.forEach(function(row) {
		sensorUnits[row.name] = row.unit || 'C';
		const limit = sensorLimit(row.group, row.name, row.unit || 'C');
		if (limit !== null)
			maxV = Math.max(maxV, limit);
	});

	if (minV === maxV) {
		minV -= 1;
		maxV += 1;
	} else {
		const pad = Math.max(1, (maxV - minV) * 0.1);
		minV = Math.floor(minV - pad);
		maxV = Math.ceil(maxV + pad);
	}

	const canvas = E('canvas', {
		'style': 'display:block;width:100%;height:' + CHART_HEIGHT + 'px;border:1px solid rgba(128,128,128,0.25);border-radius:8px;background:rgba(128,128,128,0.04);box-sizing:border-box;color:inherit'
	});
	const tooltip = E('div', {
		'style': 'display:none;position:absolute;z-index:5;min-width:220px;max-width:320px;padding:0.65em 0.75em;border-radius:8px;background:rgba(20,20,20,0.92);color:#fff;box-shadow:0 2px 12px rgba(0,0,0,0.35);font-size:12px;pointer-events:none'
	});
	const series = {};
	names.forEach(function(name, idx) {
		series[name] = groupRows.filter(function(row) { return row.name === name; }).sort(function(a, b) { return a.epoch - b.epoch; });
	});
	const chart = {
		group: group,
		names: names,
		series: series,
		sensorUnits: sensorUnits,
		minT: minT,
		maxT: maxT,
		groupLatest: groupLatest,
		minV: minV,
		maxV: maxV,
		unit: unit
	};
	scheduleChartDraw(canvas, chart);
	bindChartHover(canvas, tooltip, chart);

	const legendItems = names.map(function(name, idx) {
		return E('span', { 'style': 'display:inline-flex;align-items:center;gap:0.35em' }, [
			E('span', { 'style': 'display:inline-block;width:0.9em;height:0.9em;border-radius:50%;background:' + COLORS[idx % COLORS.length] }),
			name
		]);
	});
	chartLimits(chart).forEach(function(limit) {
		legendItems.push(E('span', { 'style': 'display:inline-flex;align-items:center;gap:0.35em;color:#d32f2f' }, [
			E('span', { 'style': 'display:inline-block;width:1.2em;border-top:2px dashed #d32f2f' }),
			_('Avoid limit') + ' ' + limit.toFixed(0) + '°C'
		]));
	});
	const legend = E('div', { 'style': 'display:flex;flex-wrap:wrap;gap:0.5em 1em;margin-top:0.75em' }, legendItems);

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', groupTitle(group)),
		E('div', { 'style': 'position:relative;width:100%' }, [ canvas, tooltip ]),
		legend
	]);
}

function renderStats(rows) {
	const stats = sensorStats(rows);
	const tableRows = [ E('tr', { 'class': 'tr table-titles' }, [
		E('th', { 'class': 'th' }, _('Group')),
		E('th', { 'class': 'th' }, _('Sensor')),
		E('th', { 'class': 'th' }, _('Latest')),
		E('th', { 'class': 'th' }, _('Avoid limit')),
		E('th', { 'class': 'th' }, _('Headroom')),
		E('th', { 'class': 'th' }, _('Min')),
		E('th', { 'class': 'th' }, _('Max')),
		E('th', { 'class': 'th' }, _('Updated'))
	]) ];

	stats.forEach(function(s) {
		const limit = sensorLimit(s.group, s.name, s.unit);
		const headroom = limit !== null ? limit - s.latest : null;
		tableRows.push(E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, groupTitle(s.group)),
			E('td', { 'class': 'td' }, s.name),
			E('td', { 'class': 'td' }, s.latest.toFixed(1) + unitSuffix(s.unit)),
			E('td', { 'class': 'td' }, limit !== null ? limit.toFixed(0) + '°C' : '-'),
			E('td', { 'class': 'td', 'style': headroom !== null && headroom <= 0 ? 'color:#d32f2f;font-weight:bold' : null }, headroom !== null ? headroom.toFixed(1) + '°C' : '-'),
			E('td', { 'class': 'td' }, s.min.toFixed(1) + unitSuffix(s.unit)),
			E('td', { 'class': 'td' }, s.max.toFixed(1) + unitSuffix(s.unit)),
			E('td', { 'class': 'td' }, formatTime(s.latestEpoch))
		]));
	});

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', _('Summary')),
		E('table', { 'class': 'table cbi-section-table' }, tableRows)
	]);
}

function renderContent(rows) {
	const filtered = filterRows(rows);
	const groups = uniqueValues(filtered, 'group');
	const latest = filtered.length ? filtered[filtered.length - 1].epoch : 0;
	const earliest = filtered.length ? filtered[0].epoch : 0;
	const chartMaxT = latest;
	const chartMinT = selectedRange > 0 && latest > 0 ? latest - selectedRange : earliest;
	const modemSeen = filtered.some(function(row) { return row.group === 'modem'; });
	const blocks = [];

	if (!filtered.length) {
		blocks.push(E('div', { 'class': 'alert-message warning' }, _('No temperature readings yet. Wait one minute or press Refresh.')));
		return E([], blocks);
	}

	blocks.push(E('p', { 'class': 'cbi-section-descr' }, _('Readings are sampled once per minute and persisted across reboots up to seven days. Each chart spans the selected range with one raw point per minute per sensor. Last sample:') + ' ' + formatTime(latest) + '.'));

	if (!modemSeen)
		blocks.push(E('div', { 'class': 'alert-message warning' }, _('No modem temperature readings detected. The modem AT port may be busy or unavailable.')));

	[ 'modem', 'fan', 'wifi', 'system' ].forEach(function(group) {
		if (groups.indexOf(group) !== -1)
			blocks.push(renderChart(group, filtered, chartMinT, chartMaxT));
	});
	groups.forEach(function(group) {
		if ([ 'modem', 'fan', 'wifi', 'system' ].indexOf(group) === -1)
			blocks.push(renderChart(group, filtered, chartMinT, chartMaxT));
	});
	blocks.push(renderStats(filtered));

	return E([], blocks);
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
		const rows = parseRows(text);
		if (contentNode)
			dom.content(contentNode, renderContent(rows));
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
		const rangeSelect = E('select', { 'class': 'cbi-input-select' }, RANGES.map(function(r) {
			return E('option', { 'value': r[0], 'selected': r[0] === selectedRange ? 'selected' : null }, r[1]);
		}));

		rangeSelect.addEventListener('change', function() {
			selectedRange = parseInt(rangeSelect.value, 10);
			refresh(false);
		});

		statusNode = E('span', {}, _('OK'));
		contentNode = E('div', {}, renderContent(parseRows(text)));

		poll.add(function() {
			return refresh(true);
		}, 60);

		return E('div', { 'class': 'cbi-map zbt-app zbt-temperature' }, [
			E('h2', _('Temperature Monitor')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:0.75em' }, [
					E('label', {}, [ _('Range'), ' ', rangeSelect ]),
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
