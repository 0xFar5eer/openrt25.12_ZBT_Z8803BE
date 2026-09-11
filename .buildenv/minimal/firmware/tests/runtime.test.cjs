'use strict';
// Host-side regression tests. Hardware, SIM registration and flashability
// are explicitly outside these tests; all device/AT/HTTP calls are mocked.
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zbt-runtime-tests-'));
after(() => fs.rmSync(temporary, { recursive: true, force: true }));
let counter = 0;
const file = p => fs.readFileSync(path.join(root, p), 'utf8');
const quote = s => "'" + s.replaceAll("'", "'\\''") + "'";
function sandbox() {
  const p = path.join(temporary, String(++counter));
  fs.mkdirSync(p);
  return p;
}
function source(p) {
  return file(p).replaceAll('/usr/lib/zbt/', root + '/firmware/files/usr/lib/zbt/');
}
function shell(script, env = {}, args = []) {
  const r = spawnSync('busybox', ['sh', '-c', script, 'test', ...args], {
    encoding: 'utf8', timeout: 15000, env: { ...process.env, ...env }
  });
  assert.ifError(r.error);
  assert.equal(r.status, 0, r.stderr + '\n' + r.stdout);
  return r.stdout.trim();
}
function usbFixture() {
  const dir = sandbox(), sys = path.join(dir, 'sys');
  for (const [usb, net, tty] of [['4-1', 'wwan8', 'ttyUSB6'], ['2-1', 'wwan3', 'ttyUSB2']]) {
    const device = path.join(sys, 'devices', usb);
    fs.mkdirSync(path.join(device, usb + ':1.4/net', net), { recursive: true });
    fs.mkdirSync(path.join(device, usb + ':1.2', tty), { recursive: true });
    fs.mkdirSync(path.join(sys, 'bus/usb/devices'), { recursive: true });
    fs.symlinkSync(device, path.join(sys, 'bus/usb/devices', usb));
    fs.mkdirSync(path.join(sys, 'class/tty', tty), { recursive: true });
    fs.symlinkSync(path.join(device, usb + ':1.2', tty), path.join(sys, 'class/tty', tty, 'device'));
  }
  return { dir, sys, env: { ZBT_SYSFS: sys } };
}
const dual = source('firmware/files/usr/lib/zbt/dual-modem.sh');

// File-backed mock UCI survives shell command substitutions, just like UCI.
// No test writes /etc, touches real GPIOs or runs a router service.
const fakeUci = `
uci() {
  [ "$1" != -q ] || shift
  op=$1; shift
  key=\${1%%=*}
  case "$op" in
    get) [ -f "$UCI_TEST_DATA/$key" ] && cat "$UCI_TEST_DATA/$key" ;;
    set) printf '%s\\n' "\${1#*=}" > "$UCI_TEST_DATA/$key" ;;
    commit) : ;;
    delete) rm -f "$UCI_TEST_DATA/$key" ;;
    show)
      for entry in "$UCI_TEST_DATA/$1".*; do
        [ -f "$entry" ] || continue
        printf '%s=%s\\n' "\${entry##*/}" "$(cat "$entry")"
      done ;;
    *) echo "Unexpected mocked UCI operation: $op" >&2; return 1 ;;
  esac
}
`;
function uciFixture(values = {}) {
  const dir = sandbox();
  for (const [key, value] of Object.entries(values)) fs.writeFileSync(path.join(dir, key), String(value));
  return { dir, env: { UCI_TEST_DATA: dir }, read: key => fs.readFileSync(path.join(dir, key), 'utf8').trim() };
}

test('minimal first boot seeds primary on and secondary off without direct GPIO writes', () => {
  const fixture = uciFixture();
  const defaults = source('firmware/files/etc/uci-defaults/99-cellular-multiwan-defaults');
  shell(fakeUci + defaults, fixture.env);
  assert.equal(fixture.read('system.5g1.value'), '1');
  assert.equal(fixture.read('system.5g2.value'), '0');
  assert.equal(fs.existsSync(path.join(fixture.dir, 'qmodem.2_1')), false, 'no incomplete phantom modem');
  assert.doesNotMatch(defaults, />\s*.*\/sys\/|modem_watchdog enable/);
  // Deliberate later choices survive even if first-boot defaults are re-run.
  fs.writeFileSync(path.join(fixture.dir, 'system.5g1.value'), '0');
  fs.writeFileSync(path.join(fixture.dir, 'system.5g2.value'), '1');
  shell(fakeUci + defaults, fixture.env);
  assert.equal(fixture.read('system.5g1.value'), '0');
  assert.equal(fixture.read('system.5g2.value'), '1');
});

