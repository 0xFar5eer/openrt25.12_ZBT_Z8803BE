'use strict';
// Regression fixtures only: no router, AT port, GPIO or host /sys is changed.
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zbt-led-labels-'));
after(() => fs.rmSync(temporary, { recursive: true, force: true }));
const file = p => fs.readFileSync(path.join(root, p), 'utf8');
const source = p => file(p).replaceAll('/usr/lib/zbt/', root + '/firmware/files/usr/lib/zbt/');
function run(script, env, args = []) {
  const r = spawnSync('busybox', ['sh', '-c', script, 'test', ...args], {
    encoding: 'utf8', timeout: 10000, env: { ...process.env, ...env }
  });
  assert.ifError(r.error);
  assert.equal(r.status, 0, r.stderr + '\n' + r.stdout);
  return r.stdout.trim();
}
function fixture() {
  const dir = fs.mkdtempSync(path.join(temporary, 'case-'));
  const sys = path.join(dir, 'sys');
  const write = (p, data) => {
    fs.mkdirSync(path.dirname(path.join(sys, p)), { recursive: true });
    fs.writeFileSync(path.join(sys, p), data + '\n');
  };
  const read = p => fs.readFileSync(path.join(sys, p), 'utf8').trim();
  for (const [usb, net, power, led] of [['4-1', 'wwan8', '5g1', 'blue:mobile-1'], ['2-1', 'wwan3', '5g2', 'blue:mobile-2']]) {
    const device = path.join(sys, 'devices', usb);
    fs.mkdirSync(path.join(device, usb + ':1.4/net', net), { recursive: true });
    fs.mkdirSync(path.join(sys, 'bus/usb/devices'), { recursive: true });
    fs.symlinkSync(device, path.join(sys, 'bus/usb/devices', usb));
    write(`class/gpio/${power}/value`, '1');
    write(`class/net/${net}/carrier`, '1');
    write(`class/leds/${led}/available`, 'none timer netdev');
    write(`class/leds/${led}/trigger`, 'none');
    for (const attr of ['brightness', 'device_name', 'delay_on', 'delay_off', 'link', 'rx', 'tx']) write(`class/leds/${led}/${attr}`, '0');
    write(`class/leds/${led}/max_brightness`, '255');
  }
  for (const led of ['red:status', 'green:wan', 'blue:power']) {
    write(`class/leds/${led}/trigger`, 'default-on');
    write(`class/leds/${led}/brightness`, '0');
    write(`class/leds/${led}/max_brightness`, '255');
    write(`class/leds/${led}/delay_on`, '0');
    write(`class/leds/${led}/delay_off`, '0');
  }
  return { dir, sys, write, read, env: { ZBT_SYSFS: sys, CALLS: path.join(dir, 'writes'), ONLINE: 'wwan8' } };
}
const led = source('firmware/files/usr/lib/zbt/modem-leds.sh').replace('zbt_led_write() {', '_led_write() {');
// Model the kernel's trigger-list readback. All writes still go through the
// production writer to real fixture files; log every attempted attribute.
const mocks = `
zbt_led_write() { echo "$ZBT_LED:$1=$2" >> "$CALLS"; _led_write "$@"; }
zbt_led_read() {
  if [ "$1" = trigger ]; then
    selected=$(cat "$ZBT_LED_PATH/trigger")
    for choice in $(cat "$ZBT_LED_PATH/available"); do
      [ "$choice" != "$selected" ] && printf '%s ' "$choice" || printf '[%s] ' "$choice"
    done
  else cat "$ZBT_LED_PATH/$1"; fi
}
ip() { [ "$4" = "$ONLINE" ] && echo '    inet 192.0.0.2/27 scope global'; }
logger() { :; }
`;

