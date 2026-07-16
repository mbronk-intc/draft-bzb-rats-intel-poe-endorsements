---
title: "A CoRIM Profile for Intel Platform Ownership Endorsements (POE)"
abbrev: "Intel POE CoRIM Profile"
category: info
ipr: trust200902
docname: draft-bzb-rats-intel-poe-endorsements-latest
submissiontype: independent
number:
date:
v: 3
area: "Security"
workgroup: "Remote ATtestation ProcedureS"
pi:
  toc: yes
  sortrefs: yes
  symrefs: yes
  strict: yes
  comments: no
keyword:
 - attestation
 - corim
 - endorsement
 - ownership
 - sgx
 - tdx

venue:
  github: "mbronk-intc/draft-bzb-rats-intel-poe-endorsements"
  latest: "https://mbronk-intc.github.io/draft-bzb-rats-intel-poe-endorsements/draft-bzb-rats-intel-poe-endorsements.html"

author:
 -  ins: "M. Bronk"
    fullname: "Mateusz Bronk"
    organization: "Intel Corporation"
    email: "mateusz.bronk@intel.com"
 -  ins: "P. Zmijewski"
    fullname: "Piotr Zmijewski"
    organization: "Intel Corporation"
    email: "piotr.zmijewski@intel.com"
 -  ins: "J. Beaney"
    fullname: "James D. Beaney"
    organization: "Intel Corporation"
    email: "james.d.beaney@intel.com"

normative:
  CoRIM:
    title: "Concise Reference Integrity Manifest"
    target: https://datatracker.ietf.org/doc/html/draft-ietf-rats-corim-10
    date: 2026-03
    author:
      - name: H. Birkholz
      - name: T. Fossati
      - name: Y. Deshpande
      - name: N. Smith
      - name: W. Pan
    seriesinfo:
      Internet-Draft: draft-ietf-rats-corim-10
  # RFC2119 / RFC8174 (BCP 14) are pulled in as normative refs automatically by `{::boilerplate bcp14-tagged}`
  RFC9052:    # COSE structures and process
  RFC9053:    # COSE initial algorithms
  RFC9360:    # COSE X.509 (x5chain header parameter)
  RFC9562:    # UUID
  RFC8949:    # CBOR
  RFC5280:    # X.509
  RFC4151:    # tag: URI scheme
  RFC9679:    # COSE Key Thumbprint
  RFC9597:    # CWT Claims in COSE Headers
  RFC8392:    # CBOR Web Token (CWT)

informative:
  RATS-ARCH:
    title: "Remote ATtestation procedureS (RATS) Architecture"
    target: https://www.rfc-editor.org/rfc/rfc9334
    seriesinfo:
      RFC: 9334
  RFC7942:    # Implementation Status (running code)
  SGX-PCK:
    title: "Intel SGX PCK Certificate and Certificate Revocation List Profile Specification"
    target: https://api.trustedservices.intel.com/documents/Intel_SGX_PCK_Certificate_CRL_Spec-1.5.pdf
  POE-WHITEPAPER:
    title: "Platform Ownership Endorsements"
    target: https://www.intel.com/content/www/us/en/developer/articles/technical/software-security-guidance/technical-documentation/platform-ownership-endorsements.html
  INTEL-PROFILE:
    title: "Intel Profile for Remote Attestation"
    target: https://datatracker.ietf.org/doc/html/draft-cds-rats-intel-corim-profile-07
    date: 2026-05
    author:
      - name: J. Beaney
      - name: F. Chinchilla
      - name: Y. Deshpande
      - name: V. Scarlata
      - name: N. Smith
    seriesinfo:
      Internet-Draft: draft-cds-rats-intel-corim-profile-07


--- abstract

A Platform Ownership Endorsement (POE) is a signed statement that a
specific Intel confidential-computing platform instance, identified by
its Platform Instance Identity (PIID), belongs to a named owner. POEs
let a Verifier bind the attested hardware identity from an Intel SGX
or TDX platform to an operational owner (e.g., a Cloud Service Provider)
during appraisal, giving a Relying Party a trustworthy owner identity --
without trusting the attestation service or any in-band claim from the
platform itself.

This document defines POE as a profile of the IETF Concise Reference
Integrity Manifest (CoRIM) data model.

--- middle

# Introduction

Remote attestation Evidence produced by an Intel SGX or TDX platform
carries cryptographic identifiers (e.g., the Platform Provisioning ID
or the per-instance PIID) but does not, by itself, identify the
operational owner of the platform. In practice, Relying Parties often
need to answer the question "is this attested platform operated by the
Cloud Service Provider that claims to host my workload?" -- a question
that the attestation pipeline alone cannot answer.

