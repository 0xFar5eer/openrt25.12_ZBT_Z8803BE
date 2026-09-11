'use strict';
// Execute the exact patched LuCI view against a small DOM/RPC fixture.
// No AT commands or connected modems are used by these tests.
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const tree = process.env.QMODEM_TEST_TREE;
const source = tree && fs.readFileSync(path.join(tree,
  'luci/luci-app-qmodem-next/htdocs/luci-static/resources/view/qmodem/config_advanced.js'), 'utf8');
const previousFormat = Object.getOwnPropertyDescriptor(String.prototype, 'format');
Object.defineProperty(String.prototype, 'format', {
  configurable: true, value: function(...values) { let i = 0; return this.replace(/%s/g, () => values[i++]); }
});
after(() => {
  if (previousFormat) Object.defineProperty(String.prototype, 'format', previousFormat);
  else delete String.prototype.format;
});

class Element {
  constructor(tag, attrs = {}, children = []) {
    this.tag = tag; this.attrs = attrs || {}; this.children = []; this.events = {};
    this.style = {}; this.dataset = {}; this.value = attrs.value || '';
    this.checked = !!attrs.checked; this.disabled = !!attrs.disabled;
    this.classList = { add() {}, remove() {} };
    for (const [key, value] of Object.entries(attrs)) {
      if (typeof value === 'function') this.addEventListener(key, value);
    }
    this.append(children);
  }
  append(children) {
    if (Array.isArray(children)) children.forEach(child => this.append(child));
    else if (children !== undefined && children !== null) this.appendChild(children);
  }
  appendChild(child) {
    this.children.push(child);
    if (this.tag === 'select' && !this.value && child.tag === 'option') this.value = child.value;
    return child;
  }
  get textContent() { return this.children.map(child => typeof child === 'object' ? child.textContent : String(child)).join(''); }
  set textContent(value) { this.children = [String(value)]; }
  addEventListener(event, callback) { (this.events[event] ||= []).push(callback); }
  fire(event) { return Promise.all((this.events[event] || []).map(callback => callback.call(this, { target: this }))); }
  querySelectorAll(selector) {
    const matches = node => selector.split(',').some(raw => {
      const part = raw.trim();
      if (part === 'input[type="checkbox"]') return node.tag === 'input' && node.attrs.type === 'checkbox';
      return node.tag === part;
    });
    return this.descendants().filter(matches);
  }
  descendants() { return this.children.flatMap(child => child instanceof Element ? [child, ...child.descendants()] : []); }
}
const E = (tag, attrs = {}, children = []) => {
  if (typeof attrs === 'string' || Array.isArray(attrs)) return new Element(tag, {}, attrs);
  return new Element(tag, attrs, children);
};
const content = (node, children) => { node.children = []; node.append(children); };
function fixture(rpc = {}) {
  const calls = []; const notifications = [];
  const qmodem = {
    getLockBand: async id => { calls.push(['read', id]); return response([41]); },
    setLockBand: async (id, params) => { calls.push(['write', id, params]); return { set_lockband: 'OK (readback verified)' }; },
    ...rpc
  };
  const view = new Function('view', 'ui', 'dom', 'qmodem', 'E', '_', source)(
    { extend: obj => obj },
    { addNotification: (_, node, type) => notifications.push({ text: node.textContent, type }) },
    { content, append: (node, children) => node.append(children) }, qmodem, E, s => s);
  return { view, qmodem, calls, notifications, container: E('div') };
}
function response(locked, extra = {}) {
  return { lockband: { NR: {
    read_state: 'verified',
    available_band: [41, 77, 78].map(id => ({ band_id: id, band_name: 'NR_' + id })),
    lock_band: locked, ...extra
  } } };
}
const modem = { id: '2_1', name: 'Modem 2', enabled: true };
const byId = (node, id) => node.descendants().find(el => el.attrs.id === id);
const button = (node, text) => node.querySelectorAll('button').find(el => el.textContent === text);
function deferred() { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; }
const settle = () => new Promise(resolve => setImmediate(resolve));

test('unknown bands have diagnostics/retry, never actionable all-off checkboxes', { skip: !tree }, async () => {
  let reads = 0;
  const f = fixture({ getLockBand: async id => {
    assert.equal(id, '2_1');
    return reads++ === 0 ? response([], { read_state: 'unknown', read_error: 'Timed out',
      read_command: 'AT+QNWPREFCFG="nr5g_band"', read_response: '+CME ERROR: 3 <not HTML>' }) : response([41, 77]);
  } });
  await f.view.loadLockBand(modem, f.container);
  assert.match(f.container.textContent, /Current bands are unknown, not all disabled/);
  assert.match(f.container.textContent, /AT\+QNWPREFCFG="nr5g_band"/);
  assert.match(f.container.textContent, /\+CME ERROR: 3 <not HTML>/);
  assert.equal(f.container.querySelectorAll('input').length, 0);
  assert.equal(button(f.container, 'Apply'), undefined);
  await button(f.container, 'Read bands again').fire('click');
  assert.equal(f.container.querySelectorAll('input').filter(el => el.checked).length, 2);
  assert.equal(byId(f.container, 'locked_2_1_NR').textContent, 'NR_41, NR_77');
});