test('production path delegates both physical slots to the pinned Far5eer helper', () => {
  const f = fixture();
  const helper = path.join(f.dir, 'zbt-leds.sh');
  const helperCalls = path.join(f.dir, 'helper-calls');
  fs.writeFileSync(helper, '#!/bin/sh\nprintf "%s\\n" "$*" >> "$HELPER_CALLS"\n');
  fs.chmodSync(helper, 0o755);
  run(led + mocks + '\nzbt_led_detect 4_1; zbt_led_apply; zbt_led_detect 2_1; zbt_led_apply', {
    ...f.env, ZBT_LED_HELPER: helper, HELPER_CALLS: helperCalls
  });
  assert.equal(fs.readFileSync(helperCalls, 'utf8'), 'slot 1 wwan wwan8\nslot 2 no_signal\n');

  const hotplug = file('firmware/files/etc/hotplug.d/net/20-zbt-modem-led');
  assert.match(hotplug, /4-1\) slot=1; led=\/sys\/class\/leds\/blue:mobile-1/);
  assert.match(hotplug, /2-1\) slot=2; led=\/sys\/class\/leds\/blue:mobile-2/);
  assert.match(hotplug, /\/etc\/zbt-leds\.sh slot "\$slot" wwan "\$DEVICENAME"/);
});

test('LEDs use physical slots: online primary gets activity, waiting secondary blinks', () => {
  const f = fixture();
  run(led + mocks + '\nzbt_led_detect 4_1; zbt_led_apply; zbt_led_detect 2_1; zbt_led_apply', f.env);
  assert.equal(f.read('class/leds/blue:mobile-1/trigger'), 'netdev');
  assert.equal(f.read('class/leds/blue:mobile-1/device_name'), 'wwan8');
  for (const attr of ['rx', 'tx', 'link']) assert.equal(f.read(`class/leds/blue:mobile-1/${attr}`), '1');
  assert.equal(f.read('class/leds/blue:mobile-2/trigger'), 'timer');
  assert.equal(f.read('class/leds/blue:mobile-2/delay_on'), '1000');
  assert.equal(f.read('class/leds/blue:mobile-2/brightness'), '255');
  assert.doesNotMatch(fs.readFileSync(f.env.CALLS, 'utf8'), /gpio|5g1|5g2|wwan3/);
  run(led + mocks + '\nzbt_led_detect 4_1; zbt_led_apply; zbt_led_detect 2_1; zbt_led_apply', { ...f.env, ONLINE: 'wwan3' });
  assert.equal(f.read('class/leds/blue:mobile-2/device_name'), 'wwan3');
  assert.equal(f.read('class/leds/blue:mobile-2/trigger'), 'netdev');
  assert.equal(f.read('class/leds/blue:mobile-1/trigger'), 'timer');
});

test('missing GPIO read or a not-yet-created netdev does not black out a present modem', () => {
  const f = fixture();
  fs.unlinkSync(path.join(f.sys, 'class/gpio/5g1/value'));
  fs.rmSync(path.join(f.sys, 'devices/2-1/2-1:1.4/net'), { recursive: true });
  assert.equal(run(led + mocks + '\nzbt_led_detect 4_1; echo "$ZBT_LED_POWER:$ZBT_LED_STATE"; zbt_led_apply; zbt_led_detect 2_1; echo "$ZBT_LED_STATE"; zbt_led_apply', f.env), 'unknown:data\nwaiting');
  assert.equal(f.read('class/leds/blue:mobile-1/trigger'), 'netdev');
  assert.equal(f.read('class/leds/blue:mobile-2/trigger'), 'timer');
});

test('both addressed modems recover from dark startup with independent activity bindings', () => {
  const f = fixture();
  run(led + mocks + '\nip() { echo "    inet 192.0.0.2/27 scope global"; }\n' +
    'zbt_led_detect 4_1; zbt_led_apply; zbt_led_detect 2_1; zbt_led_apply', f.env);
  for (const [lamp, device] of [['blue:mobile-1', 'wwan8'], ['blue:mobile-2', 'wwan3']]) {
    assert.equal(f.read(`class/leds/${lamp}/trigger`), 'netdev');
    assert.equal(f.read(`class/leds/${lamp}/device_name`), device);
    assert.equal(f.read(`class/leds/${lamp}/brightness`), '255');
    for (const attr of ['link', 'rx', 'tx']) assert.equal(f.read(`class/leds/${lamp}/${attr}`), '1');
  }
});

test('powered-off absent modem stays dark without changing the working peer LED', () => {
  const f = fixture();
  fs.unlinkSync(path.join(f.sys, 'bus/usb/devices/2-1'));
  f.write('class/gpio/5g2/value', '0');
  f.write('class/leds/blue:mobile-1/brightness', '93');
  run(led + mocks + '\nzbt_led_detect 2_1; zbt_led_apply', f.env);
  assert.equal(f.read('class/leds/blue:mobile-2/brightness'), '0');
  assert.equal(f.read('class/leds/blue:mobile-1/brightness'), '93');
});