A Platform Ownership Endorsement (POE) is a signed Endorsement (in
the sense of {{RATS-ARCH}}), issued out of band of the attestation
flow, that binds a specific platform instance (named by its PIID) to a
named owner. The Verifier (the Attestation Verifier in
{{POE-WHITEPAPER}}) consumes a POE alongside Evidence: when the bound
PIID matches the PIID in Evidence, the owner-identity claim is added
to the Verifier's Appraisal Claims Set.

This document specifies how POEs are encoded as a profile of the CoRIM
data model {{CoRIM}}. The profile pins a single
`conditional-endorsement-triple-record` per CoMID whose condition
matches the Attester's PIID and whose endorsement carries the owner
identity.

Background, threat model, and operational context for POE are
described in {{POE-WHITEPAPER}}.

## Scope: POE-specific, not an Intel umbrella profile {#why-poe-specific}

This profile covers POEs only. POEs are signed by platform owners,
CSPs, or fleet managers -- not by Intel -- and their trust anchors,
appraisal policies, and revocation channels are disjoint from those
of Intel-signed reference-value endorsements for the platform TCB
(e.g. TCB Info, TD Identity), which are likely to be carried under a single
(separate), Intel-issued CoRIM profile ({{INTEL-PROFILE}}). Partitioning by trust domain lets a
Verifier key appraisal off `/ profile / 3` directly. Future
POE-issuer-signed claim kinds remain in-scope under this same URI,
distinguished by `environment.class.class-id`.

## Profile shape at a glance

A POE CoRIM differs from base CoRIM {{CoRIM}} in three ways:

1. POE binds an *owner identity* to a platform, not measurements of
   firmware components; the conditional-endorsement-triple form is
   used rather than reference-triples.
2. Exactly one CoMID per CoRIM, and exactly one (condition,
   endorsement) pair per CoMID ({{single-record}}); multiple owner
   bindings are carried as separate CoRIMs.
3. PIID is carried as a profile-private extension claim inside the
   condition of the conditional-endorsement triple ({{conditions}}),
   not as a subject-side identity in the base CoRIM `environment`
   map's `instance` field ({{CoRIM}}). In a POE the platform identity
   functions as a *predicate*: the owner endorsement applies precisely
   when the Attester's Evidence presents the bound PIID.

# Conventions and Definitions

{::boilerplate bcp14-tagged}

Familiarity with the CoRIM data model {{CoRIM}} and the RATS
architecture {{RATS-ARCH}} is assumed.

The following terms are used throughout this document:

PIID:
: Platform Instance Identity -- a per-instance identifier carried in
  Intel SGX and TDX attestation Evidence. The identifier is a byte
  string of 16 or 32 bytes.

Owner:
: The operational entity that controls the platform identified by a
  given PIID (the Platform Owner in {{POE-WHITEPAPER}}). The Owner is
  named in the endorsement; it MAY differ from the entity that signs
  the enclosing CoRIM (the Issuer).

Issuer:
: The party that signs the CoRIM (termed the Platform Endorser in
  {{POE-WHITEPAPER}}). The Issuer vouches for the (PIID, Owner)
  binding by signing it.

# Profile Overview

A POE CoRIM is a COSE_Sign1 envelope {{RFC9052}} whose payload is a
CoRIM map. The CoRIM carries exactly one CoMID containing exactly one
`conditional-endorsement-triple-record`. The triple has:

- a `conditions` clause naming the target environment class (an Intel
  platform) and the PIID the endorsement is bound to; and
- an `endorsements - additions` clause carrying the Owner identity
  claim.

A skeleton (CBOR diagnostic notation) is shown in {{fig-skeleton}}.

~~~ cbor-diag
/ corim-map / {
  / id           / 0 : ...,            ; per-instance identifier
  / tags         / 1 : [ << concise-mid-tag >> ],
  / profile      / 3 : "tag:intel.com,2026:tee.poe#1.0",
  / rim-validity / 4 : { ... }         ; endorsement validity window
}

