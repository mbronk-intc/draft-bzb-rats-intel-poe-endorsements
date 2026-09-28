#!/usr/bin/env bash
#
# dump-diag.sh -- dump the CBOR diagnostic notation (EDN) of a POE CoRIM.
#
# Unlike a generic `cbor2diag.rb`, this descends into the `bstr .cbor` embedding
# points that CoRIM/COSE use (the COSE_Sign1 protected header and payload, the
# tagged concise-mid-tag, and corim-meta) and renders each as an embedded-CBOR
# `<< ... >>` block -- the same notation the draft's Complete Example uses --
# instead of leaving them as opaque hex. Certificates and the signature are raw
# byte strings and are shown as `h'...'`.
#
# The embedding is detected structurally: a byte string is expanded only when it
# decodes as CBOR AND consumes every one of its bytes AND yields a map, array, or
# tag. DER certificates and the raw signature fail that test and stay as hex, so
# no profile-specific key list is baked in here.
#
# Usage:
#   scripts/dump-diag.sh FILE.cbor            # print EDN to stdout
#   scripts/dump-diag.sh FILE.cbor -o OUT     # write EDN to OUT
#   scripts/dump-diag.sh --raw FILE.cbor      # opaque bstr (delegates to cbor2diag.rb)
#   scripts/dump-diag.sh -h
#
# Env:
#   DIAG_PY   python with cbor2 (default: the devcontainer cddlvenv python, else python3)
#
set -euo pipefail

DIAG_PY="${DIAG_PY:-$(command -v "$HOME/.local/share/poe-tools/cddlvenv/bin/python" 2>/dev/null || command -v python3)}"

raw=0 out="" file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    --raw)     raw=1; shift ;;
    -o)        out="$2"; shift 2 ;;
    -*)        echo "usage: $0 [--raw] [-o OUT] FILE.cbor" >&2; exit 2 ;;
    *)         file="$1"; shift ;;
  esac
done
[[ -n "$file" ]] || { echo "usage: $0 [--raw] [-o OUT] FILE.cbor" >&2; exit 2; }
[[ -f "$file" ]] || { echo "error: no such file: $file" >&2; exit 2; }

if [[ "$raw" -eq 1 ]]; then
  if [[ -n "$out" ]]; then cbor2diag.rb "$file" > "$out"; else cbor2diag.rb "$file"; fi
  exit 0
fi

"$DIAG_PY" - "$file" "$out" <<'PY'
import io, sys, datetime
from collections.abc import Mapping
import cbor2

path, out = sys.argv[1], sys.argv[2]

def embedded_cbor(b):
    """Return the decoded value if b is a byte string that is exactly one CBOR
    item spanning all its bytes and is a container/tag; else None."""
    if not isinstance(b, (bytes, bytearray)):
        return None
    buf = io.BytesIO(b)
    try:
        val = cbor2.load(buf)
    except Exception:
        return None
    if buf.tell() != len(b):
        return None
    if isinstance(val, (Mapping, list, tuple, cbor2.CBORTag)):
        return val
    return None

def edn(obj, indent):
    pad, ipad = "  " * indent, "  " * (indent + 1)
    if isinstance(obj, cbor2.CBORTag):
        return "%d(%s)" % (obj.tag, edn(obj.value, indent))
    # cbor2 decodes tag 1 (epoch time) into a datetime; render it back as 1(epoch)
    if isinstance(obj, datetime.datetime):
        ts = obj.timestamp()
        return "1(%s)" % (int(ts) if ts.is_integer() else ts)
    if isinstance(obj, Mapping):
        if not obj:
            return "{}"
        items = ",\n".join("%s%s: %s" % (ipad, edn(k, indent + 1), edn(v, indent + 1))
                           for k, v in obj.items())
        return "{\n%s\n%s}" % (items, pad)
    if isinstance(obj, (list, tuple)):
        if not obj:
            return "[]"
        items = ",\n".join("%s%s" % (ipad, edn(v, indent + 1)) for v in obj)
        return "[\n%s\n%s]" % (items, pad)
    if isinstance(obj, (bytes, bytearray)):
        inner = embedded_cbor(obj)
        if inner is not None:
            return "<< %s >>" % edn(inner, indent)
        return "h'%s'" % obj.hex().upper()
    if isinstance(obj, str):
        return '"%s"' % obj.replace('"', '\\"')
    if isinstance(obj, bool):
        return "true" if obj else "false"
    if obj is None:
        return "null"
    return str(obj)

text = edn(cbor2.load(open(path, "rb")), 0) + "\n"
if out:
    open(out, "w").write(text)
else:
    sys.stdout.write(text)
PY
