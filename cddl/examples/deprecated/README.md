# Deprecated examples — prior-revision, not valid under the current draft

These samples were **conformant under draft revision -01** but are **rejected by
the current grammar** (the -02 revision in this tree). They are retained only as
a historical reference and as backward-compatibility regression material; they
are NOT part of the authoritative Engine 6 positive set in
`scripts/test-cddl.sh`, and a current-`#1.0` producer MUST NOT emit them.

## `poe-corim-1.0-unsigned.bare-profile`

The CoRIM `profile` field (key 3) is carried as a **bare, untagged `tstr`**:

```
3: "tag:intel.com,2026:tee.poe#1.0",
```

Under -01 this was explicitly correct — §3.4.3 required the identifier
"carried as an untagged tstr (the uri alternative of profile-type-choice)", and
the -01 CDDL read `poe-profile-id = "tag:intel.com,2026:tee.poe#1.0"`.

The -02 revision tightens this to the tag-32 URI form base CoRIM's `uri` type
actually is:

```
3: 32("tag:intel.com,2026:tee.poe#1.0"),      ; #6.32(tstr)
```

i.e. `poe-profile-id = #6.32("tag:intel.com,2026:tee.poe#1.0")`. A bare `tstr`
is therefore no longer a valid profile identifier — this is exactly the shape
the `poe-negative-untagged-profile.cbor` fixture exists to reject. The canonical,
current-form counterpart is `../poe-corim-1.0-unsigned.cbor` (profile wrapped in
`#6.32`).

Only the unsigned payload is kept here; there is no matching signed envelope
(re-signing requires the private key, which is not in this repo).