/ concise-mid-tag / {
  / tag-identity / 1 : { ... },
  / triples      / 4 : {
    / conditional-endorsement-triples / 10 : [
      [
        / conditions               / [ ... ],
        / endorsements - additions / [ ... ]
      ]
    ]
  }
}
~~~
{: #fig-skeleton title="POE CoRIM/CoMID skeleton"}

## Conformance constraints {#conformance}

This profile fully defines the structure of a POE CoRIM, and adopts an
asymmetric conformance model: a producer emits only what this profile
defines, while a Verifier tolerates unknown additions so that a future
`#1.<minor>` revision stays backward compatible (see {{profile-id}}).

### Producer requirements {#conformance-producer}

A producer conforming to this profile (version `#1.0`) SHOULD NOT emit
top-level CoRIM keys other than those this profile defines
({{corim-id}}, {{tags-cardinality}}, {{profile-id}}, {{rim-validity}},
and the optional base fields below), and MUST NOT:

- populate the COSE `crit` header parameter ({{RFC9052}}, Section 3.1);
- declare a `/ profile / 3` value other than the one defined by this
  specification, nor rely on any profile mechanism that imposes
  "must-understand" semantics on additional fields;
- place foreign tags in `/ tags / 1` (CoSWIDs, CoTLs, non-POE CoMIDs)
  or non-POE extension keys in the CoMID `triples`; or
- emit any field this profile marks "MUST NOT be present": the
  CoMID-level `/ entities / 5`, `tag-version`, the `environment.class`
  `vendor`/`model`/`instance`/`group` fields, and
  `measurement-map.authorized-by` (see the relevant sections).

Issuers needing additional semantics MUST publish their own profile
under their own namespace.

### Verifier requirements {#conformance-verifier}

A Verifier conforming to this profile MUST ignore any field it does not
recognise -- including the producer-prohibited fields above -- EXCEPT
that it MUST reject a CoRIM carrying:

- a non-empty COSE `crit` parameter (it cannot ignore parameters the
  producer has flagged critical);
- a `/ profile / 3` mismatch;
- a cardinality violation ({{tags-cardinality}}, {{single-record}}); or
- a `measurement-map.authorized-by` (issuer authorisation is conveyed
  by the COSE `x5chain` trust chain, not by a per-measurement key; see
  {{conditions}} and {{endorsements}}).

Thus `/ entities / 5`, `tag-version`, and the `environment.class`
fields are producer-side constraints only; a Verifier ignores them if
present. The **CoMID-level** `/ entities / 5` ({{CoRIM}}, Section 5.1.2) is
prohibited *for producers* because signer identity is already conveyed by
the COSE `x5chain` ({{RFC9360}}) leaf Subject and the `CWT-Claims` `iss`
claim ({{signer-metadata}}); a third source would only introduce drift.

Base-CoRIM optional fields permitted by this profile (all informational
and ignored by the Intel-provided Verifier):

- the CoRIM payload's `/ dependent-rims / 2` ({{CoRIM}}, Section
  4.1.3) -- not fetched or dereferenced; and
- the **CoRIM-level** `/ entities / 5` ({{CoRIM}}, Section 4.1.5) -- not
  interpreted.

## Signer metadata {#signer-metadata}

Signer metadata is carried in the COSE protected header using the
`CWT-Claims` header parameter (label 15, {{RFC9597}}). The parameter
value is a CBOR map of CWT claims ({{RFC8392}}) carried directly,
not wrapped in a byte string (unlike `corim-meta`). This profile
populates a single claim, the issuer (`iss`, CWT claim key 1), set to
a human-readable signer identity. The Intel generator emits only
`CWT-Claims` and no other CWT claim; per {{Section 4.2.2 of CoRIM}}
the `CWT-Claims` map MUST NOT carry claims that semantically overlap
CoRIM tag content.

CoRIM positions the legacy `corim-meta` header parameter (label 8) as
an alternative to `CWT-Claims` ({{Section 4.2.1 of CoRIM}}); the
`meta-group` grammar admits either parameter. This profile tightens
that to require `CWT-Claims`, with `corim-meta` permitted only as an
optional legacy addition. A producer MAY
additionally include `corim-meta` for interoperability with verifiers
that read only that parameter; when both are present, {{Section 4.2.1
of CoRIM}} requires their contents to be semantically identical -- the
`CWT-Claims` `iss` MUST equal `corim-meta`'s `signer-name`. The
Intel-provided Verifier reads signer metadata from `CWT-Claims` only
and ignores `corim-meta` if present.

The `iss` value SHOULD match the leaf signing certificate's Subject
Common Name ({{RFC5280}}, Section 4.1.2.6) so the human-readable
signer label cannot be decoupled from the cryptographically-bound
identity in `x5chain`. Signature lifetime is conveyed by the
`x5chain` ({{rim-validity}}); the CWT `nbf` (key 5) and `exp` (key 4)
claims ({{RFC8392}}) -- and, if `corim-meta` is present, its
`signature-validity` field -- MUST NOT be present.

## Refresh URI {#refresh-uri}

This profile defines one optional COSE protected-header parameter,
`tee.refresh-uri`, a forward-pointer to where a fresh POE for this
platform can be retrieved. It is carried through the protected header's
`cose-label => cose-value` extension point under the text label
`"tee.refresh-uri"` (a text label in the broader `tee.*` namespace,
deliberately not POE-specific, since manifest refresh is a generic
capability). The value is a `uri` (`#6.32(tstr)`, matching CoRIM's
`uri` type): a single absolute URI ({{!RFC3986}}) of at most 1024
bytes, whose scheme SHOULD be `https`. The parameter is OPTIONAL;
it is omitted when not applicable.

