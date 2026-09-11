'use strict';
// Host fixtures never touch router state. Real packet tests are opt-in and
// must run in a disposable container/network namespace (see Sanity workflow).
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zbt-ttl-test-'));
after(() => fs.rmSync(temporary, { recursive: true, force: true }));
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const library = read('firmware/files/usr/lib/zbt/dual-modem.sh') + '\n' +
  read('firmware/files/usr/lib/zbt/ttl.sh').replace('. /usr/lib/zbt/dual-modem.sh', '');
const uciMock = `
uci() {
  [ "$1" != -q ] || shift
  case "$1" in
    get) [ -f "$DB/$2" ] && cat "$DB/$2" ;;
    set) printf '%s\\n' "\${2#*=}" > "$DB/\${2%%=*}" ;;
    delete) rm -f "$DB/$2" ;;
    commit) : ;;
    *) return 1 ;;
  esac
}
logger() { :; }
ip() { [ ! -f "$DB/address.$6" ] || printf '1: %s inet %s scope global\\n' "$6" "$(cat "$DB/address.$6")"; }
lock() { :; }
fw4() {
  echo "$*" >> "$CALLS"
  [ "$FAIL_FW4" != 1 ] || return 1
  cp "$ZBT_TTL_RUN/active.nft" "$LIVE"
}
`;
function command(bin, args, options = {}) {
  const r = spawnSync(bin, args, { encoding: 'utf8', timeout: 15000, ...options });
  assert.ifError(r.error);
  assert.equal(r.status, 0, r.stderr + '\n' + r.stdout);
  return r.stdout.trim();
}
function fixture() {
  const dir = fs.mkdtempSync(path.join(temporary, 'case-'));
  const sys = path.join(dir, 'sys'), etc = path.join(dir, 'etc'), db = path.join(dir, 'db');
  fs.mkdirSync(db);
  fs.mkdirSync(path.join(etc, 'nftables.d'), { recursive: true });
  const write = (p, value) => {
    fs.mkdirSync(path.dirname(path.join(sys, p)), { recursive: true });
    fs.writeFileSync(path.join(sys, p), String(value));
  };
  // Primary deliberately is not wwan0. The secondary is; no guessing allowed.
  for (const [usb, dev, index] of [['4-1', 'wwan8', 71], ['2-1', 'wwan0', 19]]) {
    fs.mkdirSync(path.join(sys, 'bus/usb/devices', usb, usb + ':1.4/net', dev), { recursive: true });
    write('class/net/' + dev + '/ifindex', index);
  }
  const set = (key, value) => fs.writeFileSync(path.join(db, key), String(value));
  const get = key => fs.readFileSync(path.join(db, key), 'utf8').trim();
  const env = { ...process.env, DB: db, ZBT_SYSFS: sys, ZBT_TTL_ETC: etc,
    ZBT_TTL_RUN: path.join(dir, 'run'), CALLS: path.join(dir, 'calls'), LIVE: path.join(dir, 'live') };
  function run(body, args = [], expected = 0, extra = {}) {
    const r = spawnSync('busybox', ['sh', '-c', uciMock + library + '\n' + body, 'test', ...args], {
      encoding: 'utf8', timeout: 10000, env: { ...env, ...extra }
    });
    assert.ifError(r.error);
    assert.equal(r.status, expected, r.stderr + '\n' + r.stdout);
    return r.stdout.trim();
  }
  const worker = read('firmware/files/usr/sbin/zbt-qmodem-ttl')
    .replace('. /usr/lib/zbt/ttl.sh', '').replaceAll('/var/lock', path.join(dir, 'lock'));
  return { dir, sys, etc, db, env, set, get, write, run,
    render: (expected = 0) => run('zbt_ttl_render', [], expected),
    worker: (action, expected = 0, extra = {}) => run(worker, [action], expected, extra) };
}
function policies(f, first, second) {
  for (const [id, value] of [['4_1', first], ['2_1', second]]) {
    f.set('qmodem_ttl.' + id, 'modem');
    f.set(`qmodem_ttl.${id}.enable`, value === null ? 0 : 1);
    f.set(`qmodem_ttl.${id}.ttl`, value === null ? 64 : value);
    f.set(`qmodem_ttl.${id}.mode`, 'manual');
  }
}
function legacyRule(ttl) {
  return '# Seeded by old firmware\nchain postrouting {\n\ttype filter hook postrouting priority mangle; policy accept;\n' +
    `\toifname "wwan0" ip ttl set ${ttl}\n\toifname "wwan0" ip6 hoplimit set ${ttl}\n}\n`;
}

