# POE CoRIM examples (Intel-tooling actuals)

Real, end-to-end POE CoRIMs emitted by the Intel POE tooling — genuine
`COSE_Sign1` envelopes with a real 2-certificate `x5chain` and a real
ECDSA/P-384 signature, paired with the standalone unsigned CoRIM that is each
envelope's payload. Unlike the synthetic fixtures under `cddl/fixtures/` (which
carry placeholder keys/signatures and exercise the grammar element-by-element),
these drive the profile's own `poe-signed-corim` envelope root and are the
**authoritative** conformance samples wired into `scripts/test-cddl.sh`
(Engine 6).

Every `.cbor` has a committed `.diag` (CBOR Extended Diagnostic Notation) beside
it; `scripts/dump-diag.sh` renders it, descending into `bstr .cbor` embeddings as
`<< ... >>` and leaving certificates/signatures as `h'...'`. The test suite
asserts each `.diag` round-trips byte-identically to its `.cbor`
(`diag2cbor.rb | cmp`). Regenerate the diags with `make examples`.

## Files

Each example is an `unsigned` payload plus the `signed` envelope built over it;
the unsigned file is byte-identical to element [2] of its signed envelope
(the suite checks this). Issuer (`iss`) is `[DEBUG] sample-owner.csp.example.com`
and the endorsed owner (`tee.owner-name`, key −401) is
`sample-owner.csp.example.com`.

| Pair | `kid` (COSE label 4) | Signing `alg` | Notes |
| --- | --- | --- | --- |
| `poe-corim-1.0-{unsigned,signed}` | protected header | ESP384 (−51, RFC 9864, preferred) | Canonical shape the generator emits. |
| `poe-corim-1.0-{unsigned,signed}-kid-unprot` | unprotected header | ES384 (−35, RFC 9053, legacy) | Same binding, exercising the other conformant `kid` bucket and the legacy alg code point. |

Both placements of `kid` are conformant (RFC 9052 §3.1 makes it a non-critical
hint that MAY sit in either bucket; the profile lists it optional in both maps,
required in exactly one). Both alg code points are accepted (ESP384 preferred,
ES384 legacy) — see the draft's *Signing algorithm* section. The two pairs
together prove the grammar admits either combination against real crypto.

## `deprecated/`

Samples that were conformant under an **earlier draft revision** but are rejected
by the current grammar. They are kept for reference and backward-compatibility
regression only — they are **not** valid `#1.0` under the current draft and are
not part of the Engine 6 positive set. See `deprecated/README.md`.