`tee.refresh-uri` is deliberately not the CoRIM payload's
`/ dependent-rims / 2` ({{CoRIM}}, Section 4.1.3): `dependent-rims`
names other CoRIMs a Verifier is expected to fetch and process during
appraisal, whereas `tee.refresh-uri` imposes no appraisal-time fetch
obligation -- it is an out-of-band hint for obtaining a later POE.

## CoRIM-level fields

### Identifier {#corim-id}

The CoRIM `id` field (key 0, `corim-id-type-choice`) is per-instance:
each (PIID, owner) change and each validity-window refresh produces a
distinct CoRIM, hence a distinct `id`. Issuers SHOULD encode `id` as
a UUIDv8 (`uuid-type`, untagged 16-byte `bstr`) derived as a
left-truncated SHA-384 over the CDE-encoded ({{RFC8949}}, Section
4.2) `tagged-unsigned-corim-map` payload with the `/ id / 0` entry
omitted; the leftmost 16 bytes become the UUID, with version/variant
bits set per {{RFC9562}}, Section 4. Other schemes (random UUIDv4/v7,
or a `tstr` issuer-internal naming convention) MAY be used provided
the per-issuer-namespace uniqueness requirement of {{CoRIM}}, Section
4.1.1, holds. Verifiers MUST treat `id` as informational and MUST NOT
re-derive it.

