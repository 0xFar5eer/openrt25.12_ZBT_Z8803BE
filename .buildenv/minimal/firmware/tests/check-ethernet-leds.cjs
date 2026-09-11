'use strict';
// Verify the WAN backport against the exact inherited driver, and exercise
// its real C LED callbacks against simulated MDIO registers (no hardware).
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const base = 'https://raw.githubusercontent.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE/edc738504fe8fae81eb15de967456204699b1830/';

function addedFile(patch, name) {
  const marker = '+++ b/' + name + '\n';
  assert.ok(patch.includes(marker), name);
  return patch.split(marker)[1].split(/^--- /m)[0].split('\n')
    .filter(line => line.startsWith('+')).map(line => line.slice(1)).join('\n') + '\n';
}

module.exports = async function checkEthernet(root, temporary, run) {
  const names = [
    'target/linux/mediatek/dts/mt7988a-zbtlink-zbt-z8803be.dts',
    'target/linux/mediatek/patches-6.12/701-net-phy-mediatek-add-driver-for-built-in-2.5G-ethern.patch',
    'target/linux/mediatek/patches-6.12/752-net-phy-mediatek-i2p5g-add-support-for-mt7987.patch',
    'target/linux/generic/backport-6.12/720-05-v6.13-net-phy-mediatek-Move-LED-helper-functions-into-mtk-.patch',
    'target/linux/generic/backport-6.12/720-06-v6.13-net-phy-mediatek-Improve-readability-of-mtk-phy-lib..patch'
  ];
  const sources = await Promise.all(names.map(async name => {
    const response = await fetch(base + name, { signal: AbortSignal.timeout(20000) });
    assert.equal(response.status, 200, name);
    return response.text();
  }));
  const tree = path.join(temporary, 'ethernet');
  const write = (name, content) => {
    const dest = path.join(tree, name);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, content);
  };
  const read = name => fs.readFileSync(path.join(tree, name), 'utf8');
  const apply = (patch, reverse = false) =>
    run('patch', ['--batch', '--fuzz=0', reverse ? '--reverse' : '--forward', '-p1', '-d', tree], { input: patch });
  const driverPath = 'drivers/net/phy/mediatek/mtk-2p5ge.c';
  const headerPath = 'drivers/net/phy/mediatek/mtk.h';
  const libraryPath = 'drivers/net/phy/mediatek/mtk-phy-lib.c';
  write(names[0], sources[0]);
  const boardPatch = fs.readFileSync(path.join(root, 'firmware/patches/zbt-wan-led.patch'), 'utf8');
  apply(boardPatch);
  assert.match(read(names[0]), /&i2p5gbe_led0 \{\s*color = <LED_COLOR_ID_AMBER>;\s*function = LED_FUNCTION_WAN;\s*linux,default-trigger = "netdev";\s*status = "okay";/);
  apply(boardPatch, true);
  assert.equal(read(names[0]), sources[0], 'WAN LED patch must reverse without altering power/SIM/other nodes');
  write(driverPath, addedFile(sources[1], driverPath));
  write(headerPath, addedFile(sources[3], headerPath));
  write(libraryPath, addedFile(sources[3], libraryPath));
  apply(sources[2]);
  apply(sources[4]);
  const originalDriver = read(driverPath), originalHeader = read(headerPath);
  const kernelPatch = fs.readFileSync(path.join(root, 'firmware/kernel-patches/753-net-phy-mediatek-mt7988-led-control.patch'), 'utf8');
  apply(kernelPatch);
  const driver = read(driverPath);
  const priv = driver.match(/struct mtk_i2p5ge_phy_priv \{[\s\S]*?\n\};/)[0];
  const callbacks = driver.slice(driver.indexOf('static const unsigned long mt7988_led_triggers'),
    driver.indexOf('static int mt798x_2p5ge_phy_probe'));
  assert.ok(callbacks.includes('mt7988_2p5ge_led_hw_control_set'));
  assert.match(driver, /\.name = "MediaTek MT7988 2.5GbE PHY",[\s\S]*?\.led_brightness_set = mt7988_2p5ge_led_brightness_set/);
  // Compile production callback/helper bodies. Only the MDIO transport and
  // kernel type/bit helpers are replaced, so masks and cache layout are tested.
  const library = read(libraryPath).replace(/^#include.*$/gm, '')
    .replace(/^EXPORT_SYMBOL_GPL\(.*$/gm, '').replace(/^MODULE_.*$/gm, '');
  const harness = fs.readFileSync(path.join(root, 'firmware/tests/ethernet-led-harness.c'), 'utf8');
  const code = harness.replace('/* HEADER */', read(headerPath))
    .replace('/* PRIVATE */', priv).replace('/* LIBRARY */', library)
    .replace('/* CALLBACKS */', callbacks);
  write('led-check.c', code);
  run('cc', ['-std=gnu11', '-Wall', '-Werror', '-o', path.join(tree, 'led-check'), path.join(tree, 'led-check.c')]);
  process.stdout.write(run(path.join(tree, 'led-check'), []));
  apply(kernelPatch, true);
  assert.equal(read(driverPath), originalDriver);
  assert.equal(read(headerPath), originalHeader);
  console.log('WAN DTS and Ethernet driver patches apply/reverse against the pinned source');
};