test('LED trigger clobber and disabled RX/TX are repaired; healthy triggers are left alone', () => {
  const f = fixture();
  const cycle = led + mocks + '\nzbt_led_detect 4_1; zbt_led_apply';
  run(cycle, f.env);
  fs.writeFileSync(f.env.CALLS, '');
  run(cycle, f.env);
  assert.equal(fs.readFileSync(f.env.CALLS, 'utf8'), '');
  f.write('class/leds/blue:mobile-1/rx', '0');
  run(cycle, f.env);
  assert.equal(f.read('class/leds/blue:mobile-1/rx'), '1');
  f.write('class/leds/blue:mobile-1/trigger', 'none');
  f.write('class/leds/blue:mobile-1/brightness', '0');
  run(cycle, f.env);
  assert.equal(f.read('class/leds/blue:mobile-1/trigger'), 'netdev');
  assert.equal(f.read('class/leds/blue:mobile-1/brightness'), '255');
});

test('a LuCI system LED rule takes ownership from the automatic modem poller', () => {
  const f = fixture();
  const userRule = `
uci() {
  [ "$1" != -q ] || shift
  case "$1:$2" in
    show:system) echo "system.custom=led" ;;
    get:system.custom.sysfs) echo "blue:mobile-1" ;;
    *) return 1 ;;
  esac
}
`;
  f.write('class/leds/blue:mobile-1/brightness', '73');
  run(led + mocks + userRule + '\nzbt_led_detect 4_1; zbt_led_apply', f.env);
  assert.equal(f.read('class/leds/blue:mobile-1/trigger'), 'none');
  assert.equal(f.read('class/leds/blue:mobile-1/brightness'), '73');
  assert.equal(fs.existsSync(f.env.CALLS), false, 'automatic service must not overwrite a user-managed LED');
});

test('seeded LED inventory remains under automatic control until its trigger is changed', () => {
  const f = fixture();
  const inventoryRule = `
uci() {
  [ "$1" != -q ] || shift
  case "$1:$2" in
    show:system) echo "system.inventory=led" ;;
    get:system.inventory.sysfs) echo "blue:mobile-1" ;;
    get:system.inventory.zbt_automatic) echo 1 ;;
    get:system.inventory.trigger) echo none ;;
    *) return 1 ;;
  esac
}
`;
  run(led + mocks + inventoryRule + '\nzbt_led_detect 4_1; zbt_led_apply', f.env);
  assert.equal(f.read('class/leds/blue:mobile-1/trigger'), 'netdev');
  assert.equal(f.read('class/leds/blue:mobile-1/device_name'), 'wwan8');
});

test('missing trigger attributes or unreliable carrier use a visible fallback', () => {
  for (const failure of ['unsupported', 'attribute', 'carrier']) {
    const f = fixture();
    if (failure === 'unsupported') f.write('class/leds/blue:mobile-1/available', 'none');
    if (failure === 'attribute') fs.unlinkSync(path.join(f.sys, 'class/leds/blue:mobile-1/rx'));
    if (failure === 'carrier') f.write('class/net/wwan8/carrier', '0');
    run(led + mocks + '\nzbt_led_detect 4_1; zbt_led_apply', f.env);
    assert.equal(f.read('class/leds/blue:mobile-1/trigger'), 'none', failure);
    assert.equal(f.read('class/leds/blue:mobile-1/brightness'), '255', failure);
    if (failure === 'attribute') assert.equal(fs.existsSync(path.join(f.sys, 'class/leds/blue:mobile-1/rx')), false);
  }
});