test('TTL policies independently support neither, either, or both modems with different values', () => {
  for (const [one, two] of [[null, null], [65, null], [null, 128], [65, 128]]) {
    const f = fixture();
    policies(f, one, two);
    const rules = f.render();
    for (const [id, index, value] of [['4_1', 71, one], ['2_1', 19, two]]) {
      if (value === null) assert.doesNotMatch(rules, new RegExp('QModem ' + id));
      else {
        assert.ok(rules.includes(`meta oif ${index} ip ttl set ${value} comment "QModem ${id} IPv4"`));
        assert.ok(rules.includes(`meta oif ${index} ip6 hoplimit set ${value} comment "QModem ${id} IPv6"`));
      }
    }
    assert.doesNotMatch(rules, /oifname|iifname|br-lan|eth1|wwan0/);
  }
});

test('missing or ambiguous modem never uses its peer; reconnect binds the new ifindex', () => {
  const f = fixture(); policies(f, 65, 128);
  fs.rmSync(path.join(f.sys, 'bus/usb/devices/4-1'), { recursive: true });
  assert.doesNotMatch(f.render(), /QModem 4_1/);
  assert.match(f.render(), /meta oif 19 ip ttl set 128/);
  fs.mkdirSync(path.join(f.sys, 'bus/usb/devices/2-1/2-1:1.4/net/ambiguous'), { recursive: true });
  assert.doesNotMatch(f.render(), /ttl set/);
  fs.rmdirSync(path.join(f.sys, 'bus/usb/devices/2-1/2-1:1.4/net/ambiguous'));
  f.write('class/net/wwan0/ifindex', 93);
  assert.match(f.render(), /meta oif 93 ip ttl set 128/);
  assert.doesNotMatch(f.render(), /meta oif 19 /);
});

test('TTL validates both slots, rejects malformed values and keeps last good rules on error', () => {
  const f = fixture(); policies(f, 65, 128);
  f.worker('start');
  const old = fs.readFileSync(f.env.LIVE, 'utf8');
  for (const value of ['', '0', '256', '-1', '65; accept', '1.5', '064']) {
    f.set('qmodem_ttl.2_1.ttl', value);
    f.worker('refresh', 1);
    assert.equal(fs.readFileSync(f.env.LIVE, 'utf8'), old);
    assert.equal(fs.readFileSync(path.join(f.env.ZBT_TTL_RUN, 'active.nft'), 'utf8'), old);
  }
});

test('refresh is idempotent, disabling one leaves its peer, and stopping clears all rules', () => {
  const f = fixture(); policies(f, 65, 128);
  f.set('firewall.@defaults[0].flow_offloading', 1);
  f.set('firewall.@defaults[0].flow_offloading_hw', 1);
  f.worker('start');
  assert.equal(f.get('firewall.@defaults[0].flow_offloading'), '0');
  assert.equal(f.get('firewall.@defaults[0].flow_offloading_hw'), '0');
  f.worker('refresh');
  assert.equal(fs.readFileSync(f.env.CALLS, 'utf8'), 'reload\n');
  f.set('qmodem_ttl.4_1.enable', 0);
  f.worker('refresh');
  assert.doesNotMatch(fs.readFileSync(f.env.LIVE, 'utf8'), /QModem 4_1/);
  assert.match(fs.readFileSync(f.env.LIVE, 'utf8'), /QModem 2_1/);
  f.worker('stop');
  assert.doesNotMatch(fs.readFileSync(f.env.LIVE, 'utf8'), /ttl set|hoplimit set/);
  f.worker('refresh');
  assert.equal(fs.readFileSync(f.env.CALLS, 'utf8'), 'reload\nreload\nreload\n');
  assert.equal(f.get('firewall.@defaults[0].flow_offloading'), '0', 'never re-enable offloading behind the user');
});

test('failed atomic firewall update restores its include and previous offload settings', () => {
  const f = fixture(); policies(f, null, null); f.worker('start');
  const old = fs.readFileSync(f.env.LIVE, 'utf8');
  f.set('qmodem_ttl.2_1.enable', 1);
  f.set('firewall.@defaults[0].flow_offloading', 1);
  f.set('firewall.@defaults[0].flow_offloading_hw', 1);
  f.worker('refresh', 1, { FAIL_FW4: '1' });
  assert.equal(fs.readFileSync(f.env.LIVE, 'utf8'), old);
  assert.equal(fs.readFileSync(path.join(f.env.ZBT_TTL_RUN, 'active.nft'), 'utf8'), old);
  assert.equal(f.get('firewall.@defaults[0].flow_offloading'), '1');
  assert.equal(f.get('firewall.@defaults[0].flow_offloading_hw'), '1');
});

