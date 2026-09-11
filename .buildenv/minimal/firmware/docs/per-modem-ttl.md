# Independent modem TTL policy

Open **Modem → QModem → TTL**. Modem 1 and Modem 2 each have their own enable switch, automatic/custom mode, and custom value from 1 to 255. For example, choose Custom value with 65 on Modem 1 and 128 on Modem 2, or uncheck either modem to leave its TTL alone. Its last custom value is retained while disabled or in automatic mode.

The selected value sets IPv4 TTL and IPv6 Hop Limit on egress, including router-originated traffic. Rules resolve the physical USB slots (`4-1` / `2-1`) and match the current interface index, not a guessed `wwan0` name. A removed interface's rule cannot match a different modem that reuses its name. Missing or ambiguous devices are skipped; there is no fallback to the other modem. Hotplug refreshes the bindings without restarting either dialer or changing modem power/SIM selection. Wired WAN TTL is not modified.

## Defaults and upgrades

- The primary modem retains the inherited automatic behavior, now visible and switchable. The secondary modem's TTL policy defaults off in both editions. This is independent of its power/dial setting; minimal still defaults modem 2's power/dial off.
- Automatic mode retains the old passive address heuristic: 65 for recognized modem-NAT address prefixes, otherwise 64. It runs separately for each enabled modem and never rewrites a stored custom value. It is not an AT query, carrier database or guarantee that a particular plan requires that value.
- An explicit old enabled global TTL is copied to both modem policies as a custom value. An old standalone primary rule is migrated when its exact structure is recognized. Existing per-modem choices are preserved.
- The two old TTL include files are moved to `/etc/qmodem-ttl-backup/`, not deleted. Review archived hand-edited rules if necessary; arbitrary unrelated firewall files are not moved. The old global automatic writer is disabled.
- The old boot-time `wwan0` rule is no longer generated. Disabling both modem policies removes this feature's TTL rules, rather than leaving an invisible rewrite active.

## Offloading and applying changes

As with the inherited TTL plugin, enabling a TTL policy disables software and hardware flow offloading globally so packets reach the rewrite rules. This can reduce routing performance. Do not re-enable flow offloading while either TTL policy is active. When both are disabled, offloading is **not** automatically re-enabled, avoiding conflicts with SQM or other administrator settings.

Generated rules live in RAM and are included by firewall4. An unchanged refresh does not reload the firewall. Changed rules use `fw4 reload`, not a firewall/network restart or modem redial. If applying fails, the previous generated include and offload settings are restored, and the error is logged with tag `qmodem_ttl`.

## Verification

Host fixtures cover separate policies, invalid values, reconnection, migration, preservation of custom settings, rollback and LuCI/ACL behavior. The optional real-packet test runs in a disposable network namespace and verifies IPv4/IPv6 packets on two independent virtual links: different values, either policy disabled and both disabled. A disabled policy leaves the original test TTL/Hop Limit of 42 unchanged.

Sanity CI runs both kinds of checks. They do not test an actual cellular carrier, SIM, modem firmware or RF path; confirm the new image on the router before relying on it.
