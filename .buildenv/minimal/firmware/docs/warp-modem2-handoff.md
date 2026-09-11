# Warp modem 2 handoff: source changes versus SIM-specific setup

## What the live transcript establishes

The supplied September 10 Warp export was reviewed against the actual commands,
their results, the live dialer/backup diff, and the later SIM-swap tests.

- Modem 2's saved hardware PDP profile initially used `nxtgenphone`.
- Warp selected `broadband` for the user's AT&T tablet-plan SIM, with no
  authentication, and temporarily used QModem's explicit/forced profile setting.
  Later logs show the **saved modem profile** using `broadband`, LTE packet
  attachment and an IPv4 data session. This first attachment evidence still
  used IPv4v6; IPv4-only was not what first established LTE registration.
- A later controlled `nxtgenphone` comparison remained LTE-attached but its
  IPv4 request was rejected with 3GPP cause 33, “requested service option not
  subscribed.” Warp restored `broadband`.
- Selecting `pdp_type=ip` stopped the separately rejected IPv6 request. It did
  not, by itself, restore unrestricted Internet access. Carrier DNS/att.com
  worked; independent destinations initially failed.
- The temporary force-profile option was removed. That did **not** revert the
  APN already stored inside the modem.
- After the user moved the T-Mobile SIM into modem 2 and rebooted, strict
  modem-2-bound tests returned Google HTTP 204 and Wikipedia/AT&T HTTP 200.
  The temporary TTL rule was absent. This demonstrates that physical modem 2
  could pass real Internet traffic without those experimental TTL/MTU rules.
- The transcript's tablet/account explanations changed during testing. Its
  results do not establish a specific carrier-blocking mechanism. The user's
  subsequent SIM diagnosis is separate from what source changes are justified.

## The three code changes carried into both firmware projects

The actual live diff against the pre-edit backup showed only these corrections
in the pinned QModem `modem_dial.sh`:

1. Add the missing space before `]` in the failed SIM-PIN retry comparison.
   Without it, the test is malformed and an already-failed PIN can be retried.
2. Add the missing space before `]` when checking `suggest_pdp_index`. The
   original emits a `missing ]` diagnostic for a nonempty suggestion. Tests
   confirm the correction preserves explicit selections and the existing
   platform default when no suggestion is supplied.
3. Test `pincode`, not unrelated `pin`, before falling back from the selected
   internal SIM-input-2 PIN to that module's primary PIN.

These are shared dialer correctness fixes, **not proof that any one fixed
registration**. The transcript explicitly still showed “Detached” after the
initial shell repairs. Internal SIM input 2 is not the same thing as physical
modem 2; SIM wiring/selection has not been changed.

The patch is applied against the pinned QModem revision in both projects.
Behavioral tests exercise failed-PIN suppression, absent/present PDP suggestions,
explicit PDP preservation, internal-SIM PIN fallback, physically isolated APN
arguments, IPv4-only `-4` without `-6`, and removal of the temporary `-F` flag.

## Reproducing the user's plan-specific setup

Use **QModem → Configuration → Modem 2 → Edit**. For the same confirmed AT&T
tablet plan as that diagnostic session, its retained settings were:

| Setting | Retained value |
|---|---|
| APN | `broadband` |
| PDP type | IPv4 / `ip` |
| Authentication | None |
| Metric | 210 |
| Force APN setting | Unset after the one-time profile write |
| Interface address owner | Existing `quectel-CM-M -d`, with `proto=none` |

This is a reproduction of one SIM/plan's test, **not a universal carrier preset**.
Keep IPv4v6 available for carriers/plans that support it. If the SIM moves,
configure the modem containing that SIM; do not bind a carrier assumption to
physical slot 2. Use the normal explicit APN setting and targeted redial to
update a mismatched saved profile. If a force-profile operation is specifically
needed, it must be deliberate, per-modem, verified and cleared afterward—not
an automatic startup loop.

Public image defaults remain carrier-neutral except for the documented AT&T US
`310/410` auto-mode fallback to `broadband`. Existing manual APN/PDP/PIN/SIM
settings are preserved. The full image retains its existing two-slot defaults;
Minimal still leaves modem 2 powered/dialed off until the user enables it.
There is no on-router deployment in this source change.

## Deliberately excluded from the firmware

No new global restarts, competing `proto=qmi`/DHCP manager, hardcoded AT port,
blanket carrier APN override, modem identity change, band/MBN rewrite, GPIO remapping,
power-cycle loop, automatic factory reset, CGATT detach/reattach loop, temporary
policy-routing rule, forced TTL, or arbitrary MTU was imported from Warp.

The existing physical USB mapping (`4_1 → 4-1`, `2_1 → 2-1`), one address
owner and per-modem service isolation stay intact. Modem 2 redial must not
restart the working peer.

## Acceptance on hardware

With a working SIM/plan, check the selected modem's saved APN and registration,
IPv4/IPv6 results separately, modem-bound independent HTTPS/DNS, and forwarded
LAN-client traffic. Confirm the peer modem remains connected and observe
stability over time. A tower signal, an “interface up” label, or a short test
alone is not a long-term stability guarantee.