test('modem2 dial default is off, manual enable and APNs survive rediscovery', () => {
  const fixture = uciFixture({ 'qmodem.4_1': 'modem-device', 'qmodem.2_1': 'modem-device', 'qmodem.2_1.apn': 'private.plan' });
  const profile = source('firmware/files/usr/sbin/zbt-qmodem-profile');
  for (const section of ['4_1', '2_1']) shell(fakeUci + profile, fixture.env, [section]);
  assert.equal(fixture.read('qmodem.4_1.enable_dial'), '1');
  assert.equal(fixture.read('qmodem.2_1.enable_dial'), '0');
  assert.equal(fixture.read('qmodem.2_1.apn'), 'private.plan');
  assert.equal(fixture.read('qmodem.2_1.metric'), '210');
  fs.writeFileSync(path.join(fixture.dir, 'qmodem.2_1.enable_dial'), '1');
  shell(fakeUci + profile, fixture.env, ['2_1']);
  assert.equal(fixture.read('qmodem.2_1.enable_dial'), '1');
  assert.equal(fixture.read('qmodem.2_1.apn'), 'private.plan');
});

test('minimal package contract rejects forbidden packages, including indirect selections', () => {
  const dir = sandbox(), input = path.join(dir, 'input');
  const check = path.join(root, 'firmware/scripts/check-minimal-profile.sh');
  for (const pkg of ['speedify', 'luci-app-speedify', 'kmod-tun', 'mwan3', 'luci-app-mwan3', 'openvpn-openssl', 'tailscale', 'luci-app-speedtest-lite', 'speedtest-go', 'netperf', 'qmodem_monitor', 'luci-app-zbt-modem-events', 'luci-i18n-qmodem-monitor-zh-cn', 'luci-app-modem-watchdog', 'kmod-wireguard']) {
    for (const mode of ['config', 'manifest']) {
      fs.writeFileSync(input, mode === 'config' ? `CONFIG_PACKAGE_${pkg}=y\n` : `${pkg} - 1.0\n`);
      const r = spawnSync('bash', [check, mode, input], { encoding: 'utf8' });
      assert.equal(r.status, 3, `${mode}: must reject ${pkg}: ${r.stderr}`);
    }
  }
  fs.writeFileSync(input, 'CONFIG_PACKAGE_qmodem=y\n');
  assert.equal(spawnSync('bash', [check, 'config', input]).status, 0);
  assert.match(file('firmware/profiles/kconfig-fragment.conf'), /^# CONFIG_PACKAGE_kmod-tun is not set$/m);
  const builder = file('firmware/docker/build-openwrt.sh');
  for (const mode of ['config', 'manifest', 'rootfs']) assert.ok(builder.includes(`check-minimal-profile.sh" ${mode}`));
  assert.doesNotMatch(builder, /make package\/feeds\/packages\/golang-bootstrap/);
});

test('minimal rootfs contract detects leftover watchdog and Speedify files', () => {
  const dir = sandbox(), check = path.join(root, 'firmware/scripts/check-minimal-profile.sh');
  for (const d of ['etc/init.d', 'etc/rc.d', 'usr/sbin', 'usr/share/luci/menu.d', 'www/luci-static/resources/view']) fs.mkdirSync(path.join(dir, d), { recursive: true });
  fs.writeFileSync(path.join(dir, 'etc/zbt-build-flavor'), 'minimal\n');
  fs.writeFileSync(path.join(dir, 'etc/init.d/uhttpd'), '#!/bin/sh\n', { mode: 0o755 });
  assert.equal(spawnSync('bash', [check, 'rootfs', dir]).status, 0);
  fs.writeFileSync(path.join(dir, 'etc/init.d/zbt_qmodem_watchdog'), 'forbidden');
  assert.equal(spawnSync('bash', [check, 'rootfs', dir]).status, 4);
  fs.rmSync(path.join(dir, 'etc/init.d/zbt_qmodem_watchdog'));
  fs.writeFileSync(path.join(dir, 'usr/share/luci/menu.d/tailscale.json'), '{}');
  assert.equal(spawnSync('bash', [check, 'rootfs', dir]).status, 4);
  fs.rmSync(path.join(dir, 'usr/share/luci/menu.d/tailscale.json'));
  fs.writeFileSync(path.join(dir, 'usr/share/luci/menu.d/luci-app-speedify.json'), '{}');
  assert.equal(spawnSync('bash', [check, 'rootfs', dir]).status, 4);
});

test('slot mapping follows physical USB paths, not enumeration order', () => {
  const f = usbFixture();
  assert.equal(shell(dual + '\nzbt_netdev 4_1; zbt_netdev 2_1; zbt_slot 2_1; echo "$ZBT_POWER $ZBT_LED"', f.env),
    'wwan8\nwwan3\n5g2 blue:mobile-2');
  assert.equal(shell(dual + '\nzbt_port_matches 4_1 /dev/ttyUSB6 && echo own; zbt_port_matches 4_1 /dev/ttyUSB2 || echo rejected', f.env), 'own\nrejected');
  fs.rmSync(path.join(f.sys, 'devices/2-1/2-1:1.4/net/wwan3'), { recursive: true });
  assert.equal(shell(dual + '\nzbt_netdev 2_1 || echo absent; zbt_netdev 4_1', f.env), 'absent\nwwan8');
  fs.mkdirSync(path.join(f.sys, 'devices/4-1/4-1:1.4/net/wwan9'));
  assert.equal(shell(dual + '\nzbt_netdev 4_1 || echo ambiguous', f.env), 'ambiguous');
});

test('unknown slot or stale AT path is rejected; no fallback to the other modem', () => {
  const f = usbFixture();
  assert.equal(shell(dual + '\nzbt_slot 4_2 || echo unknown; zbt_port_matches 4_1 /dev/ttyUSB99 || echo stale', f.env), 'unknown\nstale');
});

test('blank and auto APNs preserve carrier negotiation, manual APNs stay manual', () => {
  assert.equal(shell(dual + '\nzbt_apn_mode ""; zbt_apn_mode auto; zbt_apn_mode private.example'), 'auto\nauto\nmanual');
  const cmd = dual + '\nuci() { case "$3" in qmodem.2_1.apn) echo "$SIM2_APN";; qmodem.4_1.apn) echo "$SIM1_APN";; esac; }; zbt_dial_fingerprint 4_1; zbt_dial_fingerprint 2_1';
  const a = shell(cmd, { SIM1_APN: '', SIM2_APN: '' }).split('\n');
  const b = shell(cmd, { SIM1_APN: '', SIM2_APN: 'private.operator' }).split('\n');
  assert.equal(a[0], b[0], 'modem2 settings must not alter modem1 service fingerprint');
  assert.notEqual(a[1], b[1]);
});

test('AT&T US gets broadband only in auto mode and manual APNs always win', () => {
  const script = dual + `
at() { printf '%s\\r\\nOK\\r\\n' "$TEST_IMSI"; }
result=$(zbt_effective_apn "$TEST_APN" /dev/ttyUSB-test)
printf '<%s>\\n' "$result"`;
  assert.equal(shell(script, { TEST_IMSI: '310410000000001', TEST_APN: '' }), '<broadband>');
  assert.equal(shell(script, { TEST_IMSI: '310410000000001', TEST_APN: 'auto' }), '<broadband>');
  assert.equal(shell(script, { TEST_IMSI: '310410000000001', TEST_APN: 'mvno.custom' }), '<mvno.custom>');
  assert.equal(shell(script, { TEST_IMSI: '310260123456789', TEST_APN: '' }), '<>');
  assert.equal(shell(script, { TEST_IMSI: 'invalid', TEST_APN: '' }), '<>');
});

test('QModem offers matching editable US APN presets for both SIM selectors', { skip: !process.env.QMODEM_TEST_TREE }, () => {
  const sourceText = fs.readFileSync(path.join(process.env.QMODEM_TEST_TREE,
    'luci/luci-app-qmodem-next/htdocs/luci-static/resources/view/qmodem/network_config.js'), 'utf8');
  assert.match(sourceText, /form\.Value, 'apn'/, 'primary APN must remain an editable Value');
  assert.match(sourceText, /form\.Value, 'apn2'/, 'secondary APN must remain an editable Value');
  for (const apn of ['broadband', 'NXTGENPHONE', 'ENHANCEDPHONE', 'firstnet-broadband',
    'fast.t-mobile.com', 'vzwinternet', 'h2g2', 'h2g2-t', 'usccinternet']) {
    const escaped = apn.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    assert.equal((sourceText.match(new RegExp(`o\\.value\\('${escaped}'`, 'g')) || []).length, 2,
      `${apn} must be offered for both physical SIM selectors`);
  }
});

test('QModem starts both instances without nested procd transactions; redial targets one', () => {
  let svc = source('firmware/files/etc/init.d/qmodem_network').replace('mkdir -p /var/run/qmodem', ':');
  const mocks = `
extra_command() { :; }
ready() { return 0; }
procd_open_instance() { echo "open:$1"; }
procd_set_param() { [ "$1" != command ] || echo "command:$3:$4"; }
procd_close_instance() { :; }
procd_kill() { echo "kill:$1:$2"; }
rc_procd() { echo "transaction:$1:$2"; "$@"; }
`;
  const run = 'extra_command() { :; }\n' + dual + '\n' + svc + mocks + '\nzbt_dial_fingerprint() { echo stable; }; start_service; dial 2_1; hang 4_1';
  const out = shell(run);
  assert.equal(out.split('transaction:').length - 1, 1, 'only targeted dial opens its own transaction');
  assert.match(out, /open:modem_4_1/);
  assert.match(out, /open:modem_2_1/);
  assert.match(out, /kill:qmodem_network:modem_4_1/);
  assert.doesNotMatch(out, /kill:qmodem_network:modem_2_1/);
});

test('QModem stopped instance uses the marker expected by upstream RPC', () => {
  const svc = source('firmware/files/etc/init.d/qmodem_network');
  assert.equal(shell('extra_command() { :; }\n' + svc + '\nubus() { echo "{}"; }; modem_status 2_1'), 'modem_2_1 Not Running');
});

test('targeted redial waits for old cleanup and refuses overlapping dialers', () => {
  const svc = source('firmware/files/etc/init.d/qmodem_network');
  const mocks = `
extra_command() { :; }
ubus() { echo '{"qmodem_network":{"instances":{"modem_2_1":{"pid":201}}}}'; }
hang() { [ "$1" = 2_1 ]; }
dial() { echo "dial:$1:$attempts"; }
kill() { [ "$2" = 201 ] && [ "$attempts" -lt "$WAIT_SECONDS" ]; }
sleep() { :; }
logger() { :; }
`;
  assert.equal(shell('extra_command() { :; }\n' + svc + mocks + '\nredial 2_1', { WAIT_SECONDS: '2' }), 'dial:2_1:2');
  assert.equal(shell('extra_command() { :; }\n' + svc + mocks + '\nredial 2_1 || echo refused', { WAIT_SECONDS: '30' }), 'refused');
});

const bands = source('firmware/files/usr/lib/zbt/quectel-bands.sh');
test('band parser accepts quoted/CRLF masks, rejects ERROR, zero and wrong key', () => {
  const readback = '+QNWPREFCFG: "nr5g_band","78:41:77:41"\r\n\r\nOK\r\n';
  assert.equal(shell(bands + '\nzbt_band_values "$READBACK" nr5g_band', { READBACK: readback }), '41\n77\n78');
  for (const bad of ['', 'ERROR', '+QNWPREFCFG: "nr5g_band",0', '+QNWPREFCFG: "lte_band",41:77', '+QNWPREFCFG: "nr5g_band",41\nERROR']) {
    assert.equal(shell(bands + '\nzbt_band_values "$READBACK" nr5g_band || echo unreadable', { READBACK: bad }), 'unreadable');
  }
});

test('SA band write checks own AT port, modem result and exact readback', () => {
  const f = usbFixture();
  const mock = `
uci() { echo '41/77/78'; }
at() {
  printf '%s\\n' "$1:$2" >> "$CALLS"
  case "$2" in *'",'*) printf '%s\\n' "$WRITE_REPLY";; *) printf '%s\\n' "$READ_REPLY";; esac
}
config_section=2_1; at_port=/dev/ttyUSB2; band_class=NR; lock_band=77,41
zbt_set_lockband_nr
echo "$res"
`;
  const env = { ...f.env, CALLS: path.join(f.dir, 'at.log'), WRITE_REPLY: 'OK', READ_REPLY: '+QNWPREFCFG: "nr5g_band",41:77\nOK' };
  assert.equal(shell(bands + mock, env), 'OK (readback verified)');
  assert.match(fs.readFileSync(env.CALLS, 'utf8'), /ttyUSB2:AT\+QNWPREFCFG="nr5g_band",41:77/);
  assert.match(shell(bands + mock, { ...env, WRITE_REPLY: 'ERROR' }), /^ERROR: Modem rejected/);
  assert.match(shell(bands + mock, { ...env, READ_REPLY: '+QNWPREFCFG: "nr5g_band",78\nOK' }), /^ERROR: Band readback/);
  fs.writeFileSync(env.CALLS, '');
  assert.match(shell(bands + mock.replace('at_port=/dev/ttyUSB2', 'at_port=/dev/ttyUSB6'), env), /^ERROR: AT port/);
  assert.equal(fs.readFileSync(env.CALLS, 'utf8'), '', 'no command sent to peer modem');
  assert.match(shell(bands + mock.replace('lock_band=77,41', 'lock_band=99'), env), /^ERROR: Band not/);
  assert.equal(fs.readFileSync(env.CALLS, 'utf8'), '');
});

test('Minimal has no Speedify runtime and restores stock uhttpd on upgrade', () => {
  const paths = fs.readdirSync(path.join(root, 'firmware/files/etc/init.d'))
    .concat(fs.readdirSync(path.join(root, 'firmware/files/usr/sbin')))
    .join('\n');
  assert.doesNotMatch(paths, /speedify|zbt-luci-backend/i);
  const migration = file('firmware/files/etc/uci-defaults/50-zbt-luci-uhttpd');
  assert.match(migration, /uhttpd enable/);
  assert.match(migration, /uhttpd restart/);
  assert.doesNotMatch(migration, /nginx|uwsgi|qmodem|gpio/);
});

function patchedFile(p) { return fs.readFileSync(path.join(process.env.QMODEM_TEST_TREE, p), 'utf8'); }

test('Warp dialer repair blocks repeated failed SIM PIN attempts without shell-test errors', { skip: !process.env.QMODEM_TEST_TREE }, () => {
  const dir = sandbox();
  fs.mkdirSync(path.join(dir, '2_1_dir'));
  const dialer = patchedFile('application/qmodem/files/usr/share/qmodem/modem_dial.sh');
  const fn = dialer.slice(dialer.indexOf('\nunlock_sim()') + 1, dialer.indexOf('\nget_platform_suggest_pdp_index()')).replaceAll('/var/run/qmodem/', dir + '/');
  const result = shell(fn + `
lock() { :; }
m_debug() { :; }
at() { echo tried >> "$ATTEMPTS"; return 1; }
modem_config=2_1
unlock_sim 1234
unlock_sim 1234
unlock_sim 5678
wc -l < "$ATTEMPTS"
`, { ATTEMPTS: path.join(dir, 'attempts') });
  assert.equal(result, '2', 'same failed PIN must not consume another SIM retry');
});

function warpConfigFixture(options) {
  const dialer = patchedFile('application/qmodem/files/usr/share/qmodem/modem_dial.sh');
  const fn = dialer.slice(dialer.indexOf('\nget_platform_suggest_pdp_index()') + 1, dialer.indexOf('\ncheck_dial_prepare()'));
  return shell(fn + `
config_load() { :; }
config_foreach() { :; }
find() { echo /fixture/net; }
ls() { echo wwan_fixture; }
get_driver() { echo qmi; }
update_sim_slot() { sim_slot="$SIM_SLOT"; }
config_get() {
  local v=''
  case "$3" in
    path) v=/fixture/2-1 ;;
    manufacturer) v=quectel ;;
    platform) v="$PLATFORM" ;;
    pdp_index) v="$USER_INDEX" ;;
    suggest_pdp_index) v="$SUGGESTED_INDEX" ;;
    pincode) v=1111 ;;
    pincode2) v="$SECOND_PIN" ;;
  esac
  export "$1=$v"
}
modem_config=2_1
pin="$STALE_PIN"
update_config
printf '%s:%s:%s:%s' "$pdp_index" "$suggest_pdp_index" "$userset_pdp_index" "$pincode"
`, { PLATFORM: 'qualcomm', USER_INDEX: '', SUGGESTED_INDEX: '', SIM_SLOT: '1', SECOND_PIN: '', STALE_PIN: '', ...options });
}

test('Warp PDP fallback uses platform index only when suggestion is absent; explicit index survives', { skip: !process.env.QMODEM_TEST_TREE }, () => {
  assert.equal(warpConfigFixture({}), '1:1:0:1111');
  assert.equal(warpConfigFixture({ PLATFORM: 'lte' }), '3:3:0:1111');
  assert.equal(warpConfigFixture({ SUGGESTED_INDEX: '7' }), '7:7:0:1111');
  assert.equal(warpConfigFixture({ USER_INDEX: '5', SUGGESTED_INDEX: '7' }), '5:7:1:1111');
});

test('Warp PIN fallback uses internal SIM2 PIN when present, otherwise this module SIM1 PIN', { skip: !process.env.QMODEM_TEST_TREE }, () => {
  assert.equal(warpConfigFixture({ SIM_SLOT: '2', SECOND_PIN: '2222' }), '1:1:0:2222');
  assert.equal(warpConfigFixture({ SIM_SLOT: '2', STALE_PIN: '9999' }), '1:1:0:1111');
  assert.equal(warpConfigFixture({ SIM_SLOT: '1', SECOND_PIN: '2222' }), '1:1:0:1111');
});
test('patched QMI dialer gives each modem its own device and APN arguments', { skip: !process.env.QMODEM_TEST_TREE }, () => {
  const f = usbFixture(), bin = path.join(f.dir, 'bin');
  fs.mkdirSync(bin);
  const cm = path.join(bin, 'quectel-CM-M');
  fs.writeFileSync(cm, '#!/bin/sh\nprintf "%s\\0" "$@" > "$DIAL_ARGS"\n', { mode: 0o755 });
  const dialer = patchedFile('application/qmodem/files/usr/share/qmodem/modem_dial.sh');
  let fn = dialer.slice(dialer.indexOf('\nqmi_dial()') + 1, dialer.indexOf('\necm_dial()'));
  assert.ok(fn.startsWith('qmi_dial()'));
  fn = fn.replaceAll('/usr/lib/zbt/', root + '/firmware/files/usr/lib/zbt/').replaceAll('/usr/bin/quectel-CM-M', cm);
  for (const [section, port, net, apn, pdp, force, imsi, expectedApn] of [
    ['4_1', 'ttyUSB6', 'wwan8', '', 'ipv4v6', '', '310260123456789', ''],
    ['2_1', 'ttyUSB2', 'wwan3', 'auto', 'ipv4v6', '', '310260123456789', ''],
    ['2_1', 'ttyUSB2', 'wwan3', 'auto', 'ipv4v6', '', '310410000000001', 'broadband'],
    ['2_1', 'ttyUSB2', 'wwan3', 'private.apn', 'ipv4v6', '', '310410000000001', 'private.apn'],
    ['2_1', 'ttyUSB2', 'wwan3', 'broadband', 'ip', '1', '310410000000001', 'broadband'],
    ['2_1', 'ttyUSB2', 'wwan3', 'broadband', 'ip', '', '310410000000001', 'broadband']
  ]) {
    fs.mkdirSync(path.join(f.dir, section + '_dir'), { recursive: true });
    const argsfile = path.join(f.dir, 'args');
    const script = fn + `
m_debug() { :; }
at() { printf '%s\\nOK\\n' "$TEST_IMSI"; }
sleep() { exit 0; }
modem_config="$SECTION"; at_port="/dev/$PORT"; apn="$APN"
driver=qmi; pdp_type="$PDP"; force_set_apn="$FORCE_PROFILE"; userset_pdp_index=0; do_not_add_dns=1
username='test user'; password='test password'; auth=chap; metric=210
MODEM_RUNDIR="$RUNDIR"; log_file="$RUNDIR/dial.log"
qmi_dial`;
    shell(script, { ...f.env, PATH: bin + ':' + process.env.PATH, SECTION: section, PORT: port, APN: apn, PDP: pdp, FORCE_PROFILE: force, TEST_IMSI: imsi, DIAL_ARGS: argsfile, RUNDIR: f.dir });
    const args = fs.readFileSync(argsfile, 'utf8').split('\0').slice(0, -1);
    assert.equal(args[args.indexOf('-i') + 1], net);
    assert.ok(args.includes('-d'));
    assert.ok(args.includes('-D'));
    assert.ok(args.includes('-4'));
    assert.equal(args.includes('-6'), pdp !== 'ip', 'IPv4-only selection must not request a rejected IPv6 call');
    assert.equal(args.includes('-F'), force === '1', 'removed temporary force override must not persist');
    if (expectedApn) assert.deepEqual(args.slice(args.indexOf('-s'), args.indexOf('-s') + 5), ['-s', expectedApn, 'test user', 'test password', 'chap']);
    else assert.equal(args.includes('-s'), false, 'auto mode must not erase the network/modem APN profile');
  }
});

test('patched scanner repairs existing profiles and qmodem_init passes slot, not path', { skip: !process.env.QMODEM_TEST_TREE }, () => {
  const scanner = patchedFile('application/qmodem/files/usr/share/qmodem/modem_scan.sh');
  assert.match(scanner, /fi\n\s*uci -q batch <<EOF\nset qmodem\.\$section_name\.path="\$modem_path"\nset qmodem\.\$section_name\.data_interface="\$slot_type"/);
  const init = patchedFile('application/qmodem/files/etc/init.d/qmodem_init');
  assert.match(init, /modem_scan\.sh add "\$slot" "\$type"/);
  assert.doesNotMatch(init, /modem_scan\.sh add "\$path"/);
  assert.match(patchedFile('application/qmodem/files/usr/share/qmodem/modem_dial.sh'), /qmi\|mbim\|mhi\) proto="none"; protov6="none"/);
});

