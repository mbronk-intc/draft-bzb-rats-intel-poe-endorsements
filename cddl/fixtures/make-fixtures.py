#!/usr/bin/env python3
"""Generate the POE conformance fixtures used by `make test`.

Deterministic, dependency-light (needs only `cbor2`). Produces the CBOR files
under this directory:

  poe-golden.cbor            -- a minimal, base-correct signed POE CoRIM
                                (COSE_Sign1 / #6.18). MUST be accepted by both the
                                base CoRIM decoder and this profile.
  poe-golden-fwdcompat.cbor  -- the golden CoRIM plus the optional top-level keys
                                (dependent-rims, CoRIM-level entities) that this
                                profile leaves as `any`. MUST still be accepted --
                                proves the profile's looseness composes with base.
                                The optional keys carry
                                *base-legal* values (a real corim-locator-map, a
                                real corim-entity-map incl. the mandatory `role`),
                                so this fixture is a genuine base CoRIM too.
  poe-golden-tstr-id.cbor    -- the golden CoRIM with `id`/`tag-id` carried as
                                `tstr` instead of a 16-byte UUID. MUST be accepted
                                (exercises `$corim-id-type-choice` = uuid / tstr).
  poe-golden-leaf-only.cbor  -- the golden CoRIM with a single-certificate
                                `x5chain` carried as a bare `bstr` (the
                                COSE_X509 single-cert form, RFC 9360). MUST be
                                accepted (exercises `x5chain = bstr / [ 2*bstr ]`).
  poe-golden-es384-legacy.cbor
                             -- the golden CoRIM signed with the legacy
                                curve-polymorphic ES384 (`alg` = -35) instead of
                                the preferred fully-specified ESP384 (`alg` = -51,
                                RFC 9864). MUST be accepted -- the profile admits
                                both P-384/SHA-384 code points; every other
                                fixture uses -51, this one pins the -35 arm.
  poe-golden-kid-unprotected.cbor
                             -- the golden CoRIM with `kid` (label 4) carried in
                                the UNPROTECTED header instead of the protected
                                one. MUST be accepted -- RFC 9052 (Section 3.1)
                                allows `kid` in either bucket and the profile
                                lists it as `? 4 => bstr` in both. Its extracted
                                payload is identical to golden, so this placement
                                is exercised only by the envelope-root
                                (`poe-signed-corim`) engine, not the payload
                                engines.

Negatives -- each MUST be rejected by base CoRIM, by this profile, or by both; a
fixture accepted by BOTH no longer exercises a defect. Which side catches it is
recorded per fixture below. One fixture per property; do not accumulate more for
the same defect.

  poe-negative-bare.cbor     -- measurement side is a bare `measurement-map`
                                instead of the base-required `[+ measurement-map]`
                                array (guards the guard).
  poe-negative-untagged-profile.cbor
                             -- `profile` (key 3) as an untagged `tstr`. Base's
                                `$profile-type-choice` admits only `uri`
                                (`#6.32(tstr)`) and `tagged-oid-type` (`#6.111`),
                                so an untagged tstr is not a profile identifier at
                                all. THE regression guard for that defect -- one is
                                enough; the positives already assert the correct
                                encoding.
  poe-negative-base-binds.cbor
                             -- `dependent-rims` (key 2) as `[bstr]` where base
                                requires `[+ corim-locator-map]`. This profile
                                types key 2 as `[+ any]` -- pinning the array
                                shape but not the element type -- so the bstr
                                element satisfies the profile and ONLY base can
                                reject it. This is the fixture that
                                proves the suite really composes with base: drop
                                the base root and this is what starts passing.

The signature and key material are placeholders: these fixtures exercise the CBOR
*structure* only. Regenerate with `make fixtures` after any wire-shape change.
"""
import os
import cbor2

HERE = os.path.dirname(os.path.abspath(__file__))
PIID_ENV_OID = bytes.fromhex("6086480186F84D010D020601")   # 2.16.840.1.113741.1.13.2.6.1
OWNER_OID = bytes.fromhex("6086480186F84D010D020C01")      # 2.16.840.1.113741.1.13.2.12.1
PROFILE_ID = "tag:intel.com,2026:tee.poe#1.0"