test('new installations retain primary auto TTL; explicit global settings migrate once', () => {
  const f = fixture(); f.worker('migrate');
  for (const id of ['4_1', '2_1']) {
    assert.equal(f.get(`qmodem_ttl.${id}.enable`), id === '4_1' ? '1' : '0');
    assert.equal(f.get(`qmodem_ttl.${id}.ttl`), '64');
    assert.equal(f.get(`qmodem_ttl.${id}.mode`), 'auto');
  }
  const upgrade = fixture();
  upgrade.set('qmodem_ttl.main.enable', 1);
  upgrade.set('qmodem_ttl.main.ttl', 66);
  upgrade.worker('migrate');
  for (const id of ['4_1', '2_1']) {
    assert.equal(upgrade.get(`qmodem_ttl.${id}.enable`), '1');
    assert.equal(upgrade.get(`qmodem_ttl.${id}.ttl`), '66');
  }
  upgrade.set('qmodem_ttl.4_1.enable', 0);
  upgrade.set('qmodem_ttl.2_1.ttl', 129);
  upgrade.worker('migrate');
  assert.equal(upgrade.get('qmodem_ttl.4_1.enable'), '0');
  assert.equal(upgrade.get('qmodem_ttl.2_1.ttl'), '129');
  assert.equal(upgrade.get('qmodem_ttl.main.enable'), '0');
  assert.equal(upgrade.get('qmodem_ttl.main.zbt_auto_ttl'), '0');
});

test('automatic recommendations are per modem and never overwrite a custom TTL', () => {
  const f = fixture(); policies(f, 66, 128);
  f.set('qmodem_ttl.4_1.mode', 'auto');
  f.set('address.wwan8', '192.0.0.2/27');
  f.set('address.wwan0', '192.168.225.2/24');
  assert.match(f.render(), /meta oif 71 ip ttl set 65/);
  assert.match(f.render(), /meta oif 19 ip ttl set 128/);
  assert.equal(f.get('qmodem_ttl.4_1.ttl'), '66', 'retain last custom entry while in automatic mode');
  f.set('qmodem_ttl.2_1.mode', 'auto');
  f.set('address.wwan0', '10.55.12.3/29');
  assert.match(f.render(), /meta oif 19 ip ttl set 64/);
  f.set('qmodem_ttl.4_1.mode', 'manual');
  assert.match(f.render(), /meta oif 71 ip ttl set 66/);
});

test('old implicit primary TTL becomes visible; exact legacy files are archived, not deleted', () => {
  const f = fixture(), old = legacyRule(65), custom = '# Custom legacy file preserved for review\n';
  fs.writeFileSync(path.join(f.etc, 'nftables.d/99-tether-ttl.nft'), old);
  fs.writeFileSync(path.join(f.etc, 'nftables.d/99-reset-ttl-from-br-lan.nft'), custom);
  fs.writeFileSync(path.join(f.etc, 'nftables.d/user-firewall.nft'), '# unrelated');
  f.worker('migrate');
  assert.equal(f.get('qmodem_ttl.4_1.enable'), '1');
  assert.equal(f.get('qmodem_ttl.4_1.ttl'), '65');
  assert.equal(f.get('qmodem_ttl.2_1.enable'), '0');
  assert.deepEqual(fs.readdirSync(path.join(f.etc, 'nftables.d')), ['user-firewall.nft']);
  const backups = () => fs.readdirSync(path.join(f.etc, 'qmodem-ttl-backup')).map(n =>
    fs.readFileSync(path.join(f.etc, 'qmodem-ttl-backup', n), 'utf8')).sort();
  assert.deepEqual(backups(), [custom, old].sort());
  f.worker('migrate');
  assert.deepEqual(backups(), [custom, old].sort());
});