test('patched scanner defaults newly discovered modem2 to dial off before post-init', { skip: !process.env.QMODEM_TEST_TREE }, () => {
  const scanner = patchedFile('application/qmodem/files/usr/share/qmodem/modem_scan.sh');
  const assignment = scanner.split('\n').find(line => line.startsWith('set qmodem.$section_name.enable_dial='));
  assert.ok(assignment);
  for (const [section, expected] of [['4_1', '1'], ['2_1', '0']]) {
    const out = shell('section_name="$SECTION"\ncat << EOF\n' + assignment + '\nEOF', { SECTION: section });
    assert.equal(out, `set qmodem.${section}.enable_dial="${expected}"`);
  }
  const newProfileBranch = scanner.indexOf('uci -q set qmodem.$section_name=modem-device');
  assert.ok(scanner.indexOf(assignment) > newProfileBranch, 'default only belongs to new profile creation');
});

test('QModem consumes and preserves persistent network metrics across redial', { skip: !process.env.QMODEM_TEST_TREE }, () => {
  const dialer = patchedFile('application/qmodem/files/usr/share/qmodem/modem_dial.sh');
  const ui = patchedFile('luci/luci-app-qmodem-next/htdocs/luci-static/resources/view/qmodem/network_config.js');
  assert.match(dialer, /network_metric=\$\(uci -q get network\.\$\{interface_name\}\.metric\)/);
  assert.match(dialer, /if \[ "\$network_cfg" = "\$interface_name" \]; then/);
  assert.match(dialer, /uci -q set network\.\$\{network_cfg\}\.metric="\$\{metric:-200\}"/);
  assert.match(ui, /form\.DummyValue, '_route_metric'/);
  assert.match(ui, /uci\.load\('network'\)/);
});

test('route migration makes modem1 strictly preferred over modem2', () => {
  const migration = fs.readFileSync(path.join(root,
    'firmware/files/etc/uci-defaults/99-zbt-route-priority-repair'), 'utf8');
  assert.match(migration, /DEFAULTS_VERSION=2/);
  assert.match(migration, /4_1:200 2_1:210/);
  assert.match(migration, /uci -q set "network\.\$section\.metric=\$metric"/);
  assert.match(migration, /uci -q set "qmodem\.\$section\.metric=\$metric"/);
});
