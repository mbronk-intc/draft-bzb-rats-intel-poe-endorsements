# Based on https://github.com/devcontainers/templates/tree/main/src/ruby, with further customizations for IETF I-D
FROM mcr.microsoft.com/devcontainers/ruby:1-3.3-bookworm
# The base image ships a Yarn apt repo whose signing key has expired, which makes
# `apt-get update` fail (NO_PUBKEY 62D54FD4003F6525 -> exit 100). Yarn isn't used
# by this IETF I-D toolchain, so drop that repo before updating.
RUN rm -f /etc/apt/sources.list.d/yarn.list \
    && apt-get update \
    && apt-get install -y python3 python3-pip python3-venv \
       jq libxml2-utils
# bookworm ships Python 3.11 (>=3.10 required by i-d-template's doc/SETUP.md).
# jq + libxml2-utils (xmllint) are required by the i-d-template Makefile
# (per its doc/SETUP.md Ubuntu prerequisites); not present in the base image.
RUN pip3 install --break-system-packages --upgrade xml2rfc iddiff svgcheck intervaltree pip wheel setuptools #just to get everything updated container-build-time
# --break-system-packages: bookworm marks the system Python as externally-managed
# (PEP 668); this image is disposable so a global install is intentional.
# I-D toolchain gems + CoRIM/CDDL tooling:
#   cddl      -> `cddl` validator/generator (this draft is a CoRIM profile with a normative CDDL appendix)
#   cbor-diag -> cbor2diag.rb / diag2cbor.rb / cbor2pretty.rb (the draft carries several `cbor-diag` examples)
RUN mkdir -p ~/.bundle/cache && chmod +t -R ~/.bundle/cache && gem install kdwatch kramdown-mermaid cddl cbor-diag

#Install mermaid-ascii
# Latest 
RUN curl -s https://api.github.com/repos/AlexanderGrooff/mermaid-ascii/releases/latest \
    | grep "browser_download_url.*mermaid-ascii" | grep "$(uname)_$(uname -m)" | cut -d: -f2,3 | tr -d \" \
    | wget -q -i- -O- | tar -xvz -f- -C /usr/bin -- mermaid-ascii