test('poller status is read-only and has one post-generic-LED S97 owner', () => {
  const f = fixture();
  const poller = file('firmware/files/usr/sbin/zbt-modem-led-poller').replace('. /usr/lib/zbt/modem-leds.sh', '');
  const output = run(led + mocks + poller, f.env, ['status']);
  assert.match(output, /modem=4_1 usb=4-1.*device=wwan8 state=data/);
  assert.match(output, /modem=2_1 usb=2-1.*device=wwan3 state=waiting/);
  assert.equal(fs.existsSync(f.env.CALLS), false);
  assert.match(file('firmware/files/etc/init.d/zbt-modem-leds'), /^START=97$/m);
  const builder = file('firmware/docker/build-openwrt.sh');
  assert.match(builder, /legacy_modem_led_link=target\/linux\/mediatek\/filogic\/base-files\/etc\/rc\.d\/S95zbt-modem-leds/);
  assert.match(builder, /readlink \"\$legacy_modem_led_link\"\)\" = \.\.\/init\.d\/zbt-modem-leds/);
  assert.match(builder, /rm -f -- \"\$legacy_modem_led_link\"/);
  const defaults = file('firmware/files/etc/uci-defaults/49-zbt-modem-labels-leds');
  assert.match(defaults, /zbt-modem-leds enable/);
  assert.match(defaults, /S\?\?zbt-modem-leds/);
  assert.match(defaults, /zbt-leds enable/);
  for (const [phy, dev] of [['00', 'lan0'], ['02', 'lan1'], ['03', 'lan2']]) {
    assert.match(defaults, new RegExp(`mt7530-0:${phy}:green:lan' ${dev}`));
  }
  assert.match(defaults, /mdio-bus:0f:amber:wan' eth1/);
  assert.match(defaults, /system\.\$section\.mode=link tx rx/);
  assert.doesNotMatch(defaults, /ensure_automatic_led/);
  assert.match(defaults, /blue:mobile-1\|blue:mobile-2\|red:status\|green:wan\|blue:power/);
  assert.doesNotMatch(file('firmware/files/usr/sbin/zbt-modem-led-poller'), /zbt_status_apply|red:status|green:wan|blue:power/);
});

test('one-shot dark-LED repair removes only stale none rules for the two modem lamps', () => {
  const f = fixture(), db = path.join(f.dir, 'uci');
  fs.mkdirSync(db);
  const board = path.join(f.dir, 'board_name');
  fs.writeFileSync(board, 'zbtlink,zbt-z8803be\n');
  const uci = `
uci() {
  [ "$1" != -q ] || shift
  case "$1" in
    show)
      for u_path in "$DB"/system.*; do
        [ -f "$u_path" ] || continue
        printf '%s=%s\\n' "\${u_path##*/}" "$(cat "$u_path")"
      done ;;
    get) [ -f "$DB/$2" ] && cat "$DB/$2" ;;
    delete) rm -f "$DB/$2" "$DB/$2".* ;;
    commit) echo committed >> "$DB/commits" ;;
    *) return 1 ;;
  esac
}
`;
  const add = (name, lamp, trigger) => {
    fs.writeFileSync(path.join(db, `system.${name}`), 'led');
    fs.writeFileSync(path.join(db, `system.${name}.sysfs`), lamp);
    fs.writeFileSync(path.join(db, `system.${name}.trigger`), trigger);
  };
  add('dark1', 'blue:mobile-1', 'none');
  add('dark2', 'blue:mobile-2', 'none');
  add('custom', 'blue:mobile-1', 'timer');
  add('status', 'red:status', 'none');
  const repair = file('firmware/files/etc/uci-defaults/48-zbt-modem-led-dark-repair')
    .replaceAll('/tmp/sysinfo/board_name', board);
  run(uci + repair, { ...f.env, DB: db });
  assert.equal(fs.existsSync(path.join(db, 'system.dark1')), false);
  assert.equal(fs.existsSync(path.join(db, 'system.dark2')), false);
  assert.equal(fs.readFileSync(path.join(db, 'system.custom.trigger'), 'utf8').trim(), 'timer');
  assert.equal(fs.readFileSync(path.join(db, 'system.status.trigger'), 'utf8').trim(), 'none');
  assert.equal(fs.readFileSync(path.join(db, 'commits'), 'utf8').trim(), 'committed');
});

test('LED migration removes broken automatic rows, seeds four jacks, and preserves administrator settings', () => {
  const f = fixture(), db = path.join(f.dir, 'uci');
  fs.mkdirSync(db);
  const board = path.join(f.dir, 'board_name');
  fs.writeFileSync(board, 'zbtlink,zbt-z8803be\n');
  const uci = `
uci() {
  local u_path u_index
  [ "$1" != -q ] || shift
  case "$1" in
    show)
      for u_path in "$DB"/system.*; do
        [ -f "$u_path" ] || continue
        printf '%s=%s\\n' "\${u_path##*/}" "$(cat "$u_path")"
      done ;;
    get) [ -f "$DB/$2" ] && cat "$DB/$2" ;;
    set) printf '%s\\n' "\${2#*=}" > "$DB/\${2%%=*}" ;;
    add)
      u_index=0
      while [ -f "$DB/system.led$u_index" ]; do u_index=$((u_index+1)); done
      echo led > "$DB/system.led$u_index"
      echo "led$u_index" ;;
    delete) rm -f "$DB/$2" "$DB/$2".* ;;
    commit) : ;;
    *) return 1 ;;
  esac
}
`;
  const defaults = file('firmware/files/etc/uci-defaults/49-zbt-modem-labels-leds')
    .replaceAll('/tmp/sysinfo/board_name', board)
    .replaceAll('/usr/sbin/zbt-qmodem-profile', ':')
    .replaceAll('/etc/init.d/zbt-modem-leds', ':')
    .replaceAll('/etc/init.d/zbt-leds', ':')
    .replaceAll('/etc/rc.d/', path.join(f.dir, 'rc.d') + '/');
  const env = { ...f.env, DB: db };
  for (const [name, sysfs] of [['stale5g', 'blue:mobile-1'], ['stalestatus', 'green:wan']]) {
    fs.writeFileSync(path.join(db, `system.${name}`), 'led');
    fs.writeFileSync(path.join(db, `system.${name}.sysfs`), sysfs);
    fs.writeFileSync(path.join(db, `system.${name}.trigger`), 'none');
    fs.writeFileSync(path.join(db, `system.${name}.zbt_automatic`), '1');
  }
  run(uci + defaults, env);
  const read = name => fs.readFileSync(path.join(db, name), 'utf8').trim();
  for (const [index, lamp, device] of [
    [0, 'mt7530-0:00:green:lan', 'lan0'], [1, 'mt7530-0:02:green:lan', 'lan1'],
    [2, 'mt7530-0:03:green:lan', 'lan2'], [3, 'mdio-bus:0f:amber:wan', 'eth1']
  ]) {
    assert.equal(read(`system.led${index}.sysfs`), lamp);
    assert.equal(read(`system.led${index}.dev`), device);
    assert.equal(read(`system.led${index}.trigger`), 'netdev');
    assert.equal(read(`system.led${index}.mode`), 'link tx rx');
  }
  assert.equal(fs.readdirSync(db).filter(n => /^system\.led\d+$/.test(n)).length, 4);
  assert.equal(fs.readdirSync(db).some(n => n.includes('stale5g') || n.includes('stalestatus')), false);
  fs.writeFileSync(path.join(db, 'system.led3.mode'), 'rx');
  fs.writeFileSync(path.join(db, 'system.led3.name'), 'Custom WAN');
  const snapshot = () => Object.fromEntries(fs.readdirSync(db).sort().map(n => [n, read(n)]));
  const before = snapshot();
  run(uci + defaults, env);
  assert.deepEqual(snapshot(), before, 'rerun must not duplicate rows or overwrite user rules');
});

test('display labels migrate independently of internal interface IDs and dial fingerprints', () => {
  const f = fixture(), db = path.join(f.dir, 'uci');
  fs.mkdirSync(db);
  const uci = `
uci() {
  [ "$1" != -q ] || shift
  case "$1" in
    get) [ -f "$DB/$2" ] && cat "$DB/$2" ;;
    set) printf '%s\\n' "\${2#*=}" > "$DB/\${2%%=*}" ;;
    commit) : ;;
    *) return 1 ;;
  esac
}
`;
  const profile = source('firmware/files/usr/sbin/zbt-qmodem-profile');
  const env = { ...f.env, DB: db };
  for (const id of ['4_1', '2_1']) {
    fs.writeFileSync(path.join(db, `qmodem.${id}`), 'modem-device');
    fs.writeFileSync(path.join(db, `qmodem.${id}.alias`), id);
    run(uci + profile, env, [id]);
  }
  assert.equal(fs.readFileSync(path.join(db, 'qmodem.4_1.display_name'), 'utf8').trim(), 'Modem 1');
  assert.equal(fs.readFileSync(path.join(db, 'qmodem.2_1.display_name'), 'utf8').trim(), 'Modem 2');
  const fingerprints = () => run(uci + source('firmware/files/usr/lib/zbt/dual-modem.sh') + '\nzbt_dial_fingerprint 4_1; zbt_dial_fingerprint 2_1', env);
  const before = fingerprints();
  fs.writeFileSync(path.join(db, 'qmodem.2_1.display_name'), 'Travel SIM');
  run(uci + profile, env, ['2_1']);
  assert.equal(fingerprints(), before, 'renaming either modem must not redial it or its peer');
  assert.equal(fs.readFileSync(path.join(db, 'qmodem.2_1.display_name'), 'utf8'), 'Travel SIM');
  assert.equal(fs.readFileSync(path.join(db, 'qmodem.2_1.alias'), 'utf8').trim(), '2_1');
  fs.unlinkSync(path.join(db, 'qmodem.2_1.display_name'));
  fs.writeFileSync(path.join(db, 'qmodem.2_1.alias'), 'My carrier');
  fs.writeFileSync(path.join(db, 'qmodem.slot_2_1.display_name'), 'Default name');
  run(uci + profile, env, ['2_1']);
  assert.equal(fs.readFileSync(path.join(db, 'qmodem.2_1.display_name'), 'utf8').trim(), 'My carrier');
  fs.unlinkSync(path.join(db, 'qmodem.2_1.display_name'));
  run(uci + profile, env, ['2_1']);
  assert.equal(fs.readFileSync(path.join(db, 'qmodem.2_1.display_name'), 'utf8').trim(), 'Default name');
});

test('patched LuCI dropdowns and overview show labels while RPC values remain stable', { skip: !process.env.QMODEM_TEST_TREE }, async () => {
  const base = path.join(process.env.QMODEM_TEST_TREE, 'luci/luci-app-qmodem-next/htdocs/luci-static/resources');
  const read = p => fs.readFileSync(path.join(base, p), 'utf8');
  const sections = [
    { '.name': '4_1', alias: '4_1', name: 'rm551e-gl', at_port: '/dev/ttyUSB6' },
    { '.name': '2_1', alias: '2_1', name: 'rm551e-gl', at_port: '/dev/ttyUSB2' }
  ];
  const uci = { load: async () => {}, get: (p, id) => sections.find(s => s['.name'] === id),
    sections: (p, type, cb) => { if (cb) sections.forEach(cb); return sections; } };
  const L = { Class: { extend: o => o }, resource: x => x };
  const rpc = { declare: () => () => {} };
  const qmodem = new Function('L', 'rpc', 'uci', '_', read('qmodem/qmodem.js'))(L, rpc, uci, x => x);
  assert.deepEqual((await qmodem.getModemSections()).map(s => [s.id, s.name]), [
    ['4_1', 'Modem 1 (RM551E-GL)'], ['2_1', 'Modem 2 (RM551E-GL)']
  ]);
  const overview = new Function('view', 'document', 'E', 'L', 'uci', 'qmodem', '_', read('view/qmodem/overview.js'))(
    { extend: o => o }, { head: { appendChild() {} }, styleSheets: [] }, () => ({}), L, uci, qmodem, x => x);
  assert.deepEqual(overview.getModemList().map(s => [s.id, s.name]), [
    ['4_1', 'Modem 1 (RM551E-GL)'], ['2_1', 'Modem 2 (RM551E-GL)']
  ]);
  sections[1].display_name = 'Travel SIM';
  assert.equal(qmodem.getModemLabel('2_1'), 'Travel SIM');
  assert.equal(overview.getModemList()[1].id, '2_1');
  assert.equal(overview.getModemList()[1].name, 'Travel SIM (RM551E-GL)');
  for (const p of ['view/qmodem/network_config.js', 'view/qmodem/settings.js']) {
    assert.doesNotMatch(read(p), /form\.Value, 'alias'/, 'GUI edits must not rename netifd devices');
    assert.match(read(p), /form\.Value, 'display_name'/);
    assert.match(read(p), /sectiontitle = function\(section_id\) \{ return qmodem\.getModemLabel/);
  }
});
