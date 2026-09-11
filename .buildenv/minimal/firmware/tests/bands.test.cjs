'use strict';
// No modem is contacted: BusyBox executes the production helper against
// disposable sysfs links, AT transcripts and a small jshn event recorder.
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zbt-bands-test-'));
after(() => fs.rmSync(temporary, { recursive: true, force: true }));
const read = name => fs.readFileSync(path.join(root, 'firmware/files/usr/lib/zbt', name), 'utf8');
const library = read('dual-modem.sh').replace('zbt_port_matches()', 'fixture_port_matches()') + '\n' +
  read('quectel-bands.sh').replace('. /usr/lib/zbt/dual-modem.sh', '');
const mask = (value, key = 'nr5g_band') => `+QNWPREFCFG: "${key}",${value}\r\nOK\r\n`;
const mock = String.raw`
zbt_port_matches() {
  printf '%s\t%s\n' "$1" "$2" >> "$PORT_CALLS"
  fixture_port_matches "$@"
}
uci() {
  [ "$1" = -q ] && [ "$2" = get ] || return 1
  case "$3" in
    qmodem.2_1.*) printf '%s\n' '41/77/78';;
    qmodem.4_1.*) printf '%s\n' '1/3/7';;
    *) return 1;;
  esac
}
at() {
  printf '%s\t%s\n' "$1" "$2" >> "$AT_CALLS"
  case "$2" in
    AT+QNWPREFCFG=\"*\",*)
      cat "$FIXTURE/write.reply"
      [ ! -f "$FIXTURE/write.fail" ]
      ;;
    AT+QNWPREFCFG=\"*\")
      count=0
      [ ! -f "$FIXTURE/count" ] || read -r count < "$FIXTURE/count"
      count=$((count + 1))
      printf '%s\n' "$count" > "$FIXTURE/count"
      cat "$FIXTURE/read.$count.reply"
      [ ! -f "$FIXTURE/read.$count.fail" ]
      ;;
    *) return 1;;
  esac
}
sleep() {
  # No wall-clock sleep: each call is the intended readback settling delay.
  printf '%s\n' "$1" >> "$SLEEP_CALLS"
  if [ -n "$REASSIGN_AFTER_READ" ] && [ -f "$FIXTURE/count" ]; then
    read -r count < "$FIXTURE/count"
    if [ "$count" = "$REASSIGN_AFTER_READ" ]; then
      ln -sfn "$PEER_DEVICE" "$TARGET_LINK"
    fi
  fi
}
json_add_object() { printf 'object\037%s\037\036' "$1"; }
json_add_array() { printf 'array\037%s\037\036' "$1"; }
json_add_string() { printf 'string\037%s\037%s\036' "$1" "$2"; }
json_close_object() { printf 'close\037\037\036'; }
json_close_array() { printf 'close\037\037\036'; }
add_avalible_band_entry() {
  json_add_object ''
  json_add_string band "$1"
  json_add_string name "$2"
  json_close_object
}
`;
function fixture() {
  const dir = fs.mkdtempSync(path.join(temporary, 'case-'));
  const sys = path.join(dir, 'sys');
  // Neither physical slot is inferred from its tty/wwan number.
  for (const [usb, net, tty] of [['4-1', 'wwan8', 'ttyUSB6'], ['2-1', 'wwan3', 'ttyUSB2']]) {
    const device = path.join(sys, 'devices', usb);
    fs.mkdirSync(path.join(device, usb + ':1.4/net', net), { recursive: true });
    fs.mkdirSync(path.join(device, usb + ':1.2', tty), { recursive: true });
    fs.mkdirSync(path.join(sys, 'bus/usb/devices'), { recursive: true });
    fs.symlinkSync(device, path.join(sys, 'bus/usb/devices', usb));
    fs.mkdirSync(path.join(sys, 'class/tty', tty), { recursive: true });
    fs.symlinkSync(path.join(device, usb + ':1.2', tty), path.join(sys, 'class/tty', tty, 'device'));
  }
  const env = {
    ...process.env, FIXTURE: dir, ZBT_SYSFS: sys,
    AT_CALLS: path.join(dir, 'at.log'), PORT_CALLS: path.join(dir, 'ports.log'),
    SLEEP_CALLS: path.join(dir, 'sleeps.log'),
    TARGET_LINK: path.join(sys, 'class/tty/ttyUSB2/device'),
    PEER_DEVICE: path.join(sys, 'devices/4-1/4-1:1.2/ttyUSB6'),
    REASSIGN_AFTER_READ: ''
  };
  function put(name, value) { fs.writeFileSync(path.join(dir, name), value); }
  function lines(name) {
    const file = path.join(dir, name);
    return fs.existsSync(file) ? fs.readFileSync(file, 'utf8').trim().split('\n').filter(Boolean) : [];
  }
  function run(body, extra = {}) {
    const result = spawnSync('busybox', ['sh', '-c', library + '\n' + mock + '\n' + body], {
      encoding: 'utf8', timeout: 10000, env: { ...env, ...extra }
    });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr + '\n' + result.stdout);
    return result.stdout.trim();
  }
  function replies(reads, write = 'OK\r\n') {
    put('write.reply', write);
    reads.forEach((reply, index) => put(`read.${index + 1}.reply`, reply));
  }
  const set = (extra = {}, overrides = '') => run(`
config_section=2_1; at_port=/dev/ttyUSB2; band_class=NR; lock_band=77,41
${overrides}
zbt_set_lockband_nr
printf '%s\n' "$res"
`, extra);
  return { dir, sys, put, lines, run, replies, set };
}
function decode(events) {
  const result = {}, stack = [result];
  for (const event of events.split('\x1e').filter(Boolean)) {
    const [kind, key, value] = event.split('\x1f');
    if (kind === 'close') { assert.ok(stack.length > 1); stack.pop(); continue; }
    const item = kind === 'object' ? {} : kind === 'array' ? [] : value;
    const current = stack.at(-1);
    if (Array.isArray(current)) current.push(item); else current[key] = item;
    if (kind === 'object' || kind === 'array') stack.push(item);
  }
  assert.equal(stack.length, 1);
  return result;
}
function assertScoped(f, expectedReads, port = '/dev/ttyUSB2') {
  const calls = f.lines('at.log');
  const writes = calls.filter(line => /",/.test(line));
  const reads = calls.filter(line => !/",/.test(line));
  assert.equal(writes.length, 1, 'never repeat a persistent band write');
  assert.equal(reads.length, expectedReads);
  assert.ok(reads.length <= 3, 'readback is bounded');
  for (const line of calls) {
    const [actualPort, command] = line.split('\t');
    assert.equal(actualPort, port, 'never probe or configure the peer modem');
    assert.match(command, /^AT\+QNWPREFCFG="nr5g_band"(?:,41:77)?$/);
  }
}

test('band masks tolerate whitespace, CRLF, quoted values, order and duplicate entries', () => {
  const f = fixture();
  const response = ' AT+QNWPREFCFG="nr5g_band"\r\n \t+QNWPREFCFG: "nr5g_band", "78 : 41: 77 :41" \r\n \tOK \r\n';
  assert.equal(f.run('zbt_band_values "$RESPONSE" nr5g_band', { RESPONSE: response }), '41\n77\n78');
});

test('duplicate reply lines never concatenate into an invented band 4141', () => {
  const f = fixture();
  const response = '+QNWPREFCFG: "nr5g_band",41\r\n+QNWPREFCFG: "nr5g_band",41\r\nOK\r\n';
  assert.equal(f.run('zbt_band_values "$RESPONSE" nr5g_band', { RESPONSE: response }), '41');
  const reordered = '+QNWPREFCFG: "nr5g_band",41:77:41\r\n+QNWPREFCFG: "nr5g_band",77:41\r\nOK\r\n';
  assert.equal(f.run('zbt_band_values "$RESPONSE" nr5g_band', { RESPONSE: reordered }), '41\n77');
});

test('truncated, conflicting, wrong-key, failed and zero masks remain unknown', () => {
  const invalid = [
    '', 'OK', '+QNWPREFCFG: "nr5g_band",41',
    'OK\n+QNWPREFCFG: "nr5g_band",41',
    'OK\n' + mask('41'),
    '+QNWPREFCFG: "nr5g_band",41\n+QNWPREFCFG: "nr5g_band",78\nOK',
    mask('41', 'nsa_nr5g_band'), mask('0'), mask('41:0'), mask('41::77'),
    mask('41 77'), mask('4"1'), mask('"41" : "77"'),
    mask('41') + 'ERROR\r\n', mask('41') + '+CME ERROR: 50\r\n',
    mask('41') + '+CMS ERROR: 500\r\n', mask('41') + 'NO CARRIER\r\n'
  ];
  for (const response of invalid) {
    const f = fixture();
    assert.equal(f.run('zbt_band_values "$RESPONSE" nr5g_band || printf unknown', { RESPONSE: response }), 'unknown', JSON.stringify(response));
  }
});

test('GET reports independently verified and unknown band classes with diagnostic replies', () => {
  const f = fixture();
  f.replies([mask('41:77', 'gw_band'), 'ERROR\r\n', mask('41:78'), mask('77', 'nsa_nr5g_band')]);
  const data = decode(f.run('config_section=2_1; zbt_get_lockband_nr /dev/ttyUSB2'));
  assert.deepEqual(Object.keys(data), ['UMTS', 'LTE', 'NR', 'NR_NSA']);
  assert.equal(data.UMTS.read_state, 'verified');
  assert.deepEqual(data.UMTS.lock_band, ['41', '77']);
  assert.equal(data.LTE.read_state, 'unknown');
  assert.match(data.LTE.read_error, /Unknown is not all bands off/);
  assert.equal(data.LTE.read_response, 'ERROR');
  assert.equal(data.LTE.read_command, 'AT+QNWPREFCFG="lte_band"');
  assert.equal(data.NR.read_state, 'verified');
  assert.deepEqual(data.NR.lock_band, ['41', '78']);
  assert.equal(data.NR.read_error, undefined);
  assert.deepEqual(data.NR.available_band.map(entry => entry.band), ['41', '77', '78']);
  assert.equal(f.lines('ports.log').length, 4, 'validate ownership before each band class query');
  assert.ok(f.lines('at.log').every(line => line.startsWith('/dev/ttyUSB2\tAT+QNWPREFCFG=')));
  assert.ok(f.lines('at.log').every(line => !line.includes('",')), 'GET has no persistent writes');
});

test('GET transport failure does not accept a seemingly valid response or expose identity URCs', () => {
  const f = fixture();
  f.replies([mask('41', 'gw_band'), mask('41', 'lte_band'), '+CIMI: PRIVATE_SIM_IDENTIFIER\r\n' + mask('41'), mask('41', 'nsa_nr5g_band')]);
  f.put('read.3.fail', '');
  const data = decode(f.run('config_section=2_1; zbt_get_lockband_nr /dev/ttyUSB2'));
  assert.equal(data.NR.read_state, 'unknown');
  assert.match(data.NR.read_error, /transport failed or timed out/);
  assert.deepEqual(data.NR.lock_band, []);
  assert.doesNotMatch(data.NR.read_response, /CIMI|PRIVATE_SIM_IDENTIFIER/);
});

test('GET rejects a peer modem port without sending any AT query', () => {
  const f = fixture();
  const data = decode(f.run('config_section=2_1; zbt_get_lockband_nr /dev/ttyUSB6'));
  for (const value of Object.values(data)) {
    assert.equal(value.read_state, 'unknown');
    assert.match(value.read_error, /does not belong/);
    assert.deepEqual(value.lock_band, []);
  }
  assert.deepEqual(f.lines('at.log'), []);
});

test('SET verifies a delayed band change with one write and three reads at most', () => {
  for (const successRead of [1, 2, 3]) {
    const f = fixture();
    f.replies(Array.from({ length: successRead }, (_, i) => mask(i + 1 === successRead ? '77:41' : '78')));
    assert.equal(f.set(), 'OK (readback verified)');
    assertScoped(f, successRead);
    assert.equal(f.lines('sleeps.log').length, successRead - 1);
    assert.equal(f.lines('ports.log').length, successRead + 1);
  }
});

test('SET stable mismatch reports actual and requested bands instead of claiming a carrier restriction', () => {
  const f = fixture(); f.replies([mask('78'), mask('78'), mask('78')]);
  const result = f.set();
  assert.match(result, /^ERROR: Band readback differs for nr5g_band/);
  assert.match(result, /Requested: 41:77; modem reports: 78/);
  assert.doesNotMatch(result, /readback verified|firmware\/carrier restrictions/);
  assertScoped(f, 3);
  assert.deepEqual(f.lines('sleeps.log'), ['1', '1']);
});

test('SET unknown readback is distinct from a real mismatch and preserves useful raw reply', () => {
  const f = fixture();
  f.replies([mask('0'), 'ERROR\r\n', '+QNWPREFCFG: "nr5g_band",41']);
  const result = f.set();
  assert.match(result, /readback is unknown/);
  assert.match(result, /Requested: 41:77/);
  assert.match(result, /Reply: \+QNWPREFCFG: "nr5g_band",41/);
  assert.doesNotMatch(result, /modem reports:|readback verified/);
  assertScoped(f, 3);
});

test('SET transient transport failure retries only the read, and persistent failure stays unknown', () => {
  for (const recover of [false, true]) {
    const f = fixture();
    f.replies([mask('41:77'), mask('41:77'), mask('41:77')]);
    f.put('read.1.fail', '');
    if (!recover) { f.put('read.2.fail', ''); f.put('read.3.fail', ''); }
    const result = f.set();
    if (recover) assert.equal(result, 'OK (readback verified)');
    else {
      assert.match(result, /readback is unknown/);
      assert.match(result, /transport failed or timed out/);
      assert.doesNotMatch(result, /readback verified/);
    }
    assertScoped(f, recover ? 2 : 3);
  }
});

test('SET unacknowledged or transport-failed write never retries the write or queries success', () => {
  for (const [reply, fail] of [['ERROR\r\n', false], ['', false], ['OK\r\n', true]]) {
    const f = fixture(); f.replies([], reply);
    if (fail) f.put('write.fail', '');
    assert.match(f.set(), /^ERROR: Modem rejected band command or did not acknowledge it/);
    assertScoped(f, 0);
    assert.deepEqual(f.lines('sleeps.log'), []);
  }
});

test('SET revalidates physical ownership before each read and stops querying a reassigned port', () => {
  for (const afterRead of [1, 2]) {
    const f = fixture(); f.replies([mask('78'), mask('78'), mask('41:77')]);
    const result = f.set({ REASSIGN_AFTER_READ: String(afterRead) });
    assert.match(result, /readback is unknown/);
    assert.match(result, /does not belong to this modem/);
    assertScoped(f, afterRead);
    assert.equal(f.lines('ports.log').length, 4, 'initial write and every attempted read are validated');
    assert.deepEqual(f.lines('sleeps.log'), ['1', '1']);
  }
});

test('SET invalid selection, capability mismatch and peer port never cause AT writes', () => {
  for (const [overrides, message] of [
    ['lock_band=0', /Invalid band selection/],
    ['lock_band=41,,77', /Invalid band selection/],
    ['lock_band=99', /not in this modem capability list/],
    ['at_port=/dev/ttyUSB6', /does not belong to this modem/],
    ['band_class=unknown', /Invalid band selection/]
  ]) {
    const f = fixture();
    assert.match(f.set({}, overrides), message);
    assert.deepEqual(f.lines('at.log'), []);
  }
});
