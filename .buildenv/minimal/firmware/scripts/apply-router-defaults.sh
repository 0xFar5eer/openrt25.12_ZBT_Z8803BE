#!/bin/sh
# Kept to prevent an old runbook from reintroducing competing DHCP/proto
# stubs and globally restarting both modems on an already-working router.
echo 'This legacy live-defaults script is retired. Install the fixed firmware and use the per-modem QModem controls. No settings were changed.' >&2
exit 2
