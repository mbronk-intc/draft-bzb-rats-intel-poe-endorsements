#!/usr/bin/env python3
"""Generate the POE conformance fixtures used by `make test`.

Deterministic, dependency-light (needs only `cbor2`). Produces three CBOR files
under this directory:

  poe-golden.cbor            -- a minimal, base-correct signed POE CoRIM
                                (COSE_Sign1 / #6.18). MUST be accepted by both the
                                base CoRIM decoder and this profile.
  poe-golden-fwdcompat.cbor  -- the golden CoRIM plus optional/forward-compatible
                                top-level keys (dependent-rims, CoRIM-level
                                entities, and an unknown future key). MUST still be
                                accepted -- exercises the profile's Postel's-law
                                verifier posture.
  poe-negative-bare.cbor     -- a deliberately malformed CoRIM whose measurement
                                side is a bare `measurement-map` instead of the
                                base-required `[+ measurement-map]` array. MUST be
                                rejected by the base decoder and this profile
                                (guards the guard).
  poe-golden-tstr-id.cbor    -- the golden CoRIM with `id`/`tag-id` carried as
                                `tstr` instead of a 16-byte UUID. MUST be accepted
                                (exercises `$corim-id-type-choice` = uuid / tstr).
  poe-golden-leaf-only.cbor  -- the golden CoRIM with a single-certificate
                                `x5chain` carried as a bare `bstr` (the
                                COSE_X509 single-cert form, RFC 9360). MUST be
                                accepted (exercises `x5chain = bstr / [ 2*bstr ]`).

The signature and key material are placeholders: these fixtures exercise the CBOR
*structure* only. Regenerate with `make fixtures` after any wire-shape change.
"""
import os
import cbor2

HERE = os.path.dirname(os.path.abspath(__file__))
PIID_ENV_OID = bytes.fromhex("6086480186F84D010D020601")   # 2.16.840.1.113741.1.13.2.6.1
OWNER_OID = bytes.fromhex("6086480186F84D010D020C01")      # 2.16.840.1.113741.1.13.2.12.1


def _tag(n, v):
    return cbor2.CBORTag(n, v)


def _comid(bare=False, tstr_id=False):
    piid_env = {0: {0: _tag(111, PIID_ENV_OID)}}
    owner_env = {0: {0: _tag(111, OWNER_OID)}}
    piid_meas = {0: "tee.poe.platform-binding", 1: {-101: bytes(16)}}
    owner_meas = {0: "tee.poe.ownership-claims", 1: {-401: "csp.example"}}
    if bare:                                  # F1 violation: bare map, no array
        cond = [[piid_env, piid_meas]]
        endo = [[owner_env, owner_meas]]
    else:                                     # base shape: [env, [+ measurement-map]]
        cond = [[piid_env, [piid_meas]]]
        endo = [[owner_env, [owner_meas]]]
    tag_id = "tag-id.example" if tstr_id else bytes(16)
    return {1: {0: tag_id}, 4: {10: [[cond, endo]]}}


def _signed_corim(bare=False, fwdcompat=False, tstr_id=False, single_cert=False):
    corim_map = {
        0: "corim-id.example" if tstr_id else bytes(16),
        1: [_tag(506, cbor2.dumps(_comid(bare, tstr_id)))],   # #6.506(bstr .cbor concise-mid-tag)
        3: "tag:intel.com,2026:tee.poe#1.0",
        4: {0: _tag(1, 1780358400), 1: _tag(1, 1938124800)},
    }
    if fwdcompat:
        corim_map[2] = [bytes(8)]                     # dependent-rims (optional)
        corim_map[5] = [{0: "example"}]               # CoRIM-level entities (optional)
        corim_map[99] = "unknown-future-key"          # forward-compat unknown key
    payload = cbor2.dumps(_tag(501, corim_map))
    protected = cbor2.dumps({1: -35, 3: "application/rim+cbor", 4: bytes(48),
                             15: {1: "csp.example"}})
    # x5chain (COSE_X509, RFC 9360): a single cert is a BARE bstr; two-or-more
    # use the array form. single_cert exercises the bare-bstr leaf-only shape.
    x5chain = bytes(64) if single_cert else [bytes(64), bytes(64)]
    unprotected = {33: x5chain}
    return cbor2.dumps(_tag(18, [protected, unprotected, payload, bytes(96)]))


def main():
    out = {
        "poe-golden.cbor": _signed_corim(),
        "poe-golden-fwdcompat.cbor": _signed_corim(fwdcompat=True),
        "poe-negative-bare.cbor": _signed_corim(bare=True),
        "poe-golden-tstr-id.cbor": _signed_corim(tstr_id=True),
        "poe-golden-leaf-only.cbor": _signed_corim(single_cert=True),
    }
    for name, data in out.items():
        with open(os.path.join(HERE, name), "wb") as fh:
            fh.write(data)
        print(f"wrote {name} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
