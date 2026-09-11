# Per-modem band readback and editing

The band page reads the configured mask from the selected modem. It is not a
display of the currently serving cell, carrier coverage, or successful network
registration. Selecting an NR band does not guarantee SA service.

## Repairs

- Parse complete, exact-key `+QNWPREFCFG` replies with an `OK` terminator.
  Accept ordinary leading whitespace, CRLF, quoted masks, and numeric ordering
  differences. Never concatenate repeated reply lines into invented band IDs.
- Keep failed, truncated, ambiguous, zero, or missing replies **unknown**.
  Unknown rows show a read-only diagnostic and a retry button, not editable
  unchecked boxes implying all bands are off.
- Separate the modem's reported bands from the user's pending checkbox edits.
  After an accepted or rejected change, reload the actual modem state.
- Issue a persistent band write only once. Verify with up to three read-only
  queries, one second apart after the first attempt. Success requires exact
  agreement; an unreadable reply and a readable mismatch have different errors.
  This bounds the number of queries, not the underlying AT transport's wall-clock
  wait. A wedged or busy AT transport can still time out in LuCI; it must not be
  interpreted as an empty mask or a successful write. This patch does not kill
  shared modem processes or change global RPC timeouts.
- Show the requested and actual masks for a mismatch. For an unreadable reply,
  show the query and filtered band/status response. Do not include SIM identities
  or unrelated AT notifications.
- Revalidate the physical USB path before every AT operation. Never fall back
  from Modem 2 to Modem 1. Ignore stale UI replies after switching modems.

No GPIO, SIM selection, APN, radio mode, MBN profile, module firmware, or peer
modem restart is part of this repair. The firmware flavor's other defaults are
unchanged.

## What is known about the reported failure

The supplied logs identify RM551E-GL modules running different firmware:
`RM551EGL00AAR01A02M8G` and `RM551EGL00AAR02A02M8G`. The screenshot's old
“readback did not match” error did not distinguish parsing failure from a modem
actually retaining a different mask. It therefore did **not** establish carrier
restrictions, all bands disabled, or the cause of Modem 2's detached state.

The commands remain `gw_band`, `lte_band`, `nr5g_band` (SA), and
`nsa_nr5g_band` (NSA), using colon-separated band numbers. We do not substitute
`ue_capability_band` or `policy_band` for the configured mask: those are different
information. See the [Quectel command manual](https://www.quectel.com/content/uploads/2024/05/Quectel_RG50xQRM5xxQ_Series_AT_Commands_Manual_V1.2.pdf)
and [Quectel's capability/MBN explanation](https://forums.quectel.com/t/question-about-the-support-nr5g-band-of-rm500q-gl/10945).

Quectel also [cautions against assuming R01 and R02 are interchangeable](https://forums.quectel.com/t/rm551-lost-5g-with-firmare-rm551egl00aar02a02m8g/53078).
Do not flash modem firmware, clear profiles, reset every band, or force SA-only
mode based on this UI error.

## Validation and remaining hardware check

Automated tests use fixture USB paths and AT replies, not a connected router.
They cover complete/invalid replies, duplicate lines, write verification,
per-modem isolation, unknown UI state, pending edits, failed-write refresh, and
out-of-order modem selection replies. The upstream patch is tested against the
pinned QModem revision.

After installing a firmware built from this change, open each modem's band page
and verify its reported masks. If Modem 2 still returns an unknown or mismatched
mask, retain the new query/reply diagnostic. That actual device response is
needed to distinguish a remaining transport issue from module firmware behavior;
host tests cannot prove that the physical modem accepts a band lock or registers
with its carrier.