The CoMID `tag-id` ({{tag-identity}}) uses the same mechanism over a
narrower input (the CoMID's `/ triples / 4` only): `tag-id` is a
subject identifier and remains stable across re-issuance of the same
logical binding, whereas `id` perturbs on every byte that differs.
Generators that use both derivations MUST compute `tag-id` first,
embed the CoMID, then compute `id`.

### Tags cardinality {#tags-cardinality}

The CoRIM `tags` field (key 1) MUST contain exactly one entry under
this profile. That entry MUST be a Platform Ownership CoMID
(`#6.506(bstr .cbor concise-mid-tag-map)`) carrying the
`tee.platform-instance-id` extension key (`-101`, see
{{conditions}}). The base CoRIM schema permits one or more entries
({{CoRIM}}, Section 4.1.2); this profile tightens that to exactly
one. Verifiers MUST reject CoRIMs whose `tags` array is empty,
contains more than one entry, or contains an entry that is not a POE
CoMID. Issuers needing batch issuance MUST emit one CoRIM per
platform.

### Profile {#profile-id}

The CoRIM `profile` field (key 3, `profile-type-choice`) MUST be
present and MUST be the literal {{RFC4151}}-style tag URI:

~~~
tag:intel.com,2026:tee.poe#1.0
~~~

carried as an untagged `tstr` (the `uri` alternative of
`profile-type-choice`). The fragment carries a `#<major>.<minor>`
version axis. A breaking change to this profile MUST bump `<major>`;
a purely additive change that an unaware Verifier can safely ignore
MAY bump `<minor>`. Per {{CoRIM}}, Section 4.1.4, any change other
than such a `<minor>` bump constitutes a new profile and MUST be
assigned a new identifier.

Verifiers MUST reject the CoRIM if `profile` is absent, is not the
literal byte-equal string above on the `<major>` axis (current
`<major>` is `1`), or is encoded as any other type (e.g. an `https:`
URI, or an OID via `tagged-oid-type`). On a recognised `<major>`
with any `<minor>` -- including one higher than the Verifier's
built-in maximum -- the Verifier MUST accept the CoRIM and ignore
any top-level CoRIM keys it does not recognise, subject to the
"MUST NOT be present" restrictions in this profile.

### Validity {#rim-validity}

The CoRIM `rim-validity` field (key 4, `validity-map`) is REQUIRED
under this profile, with both `not-before` (key 0) and `not-after`
(key 1) populated as `#6.1` epoch-based numeric date-time values
({{CoRIM}}, Section 7.3; {{RFC8949}}, Section 3.4.2). A bounded validity window
provides the only standing time-based ceiling on a stale endorsement
in the absence of an in-band revocation channel; see
{{security-considerations}}.

This profile sets no normative upper bound on `not-after - not-before`.
Issuers SHOULD keep windows short to bound staleness, and are recommended
to bind refresh to an existing platform lifecycle event -- for
example, alongside Intel TCB Recovery events, so the POE and the PCK
certificate ({{SGX-PCK}}) stay in lock-step. The Intel generator's
default lifetime is `P5Y`; issuers with a scheduled re-issuance
pipeline SHOULD override it to match their cadence.

`rim-validity` is the semantic lifetime of the (PIID, owner) binding
and is independent of the COSE signing-chain validity. An issuer MAY
assert a multi-year `rim-validity` signed by a shorter-lived chain,
expecting to refresh the unprotected `x5chain` (re-certify the same
signing key) without re-signing the endorsement. The Verifier MUST
intersect `rim-validity` with the `max(cert.notBefore)`..`min(cert.notAfter)`
window across the `x5chain` and MUST reject the CoRIM if the
intersection is empty or if the caller-supplied verification
timestamp falls outside it.

# POE CoMID Encoding

## Tag Identity {#tag-identity}

The CoMID `tag-identity` (key 1) carries exactly one populated field
under this profile:

- `tag-id` (key 0): identifies the (platform, owner) binding. Issuers
  SHOULD encode `tag-id` by the same UUIDv8 / left-truncated SHA-384 /
  CDE mechanism as `corim-id` ({{corim-id}}), computed over this
  CoMID's `/ triples / 4` map. The derivation is deterministic for a
  given `triples` content, so a validity-window refresh (since
  `rim-validity` lives at the CoRIM level) yields the same `tag-id`,
  whereas a change to the bound PIID or owner name yields a new tag.
  Other schemes (random UUIDv4/v7, or a `tstr` issuer-internal naming
  convention) MAY be used provided uniqueness per {{CoRIM}}, Section
  5.1.1, holds. Verifiers MUST treat `tag-id` as informational and
  MUST NOT validate the derivation.

The `tag-version` field (key 1) MUST NOT be present. The meaningful
re-issuance axis is already captured by the `tag-id` derivation: a
change in PIID or owner name yields a new `tag-id`. A per-instance
revision counter adds no appraisal value and would require Issuers
to track per-`(PIID, owner)` monotonic state. Verifiers MUST ignore
`tag-version` if present.

## Single-record cardinality {#single-record}

The CoRIM/CoMID base schema ({{CoRIM}}, Section 5.1.4) allows
one-or-more `conditional-endorsement-triple-record` entries in
`/ conditional-endorsement-triples / 10`. This profile tightens that
to **exactly one** record per CoMID. Each binding then has its own
`tag-id`, validity window, and revocation lifecycle. Multiple
bindings -- different platforms, different owners, or alternative
conditions on the same platform -- MUST be carried as separate
CoRIMs (this profile pins `/ tags / 1` to exactly one CoMID; see
{{tags-cardinality}}).

Generators MUST emit exactly one record per CoMID; Verifiers MUST
reject a CoMID carrying zero or more-than-one record under this
profile.

## Conditions clause {#conditions}

The condition is a `stateful-environment-record` whose
`environment-map` identifies the PIID-bearing environment in Evidence
and whose `measurement-values-map` carries the PIID value to match.

~~~ cbor-diag
/ stateful-environment-record / [
  / environment-map / {
    / class / 0 : {
      / class-id / 0 : 111(h'6086480186F84D010D020601')
                                      ; 2.16.840.1.113741.1.13.2.6.1
                                      ; Intel PIID environment OID
    }
  },
  / claims-list / [
    / measurement-map / {
      / mkey / 0 : "tee.poe.platform-binding",
      / mval / 1 : {
        / tee.platform-instance-id /
        -101 : h'...'                 ; PIID, 16 B or 32 B
      }
    }
  ]
]
~~~
{: title="POE conditions clause"}

`environment.class.class-id` (key 0) MUST be the OID identifying the
Intel PIID environment, `2.16.840.1.113741.1.13.2.6.1`, encoded as
`tagged-oid-type` (CBOR tag 111). This OID matches the corresponding
PIID environment tag in the Intel SGX platform certificate {{SGX-PCK}}
and is the binding point between the certificate-side and CoMID-side
representations of the same identifier.

`environment.class.vendor` (key 1) MUST NOT be present. The
`class-id` OID is identity-bearing on its own; `vendor = "Intel"`
would be a redundant constant.

`environment.class.model` (key 2) MUST NOT be present. The `class-id`
OID uniquely identifies the PIID-bearing environment for this
profile, and the platform model is determined by the PIID itself --
a per-instance property rather than a class attribute.

`measurement-map.authorized-by` MUST NOT be present. Issuer
authorisation is conveyed by the COSE `x5chain` trust chain, not by a
per-measurement key. A Verifier MUST reject a CoRIM in which
`authorized-by` is present.

`measurement-map.mkey` (key 0) is RECOMMENDED. When present, it
SHOULD be the `tstr` value `"tee.poe.platform-binding"` -- a
diagnostic aid that keeps CBOR-diagnostic dumps self-describing.
Appraisal MUST NOT depend on `mkey`; Verifiers MUST accept the field
absent, present with this value, or present with any other `tstr`,
and MUST treat the bound PIID as the matching key.

The PIID itself is carried in `measurement-values-map` under the
profile-private extension key `-101` (registered name
`tee.platform-instance-id`). The value is a CBOR byte
string of length 16 or 32.
Generators MUST preserve the caller-supplied length verbatim.
Verifiers MUST compare the Evidence PIID against the bound value
verbatim over the full length; a length mismatch is a non-match.
Lengths other than 16 or 32 MUST be rejected.

Per {{CoRIM}}, Section 5.2.1, negative integer keys under
`measurement-values-map` are profile-private; this profile's
allocations are listed in {{ext-claims}}.

## Endorsements clause {#endorsements}

The endorsement is an `endorsed-triple-record` whose
`measurement-values-map` carries the Owner identity claim.

~~~ cbor-diag
/ endorsed-triple-record / [
  / environment-map / {
    / class / 0 : {
      / class-id / 0 : 111(h'6086480186F84D010D020C01')
                                     ; 2.16.840.1.113741.1.13.2.12.1
                                     ; Intel Owner-Endorsement OID
    }
  },
  / measurements / [
    / measurement-map / {
      / mkey / 0 : "tee.poe.ownership-claims",
      / mval / 1 : {
        / tee.owner-name / -401 : "csp.example"
      }
    }
  ]
]
~~~
{: title="POE endorsements clause"}

`environment.class.class-id` (key 0) MUST be the OID
`2.16.840.1.113741.1.13.2.12.1` -- the Intel Owner-Endorsement
environment class (version 1) -- encoded as `tagged-oid-type`
(CBOR tag 111). This OID is a sibling of the PIID environment OID
on the conditions side (`2.16.840.1.113741.1.13.2.6.1`).

`measurement-map.authorized-by` MUST NOT be present, for the same
reason as in {{conditions}}; a Verifier MUST likewise reject a CoRIM in
which it is present.

`measurement-map.mkey` (key 0) is RECOMMENDED. When present, it
SHOULD be the `tstr` value `"tee.poe.ownership-claims"`. As on the
conditions side, `mkey` is a diagnostic aid only; appraisal MUST NOT
depend on it.

`measurement-values-map` MUST carry exactly one entry: the Owner
name under the profile-private extension key `-401` (registered name
`tee.owner-name`). The value is a UTF-8 text string of length 1 to 1024
bytes.

The value SHOULD be a DNS name controlled by the Owner organisation
(e.g., `csp.example`, `aws.amazon.com`, `azure.microsoft.com`). DNS
names are globally unique and human-readable, which makes them the
preferred form. Other globally-unique forms -- a URI, an LEI, a
DUNS number, or a fully-qualified X.500 Distinguished Name -- MAY
be used where a DNS name is not available; locally-scoped or
free-form strings SHOULD NOT be used.

The Verifier MUST surface the decoded `tee.owner-name` to the caller
verbatim and SHOULD additionally surface the Issuer identity (COSE
`x5chain` leaf Subject and the `CWT-Claims` `iss` claim) so
callers can detect Issuer-vs-Owner mismatches. The appraisal
outcome MUST NOT depend on the value of `tee.owner-name`; interpretation
is a policy-layer concern.

## Extension claims {#ext-claims}

This profile allocates the following profile-private extension keys
under `$$measurement-values-map-extension`:

| Key  | Name                                 | Type                  | Used in                  |
| ---- | ------------------------------------ | --------------------- | ------------------------ |
| -101 | tee.platform-instance-id             | bstr (size 16 or 32)  | conditions clause        |
| -401 | tee.owner-name                       | tstr (size 1..1024)   | endorsements clause      |
{: title="POE measurement-values-map extension keys"}

Key `-101` corresponds to the `tee.platform-instance-id`
`measurement-values-map` extension defined by the Intel Profile for
Remote Attestation ({{INTEL-PROFILE}}, Section 8.3.6); it is shared
with the wider Intel `tee.*` namespace and is not exclusive to this
profile. Key `-401` is allocated here.

Unlike the Intel Profile ({{INTEL-PROFILE}}), which plugs each key
into the open `$$measurement-values-map-extension` socket, this
profile pins closed `measurement-values-map`s ({{cddl}}) so that
exactly one entry is permitted on each of the conditions and
endorsements sides.

Per {{CoRIM}}, Section 5.2.1, negative integer keys are reserved for
per-profile private use and require no IANA action. Keys allocated
here MUST NOT be used by generators or interpreted by Verifiers in
the absence of the POE profile identifier in the enclosing CoRIM
`/ profile / 3` field.

# Complete Example

A complete CBOR-diagnostic example of a POE CoRIM is shown in
{{fig-example}}. Values shown as `h'...'` are abbreviated for
readability.

~~~ cbor-diag
18([                                  ; COSE_Sign1
  << {                                ; protected header
    / alg / 1          : -35,         ; ES384
    / content-type / 3 : "application/rim+cbor",
    / kid / 4          : h'...',      ; SHA-384 COSE Key Thumbprint
    / CWT-Claims / 15  : {
      / iss / 1 : "csp.example"
    },
    / tee.refresh-uri /
      "tee.refresh-uri" :
      32("https://poe.example.com/corims/{PIID}.cbor")
  } >>,
  {                                   ; unprotected header
    / x5chain / 33 : [ h'...', h'...' ]
  },
  << 501( {                           ; payload: tagged corim-map
    / id           / 0 : h'...',      ; 16-byte UUIDv8 (untagged)
    / tags         / 1 : [
      506( <<                         ; concise-mid-tag
        {
          / tag-identity / 1 : {
            / tag-id / 0 : h'...'     ; 16-byte UUIDv8 (untagged)
          },
          / triples / 4 : {
            / conditional-endorsement-triples / 10 : [
              [
                / conditions / [
                  [
                    / environment-map / {
                      / class / 0 : {
                        / class-id / 0 :
                          111(h'6086480186F84D010D020601')
                          ; 2.16.840.1.113741.1.13.2.6.1 (PIID env)
                      }
                    },
                    / claims-list / [
                      / measurement-map / {
                        / mkey / 0 : "tee.poe.platform-binding",
                        / mval / 1 : {
                          / -101 / : h'...' ; PIID, 16 or 32 bytes
                        }
                      }
                    ]
                  ]
                ],
                / endorsements - additions / [
                  [
                    / environment-map / {
                      / class / 0 : {
                        / class-id / 0 :
                          111(h'6086480186F84D010D020C01')
                          ; 2.16.840.1.113741.1.13.2.12.1
                          ; (Owner-Endorsement env)
                      }
                    },
                    / measurements / [
                      / measurement-map / {
                        / mkey / 0 : "tee.poe.ownership-claims",
                        / mval / 1 : {
                          / -401 / : "csp.example"
                        }
                      }
                    ]
                  ]
                ]
              ]
            ]
          }
        }
      >> )
    ],
    / profile      / 3 : "tag:intel.com,2026:tee.poe#1.0",
    / rim-validity / 4 : {
      / not-before / 0 : 1(1780358400),  ; 2026-06-02T00:00:00Z
      / not-after  / 1 : 1(1938124800)   ; 2031-06-02T00:00:00Z
    }
  } ) >>,
  h'...'                              ; signature
])
~~~
{: #fig-example title="Complete POE CoRIM example (CBOR diagnostic)"}

# Implementation Status

This section records implementations of the profile defined by this
specification, in the spirit of {{RFC7942}}.


- Intel provides open-source tooling for the POE flow at
  [https://github.com/intel/confidential-computing.tee.dcap.poe](https://github.com/intel/confidential-computing.tee.dcap.poe),
  distributed under the BSD-3-Clause license:

  - The Intel(R) POE Generator (`poe-gen-tool`) extracts the Platform
    Instance Identity (PIID) from a Platform Manifest, PCK certificate,
    or SGX/TDX Quote, and builds and signs a POE CoRIM as specified in
    this document.
  - The Intel(R) POE Evaluator (`poe-eval-tool`) parses a POE CoRIM,
    matches its bound PIID against attestation Evidence, and surfaces the
    endorsed owner identity to the caller.

  Both tools track the `tag:intel.com,2026:tee.poe#1.0` profile
  defined here.

{::comment}
  AUTHOR NOTE:
  At the time of writing, the public open-source POE tooling
  (poe-gen-tool / poe-eval-tool) at the URL below is in the process of
  being released. The generate/sign and evaluate capabilities described
  here are present-tense in the text on the assumption they are public
  by the time this draft is posted; confirm the repository reflects them
  before relying on this section externally.
{:/comment}

# Security Considerations

## Issuer trust

A POE is only as trustworthy as the COSE_Sign1 signer. Relying
Parties MUST establish a trust anchor for the Issuer's signing
certificate chain out of band; this profile does not define an Issuer
trust hierarchy. Operational mechanisms for distributing Issuer
trust anchors are deployment-specific.

## Issuer is not necessarily Owner

This profile decouples the Issuer (who signs the CoRIM) from the
Owner (whose identity is endorsed), so that a Cloud Service Provider
or a delegated provisioning service can act as Issuer on the Owner's
behalf. Relying Parties whose policy requires the Issuer and Owner
to match (or to satisfy any other relationship) MUST enforce that
relationship at the policy layer using the Issuer identity surfaced
by the Verifier (see {{conditions}}) and the `tee.owner-name` claim.

## Revocation

This profile defines no in-band revocation mechanism for individual
POEs. Issuers MUST bound POE validity windows for their deployment
(see {{rim-validity}}), and SHOULD refresh a POE before its window
elapses; Intel TCB Recovery is a natural refresh trigger on Intel
platforms, keeping the POE and PCK certificate in lock-step ({{SGX-PCK}}).

A change to the (PIID, Owner) binding requires a new POE,
yielding a new `tag-id` (see {{tag-identity}}); on an ownership change
an SGX Factory Reset by the platform operator is also recommended, as the
resulting new PIID naturally orphans every POE bound to the prior one
({{POE-WHITEPAPER}}).

Standard COSE signing-chain revocation (CRL, OCSP) applies to the
Issuer certificate chain. Issuers can also use their CA layout to scope
revocation -- e.g. dedicating an intermediate CA to a fleet, tenant,
or issuance batch so one revocation invalidates every POE issued
under it.

## PIID confidentiality

The PIID is a per-instance identifier that can be used to track a
platform across attestation flows. A POE makes the
PIID-Owner binding publicly visible to any party that receives the
CoRIM. Issuers that distribute POEs to untrusted parties SHOULD
consider whether this disclosure is acceptable in their threat model.

Note that an SGX Factory Reset establishes a new PIID
({{POE-WHITEPAPER}}), bounding that correlation.

# IANA Considerations {#iana}

This document requests no IANA action.

The profile identifier ({{profile-id}}) is an {{RFC4151}} tag URI
(`tag:intel.com,2026:tee.poe#1.0`); per RFC 4151, no registration is
required. The DNS authority `intel.com` is under the control of Intel
Corporation, and the year `2026` pins the allocation per RFC 4151,
Section 2.4.

The OIDs used in this profile are under Intel's private enterprise arc
(`2.16.840.1.113741`); their allocation is administered by Intel and
requires no IANA action:

- `2.16.840.1.113741.1.13.2.6.1` -- Intel PIID environment class,
  reused from {{SGX-PCK}}, used as `environment.class.class-id` in
  the conditions clause ({{conditions}}).
- `2.16.840.1.113741.1.13.2.12.1` -- Intel Owner-Endorsement
  environment class, version 1, used as `environment.class.class-id`
  in the endorsements clause ({{endorsements}}).

The negative integer keys allocated in {{ext-claims}}
(`-101 tee.platform-instance-id` and `-401 tee.owner-name`)
are profile-private per {{CoRIM}}, Section 5.2.1, and require no
IANA action. Key `-101` is shared with the broader Intel `tee.*`
namespace; the authoritative registry of record for cross-profile
Intel allocations under that namespace is maintained outside this
document, and a future revision may relocate the normative-of-record
entry for `-101` accordingly without affecting IANA.

--- back

# CDDL {#cddl}

This appendix gives a single self-contained CDDL fragment for the
POE profile. It is a narrowing of base CoRIM {{CoRIM}}: every
production defined here is a stricter form of the corresponding base
production, expressing the constraints stated normatively in
{{single-record}}, {{tag-identity}}, {{conditions}},
{{endorsements}}, and {{ext-claims}}.

To validate a candidate POE CoRIM, concatenate the base CoRIM CDDL
(`corim.cddl` from {{CoRIM}}, Appendix A) with the fragment below
and feed the combined grammar to a CDDL tool. The top-level rule is
`poe-signed-corim`.

The following constraints cannot be expressed in CDDL and remain
normative in prose:

- the literal OID byte strings pinned in {{conditions}} and
  {{endorsements}} (CDDL types over `bstr` cannot pin a specific
  byte sequence portably across tools);
- the UUIDv8/SHA-384/CDE derivation rule for `tag-id` ({{tag-identity}})
  and `corim-id` ({{corim-id}});
- the intersection of `rim-validity` with the COSE `x5chain`
  validity ({{rim-validity}});
- the `mkey` string recommendations of `"tee.poe.platform-binding"`
  and `"tee.poe.ownership-claims"` ({{conditions}}, {{endorsements}});
- the empty-`crit` requirement on the COSE protected header
  ({{conformance}}).

~~~ cddl
{::include cddl/exports/intel-poe-profile.cddl}
~~~
{: title="POE profile CDDL (self-contained)"}

# Acknowledgments
{:numbered="false"}

The authors wish to thank Vincent R. Scarlata and Francisco J. Chinchilla for their valuable contributions.
