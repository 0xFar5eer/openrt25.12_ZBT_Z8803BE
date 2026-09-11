'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('MLO editor rewrites legacy per-band records as one shared multi-radio iface', () => {
  const tree = process.env.MLO_TEST_TREE;
  assert.ok(tree, 'MLO_TEST_TREE is required');
  const file = path.join(tree, 'htdocs/luci-static/resources/view/mlo/main.js');
  const source = fs.readFileSync(file, 'utf8');
  const boundary = source.indexOf('\nreturn view.extend({');
  assert.ok(boundary > 0, 'unable to isolate MLO model functions');

  const wifiDevices = [
    { '.type': 'wifi-device', '.name': 'radio0', band: '2g' },
    { '.type': 'wifi-device', '.name': 'radio1', band: '5g' },
    { '.type': 'wifi-device', '.name': 'radio2', band: '6g' }
  ];
  let ifaces = [
    { '.type': 'wifi-iface', '.name': 'old_2g', device: 'radio0', mode: 'ap', network: 'lan', ssid: 'Fostah Logistics', encryption: 'sae', key: 'test-password', mlo: '1' },
    { '.type': 'wifi-iface', '.name': 'old_5g', device: 'radio1', mode: 'ap', network: 'lan', ssid: 'Fostah Logistics', encryption: 'sae', key: 'test-password', mlo: '1' },
    { '.type': 'wifi-iface', '.name': 'old_6g', device: 'radio2', mode: 'ap', network: 'lan', ssid: 'Fostah Logistics', encryption: 'sae', key: 'test-password', mlo: '1' }
  ];
  const uci = {
    sections(config, type) {
      assert.equal(config, 'wireless');
      return (type === 'wifi-device' ? wifiDevices : ifaces).slice();
    },
    get(config, section, option) {
      assert.equal(config, 'wireless');
      const row = wifiDevices.concat(ifaces).find(x => x['.name'] === section);
      return row && row[option];
    },
    add(config, type, name) {
      assert.equal(config, 'wireless');
      assert.equal(type, 'wifi-iface');
      assert.ok(!ifaces.some(x => x['.name'] === name), `duplicate section ${name}`);
      ifaces.push({ '.type': type, '.name': name });
      return name;
    },
    set(config, section, option, value) {
      assert.equal(config, 'wireless');
      const row = ifaces.find(x => x['.name'] === section);
      assert.ok(row, `missing section ${section}`);
      row[option] = value;
    },
    remove(config, section) {
      assert.equal(config, 'wireless');
      ifaces = ifaces.filter(x => x['.name'] !== section);
    }
  };

  const api = new Function('uci', source.slice(0, boundary) + '\nreturn { loadMlds, applyMld };')(uci);
  const before = api.loadMlds().mlds['Fostah Logistics'];
  assert.deepEqual(Array.from(before.bands).sort(), [ '2g', '5g', '6g' ]);
  api.applyMld(before);

  const mlo = ifaces.filter(x => x.mlo === '1');
  assert.equal(mlo.length, 1, 'one logical MLD must be one wifi-iface');
  assert.deepEqual(mlo[0].device, [ 'radio0', 'radio1', 'radio2' ]);
  assert.equal(mlo[0].ieee80211w, '2');
  assert.equal(mlo[0].ssid, 'Fostah Logistics');
  assert.equal(mlo[0].network, 'lan');

  const migration = fs.readFileSync(path.join(__dirname, '../files/etc/uci-defaults/74-zbt-mlo-shared-iface-repair'), 'utf8');
  assert.match(migration, /add_list "wireless\.\$\{first\}\.network=lan"/);
  assert.doesNotMatch(migration, /wifi reload|zbt-wifi-reload-deferred/);
  const builder = fs.readFileSync(path.join(__dirname, '../docker/build-openwrt.sh'), 'utf8');
  assert.match(builder, /make package\/luci-app-mlo\/clean/);
  assert.match(builder, /rsync -a --delete "\$\{FILES_OVERLAY_DIR\}\/?" files\//);
});