test('TTL UI exposes independent modem controls and only writes TTL configuration', async () => {
  const sections = [], loads = [];
  const uci = { load: async name => loads.push(name), get: (p, id, key) => id === '2_1' ? 'Travel SIM' : null };
  const form = { NamedSection: 'named', Flag: 'flag', Value: 'value', ListValue: 'list', DummyValue: 'dummy',
    Map: function() {
      this.section = (type, id, sectionType, title) => {
        const s = { id, title, options: [], option(kind, name) {
          const o = { kind, name, value() {}, depends: (key, value) => o.dependency = value === undefined ? key : [key, value] };
          s.options.push(o); return o;
        } };
        sections.push(s); return s;
      };
      this.render = () => sections;
    } };
  const view = new Function('view', 'form', 'uci', '_', read('firmware/files/www/luci-static/resources/view/qmodem/ttl.js'))(
    { extend: o => o }, form, uci, s => s);
  await view.load(); view.render();
  assert.deepEqual(loads, ['qmodem_ttl', 'qmodem']);
  assert.deepEqual(sections.map(s => s.id), ['4_1', '2_1', 'main']);
  assert.equal(sections[0].title, 'Modem 1');
  assert.equal(sections[1].title, 'Modem 2 — Travel SIM');
  for (const s of sections.slice(0, 2)) {
    assert.deepEqual(s.options.map(o => [o.kind, o.name]), [['flag', 'enable'], ['list', 'mode'], ['value', 'ttl']]);
    const ttl = s.options[2];
    assert.equal(ttl.datatype, 'range(1,255)');
    assert.equal(ttl.retain, true);
    assert.deepEqual(ttl.dependency, { enable: '1', mode: 'manual' });
    assert.equal(ttl.validate(s.id, '65'), true);
    for (const value of ['064', '0', '256', '65;accept']) assert.notEqual(ttl.validate(s.id, value), true);
  }
  const acl = JSON.parse(read('firmware/files/usr/share/rpcd/acl.d/luci-app-qmodem-ttlfw4.json'))['luci-app-qmodem-ttlfw4'];
  assert.deepEqual(acl.write.uci, ['qmodem_ttl']);
  assert.ok(acl.read.uci.includes('qmodem'));
  assert.doesNotMatch(read('firmware/files/etc/hotplug.d/iface/60-zbt-ttl-probe'), /--apply/);
  assert.doesNotMatch(read('firmware/files/etc/uci-defaults/36-zbt-z8803be-wan-speed-mode'), /ttl set/);
  for (const file of ['etc/init.d/qmodem_ttl', 'usr/sbin/zbt-qmodem-ttl', 'usr/lib/zbt/ttl.sh']) {
    assert.doesNotMatch(read('firmware/files/' + file), /qmodem_network\s+(restart|stop|redial)|\/sys\/class\/gpio|AT\+/);
  }
});

test('real IPv4/IPv6 packets get the selected egress TTL only; disabled modem retains TTL 42',
  { skip: process.env.ZBT_TEST_NFT !== '1' }, () => {
    const f = fixture();
    const links = [['qttl1', 'qpeer1', '192.0.2', 'fd42:1', 'wwan8'],
      ['qttl2', 'qpeer2', '198.51.100', 'fd42:2', 'wwan0']];
    try {
      for (const [dev, peer, v4, v6, mocked] of links) {
        command('ip', ['link', 'add', dev, 'type', 'veth', 'peer', 'name', peer]);
        for (const link of [dev, peer]) command('ip', ['link', 'set', link, 'up']);
        command('ip', ['addr', 'add', v4 + '.1/24', 'dev', dev]);
        command('ip', ['-6', 'addr', 'add', v6 + '::1/64', 'dev', dev, 'nodad']);
        const mac = JSON.parse(command('ip', ['-j', 'link', 'show', 'dev', peer]))[0].address;
        for (const target of [v4 + '.2', v6 + '::2'])
          command('ip', ['neigh', 'add', target, 'lladdr', mac, 'nud', 'permanent', 'dev', dev]);
        f.write('class/net/' + mocked + '/ifindex', JSON.parse(command('ip', ['-j', 'link', 'show', 'dev', dev]))[0].ifindex);
      }
      for (const values of [[65, 128], [65, null], [null, 128], [null, null]]) {
        policies(f, ...values);
        const nft = path.join(f.dir, 'test.nft');
        const include = read('firmware/files/etc/nftables.d/99-qmodem-ttl.nft')
          .replace('/var/run/qmodem-ttl', f.env.ZBT_TTL_RUN);
        fs.writeFileSync(nft, 'table inet qmodem_ttl_test {\n' + include + '\n}\n');
        // At first boot the wildcard has no file yet; this must also parse.
        command('nft', ['--check', '-f', nft]);
        fs.mkdirSync(f.env.ZBT_TTL_RUN, { recursive: true });
        fs.writeFileSync(path.join(f.env.ZBT_TTL_RUN, 'active.nft'), f.render() + '\n');
        command('nft', ['--check', '-f', nft]);
        command('nft', ['-f', nft]);
        for (let i = 0; i < links.length; i++) {
          const [dev, peer, v4, v6] = links[i];
          for (const target of [v4 + '.2', v6 + '::2']) {
            const ttl = command('python3', [path.join(__dirname, 'ttl-packet-probe.py'), dev, peer, target]);
            assert.equal(Number(ttl), values[i] === null ? 42 : values[i], `${dev} -> ${target}`);
          }
        }
        command('nft', ['delete', 'table', 'inet', 'qmodem_ttl_test']);
      }
    } finally {
      spawnSync('nft', ['delete', 'table', 'inet', 'qmodem_ttl_test']);
      for (const [dev] of links) spawnSync('ip', ['link', 'del', dev]);
    }
  });
