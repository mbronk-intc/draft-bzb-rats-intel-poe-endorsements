#!/usr/bin/env bash
#
# provision-cddl-tools.sh -- install the POE CDDL conformance-test tooling into
# durable, per-user locations so `make test` / `make fuzz` work in the container.
#
# Installs (idempotently):
#   - corim-cli  : Microsoft's Rust CoRIM decoder (Azure/corim, draft-ietf-rats-
#                  corim-10), the AUTHORITATIVE base-conformance gate. Built from a
#                  pinned commit into ~/.local/bin.
#   - pycddl + cbor2 : a Rust-backed CDDL validator + CBOR codec, in a venv under
#                  ~/.local/share/poe-tools/cddlvenv, used for the payload check
#                  and for (re)generating fixtures.
# The Ruby `cddl` gem and cbor-diag are already provided by the base image.
#
# Safe to re-run; skips work that is already done. Never fatal to the container
# build -- prints a warning and continues if a network/toolchain step fails, so
# the grammar checks still work even if the instance-level test tools are absent.
#
set -uo pipefail

TOOLS_DIR="${TOOLS_DIR:-$HOME/.local/share/poe-tools}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
CORIM_REPO="${CORIM_REPO:-https://github.com/Azure/corim.git}"
CORIM_COMMIT="${CORIM_COMMIT:-d798092e4d4baf42d5f87b9d0130662c180b91e4}"  # draft-10; pinned
RUST_VERSION="${RUST_VERSION:-1.85.0}"

mkdir -p "$TOOLS_DIR" "$BIN_DIR"

# Ensure ~/.local/bin is on PATH for future shells.
if ! grep -qs 'HOME/.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi
export PATH="$BIN_DIR:$PATH"

# --- pycddl + cbor2 venv --------------------------------------------------------
if [[ ! -x "$TOOLS_DIR/cddlvenv/bin/python" ]]; then
  echo "[provision] creating pycddl venv..."
  python3 -m venv "$TOOLS_DIR/cddlvenv" \
    && "$TOOLS_DIR/cddlvenv/bin/pip" -q install --upgrade pip \
    && "$TOOLS_DIR/cddlvenv/bin/pip" -q install pycddl cbor2 \
    || echo "[provision] WARNING: pycddl/cbor2 install failed; payload check + 'make fixtures' will be unavailable."
else
  echo "[provision] pycddl venv already present."
fi

# --- corim-cli (Azure/corim) ----------------------------------------------------
if command -v corim-cli >/dev/null 2>&1; then
  echo "[provision] corim-cli already on PATH."
else
  echo "[provision] building corim-cli (Azure/corim @ ${CORIM_COMMIT:0:9})..."
  # Rust toolchain (minimal) if absent.
  if ! command -v cargo >/dev/null 2>&1; then
    if [[ -s "$HOME/.cargo/env" ]]; then
      # shellcheck disable=SC1091
      source "$HOME/.cargo/env"
    else
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --profile minimal --default-toolchain "$RUST_VERSION" \
        && source "$HOME/.cargo/env" \
        || { echo "[provision] WARNING: Rust install failed; corim-cli unavailable (grammar checks still work)."; exit 0; }
    fi
  fi
  src="$TOOLS_DIR/azure-corim"
  if [[ ! -d "$src/.git" ]]; then
    git clone -q "$CORIM_REPO" "$src" || { echo "[provision] WARNING: clone failed; corim-cli unavailable."; exit 0; }
  fi
  git -C "$src" fetch -q --depth 1 origin "$CORIM_COMMIT" 2>/dev/null || true
  git -C "$src" checkout -q "$CORIM_COMMIT" 2>/dev/null || true
  if (cd "$src" && cargo build -q -p corim-cli --release); then
    cp "$src/target/release/corim-cli" "$BIN_DIR/corim-cli"
    echo "$CORIM_COMMIT" > "$TOOLS_DIR/azure-corim.commit"
    echo "[provision] corim-cli installed to $BIN_DIR/corim-cli"
  else
    echo "[provision] WARNING: corim-cli build failed; the authoritative gate will be unavailable."
  fi
fi

echo "[provision] done."