test('drafts never replace reported bands; failed write refreshes actual state on the same modem', { skip: !tree }, async () => {
  let reads = 0; const pending = deferred(); const writes = [];
  const f = fixture({
    getLockBand: async id => { assert.equal(id, '2_1'); return response(reads++ === 0 ? [41] : [78]); },
    setLockBand: (id, params) => { writes.push([id, params]); return pending.promise; }
  });
  await f.view.loadLockBand(modem, f.container);
  const current = byId(f.container, 'locked_2_1_NR');
  const cb = byId(f.container, 'band_2_1_NR_77');
  cb.checked = true; await cb.fire('change');
  assert.equal(current.textContent, 'NR_41');
  assert.match(f.container.textContent, /Unsaved selection \(not applied to modem\): NR_41, NR_77/);
  const apply = button(f.container, 'Apply'); const operation = apply.fire('click');
  assert.equal(f.container.querySelectorAll('button, input').every(el => el.disabled), true);
  await apply.fire('click'); // Even a duplicate programmatic event cannot overlap writes.
  assert.deepEqual(writes, [['2_1', { band_class: 'NR', lock_band: '41,77' }]]);
  pending.resolve({ set_lockband: 'ERROR: Requested bands differ from readback' });
  await operation;
  assert.equal(reads, 2);
  assert.equal(byId(f.container, 'locked_2_1_NR').textContent, 'NR_78');
  assert.equal(f.notifications.length, 1);
  assert.equal(f.notifications[0].type, 'error');
  assert.match(f.notifications[0].text, /Requested bands differ/);
  assert.equal(button(f.container, 'Apply').disabled, false);
});

test('empty selection cannot write an unlock command or claim all bands are unlocked', { skip: !tree }, async () => {
  const f = fixture({ getLockBand: async () => response([41]) });
  await f.view.loadLockBand(modem, f.container);
  const cb = byId(f.container, 'band_2_1_NR_41');
  cb.checked = false; await cb.fire('change');
  assert.equal(byId(f.container, 'locked_2_1_NR').textContent, 'NR_41');
  await button(f.container, 'Apply').fire('click');
  assert.equal(f.calls.length, 0);
  assert.match(f.notifications[0].text, /Select at least one band/);
  assert.doesNotMatch(f.container.textContent, /All bands unlocked/);
});

test('valid readback stays visible read-only when the capability list is missing', { skip: !tree }, async () => {
  for (const available_band of [[], undefined]) {
    const f = fixture({ getLockBand: async () => response([41, 77], { available_band }) });
    await f.view.loadLockBand(modem, f.container);
    assert.equal(byId(f.container, 'locked_2_1_NR').textContent, '41, 77');
    assert.match(f.container.textContent, /shown read-only; no capability list has been guessed/);
    assert.equal(f.container.querySelectorAll('input').length, 0);
    assert.equal(button(f.container, 'Apply'), undefined);
  }
});

test('verified writes succeed only after a real OK response and re-read actual values', { skip: !tree }, async () => {
  for (const reply of [
    { set_lockband: 'OK (readback verified)' },
    { result: { set_lockband: 'ERROR: Not OK' } },
    { set_lockband: 'BROKEN' }, null
  ]) {
    let reads = 0;
    const f = fixture({ getLockBand: async () => { reads++; return response([41]); }, setLockBand: async () => reply });
    await f.view.loadLockBand(modem, f.container);
    await button(f.container, 'Apply').fire('click');
    assert.equal(reads, 2);
    assert.equal(f.notifications[0].type, reply && reply.set_lockband === 'OK (readback verified)' ? 'success' : 'error');
  }
});

test('overlapping reads never replace newer band data with an old response', { skip: !tree }, async () => {
  const old = deferred(), fresh = deferred(); let calls = 0;
  const f = fixture({ getLockBand: () => calls++ === 0 ? old.promise : fresh.promise });
  const a = f.view.loadLockBand(modem, f.container);
  const b = f.view.loadLockBand(modem, f.container);
  fresh.resolve(response([77])); await b;
  old.resolve(response([41])); await a;
  assert.equal(byId(f.container, 'locked_2_1_NR').textContent, 'NR_77');
});

test('late modem 1 feature response cannot expose modem 1 controls under a modem 2 selector', { skip: !tree }, async () => {
  for (const staleFailure of [false, true]) {
    const first = deferred(), second = deferred();
    const f = fixture({ getDisabledFeatures: id => id === '4_1' ? first.promise : second.promise });
    f.view.createTabInterface = m => E('div', { id: 'tabs_' + m.id }, m.name);
    const root = f.view.render([{ id: '4_1', name: 'Modem 1', enabled: true }, modem]);
    const selector = byId(root, 'modem_selector');
    selector.value = '2_1'; await selector.fire('change');
    second.resolve({ disabled_features: [] }); await settle();
    if (staleFailure) first.reject(new Error('Old modem timed out'));
    else first.resolve({ disabled_features: [] });
    await settle();
    assert.equal(byId(root, 'tab_container').textContent, 'Modem 2');
    assert.equal(byId(root, 'tabs_4_1'), undefined);
  }
});