def _tag(n, v):
    return cbor2.CBORTag(n, v)


def _comid(bare=False, tstr_id=False):
    piid_env = {0: {0: _tag(111, PIID_ENV_OID)}}
    owner_env = {0: {0: _tag(111, OWNER_OID)}}
    piid_meas = {0: "tee.poe.platform-binding", 1: {-101: bytes(16)}}
    owner_meas = {0: "tee.poe.ownership-claims", 1: {-401: "csp.example"}}
    if bare:                                  # bare map where base needs [+ measurement-map]
        cond = [[piid_env, piid_meas]]
        endo = [[owner_env, owner_meas]]
    else:                                     # base shape: [env, [+ measurement-map]]
        cond = [[piid_env, [piid_meas]]]
        endo = [[owner_env, [owner_meas]]]
    tag_id = "tag-id.example" if tstr_id else bytes(16)
    return {1: {0: tag_id}, 4: {10: [[cond, endo]]}}


def _signed_corim(bare=False, fwdcompat=False, tstr_id=False, single_cert=False,
                  untagged_profile=False, base_illegal_locator=False, alg=-51,
                  kid_unprotected=False):
    corim_map = {
        0: "corim-id.example" if tstr_id else bytes(16),
        1: [_tag(506, cbor2.dumps(_comid(bare, tstr_id)))],   # #6.506(bstr .cbor concise-mid-tag)
        # profile: the `uri` arm of $profile-type-choice, i.e. #6.32(tstr).
        3: PROFILE_ID if untagged_profile else _tag(32, PROFILE_ID),
        4: {0: _tag(1, 1780358400), 1: _tag(1, 1938124800)},
    }
    if fwdcompat:
        # Base-legal optional keys: corim-locator-map (href is a `uri`) and
        # corim-entity-map (entity-name + the MANDATORY role).
        corim_map[2] = [{0: _tag(32, "https://example.com/dependent-rim")}]
        corim_map[5] = [{0: "example.entity", 2: [1]}]   # role 1 = manifest-creator
    if base_illegal_locator:          # not a corim-locator-map; only base sees it
        corim_map[2] = [bytes(8)]
    payload = cbor2.dumps(_tag(501, corim_map))
    # alg -51 = ESP384 (preferred), -35 = ES384 (legacy); both ECDSA/P-384/SHA-384.
    prot = {1: alg, 3: "application/rim+cbor"}
    if not kid_unprotected:
        prot[4] = bytes(48)          # kid: RFC 9679 thumbprint, protected bucket
    prot[15] = {1: "csp.example"}
    protected = cbor2.dumps(prot)
    # x5chain (COSE_X509, RFC 9360): a single cert is a BARE bstr; two-or-more
    # use the array form. single_cert exercises the bare-bstr leaf-only shape.
    x5chain = bytes(64) if single_cert else [bytes(64), bytes(64)]
    unprotected = {33: x5chain}
    if kid_unprotected:
        unprotected[4] = bytes(48)   # kid in the unprotected bucket (? 4 arm)
    return cbor2.dumps(_tag(18, [protected, unprotected, payload, bytes(96)]))


def main():
    out = {
        "poe-golden.cbor": _signed_corim(),
        "poe-golden-fwdcompat.cbor": _signed_corim(fwdcompat=True),
        "poe-golden-tstr-id.cbor": _signed_corim(tstr_id=True),
        "poe-golden-leaf-only.cbor": _signed_corim(single_cert=True),
        "poe-golden-es384-legacy.cbor": _signed_corim(alg=-35),
        "poe-golden-kid-unprotected.cbor": _signed_corim(kid_unprotected=True),
        "poe-negative-bare.cbor": _signed_corim(bare=True),
        "poe-negative-untagged-profile.cbor": _signed_corim(untagged_profile=True),
        "poe-negative-base-binds.cbor": _signed_corim(base_illegal_locator=True),
    }
    for name, data in out.items():
        with open(os.path.join(HERE, name), "wb") as fh:
            fh.write(data)
        print(f"wrote {name} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
