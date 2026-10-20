# The test image: a pinned Neovim nightly and everything tests/unit and tests/regress need, so both tiers run the
# same way on any machine and in CI. Build from the repo root (the context is the checkout, see /.dockerignore):
#   mise run test:image:build      or   podman build -f tests/image/Dockerfile -t nvim-config-test .
# Run with `mise run test:image [unit | suite [suite.sh args]]`. Decisions: docs/test-image-decisions.md.
#
# The suite's tools, plugins and parsers come from the suite's own install path, `suite.sh --refresh-only`
# (refresh.lua), into tests/regress/data/ under /work, the same path they are used from at run time: the installs
# keep absolute paths. Stages:
#   runtime  what a test run needs: nvim's and the checks' system tools, mise, rustup, the tree-sitter CLI, a C compiler
#   nvim     builds the pinned nightly
#   needs    the @needs of every check, alone, so adding a check with no new tool keeps the tools layer
#   tools    the suite's mise and rustup installs, keyed on the catalog and the needs only
#   plugins  plugins at the lockfile (vim.pack), the tool check through the config's resolver, parsers: keyed on the config
#   test     runtime plus the installs; layers from least to most often changed

ARG BASE=docker.io/library/debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

# ---- runtime --------------------------------------------------------------------------------------------------
FROM ${BASE} AS runtime
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
# Bump: change the version and its sha256 (the release asset's digest).
ARG MISE_VERSION=2026.10.8
ARG MISE_SHA256=c72477ae6c3a8e7d817a322f43da70e4643e75ee5c21265f1c19c894273b7428
# nv.sh puts tree-sitter 0.27.0 on PATH on the host; keep the two in step
ARG TREE_SITTER_VERSION=0.27.0
ARG TREE_SITTER_SHA256=20a1f39ec1c45f2211492dcb8881c802b643b554bb196869a29ac3778277fa77
ARG RUSTUP_VERSION=1.29.1
ARG RUSTUP_SHA256=dda7234360b7f578ca8b0ddcb80145646fa61a67c1720a5abc7051b35c9fcb71
# git: vim.pack and the git checks; tmux: pending_keys.sh; procps (pgrep), gawk (suite.sh's report): the runner;
# curl, gcc, libc6-dev: a first start's parser downloads and builds (fresh_bootstrap.sh); python3: the interpreter
# the suite's pypi tools were installed against, as on the host; libicu76: marksman (.NET) exits without it;
# tini: PID 1 reaps the checks' orphans; inotify-tools: inotifywait, which pyrefly requires (tools/catalog.lua)
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl gawk gcc git libc6-dev libicu76 procps python3 \
    inotify-tools tini tmux \
  && rm -rf /var/lib/apt/lists/*
RUN curl -fsSLo /usr/local/bin/mise "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-x64" \
  && echo "${MISE_SHA256}  /usr/local/bin/mise" | sha256sum -c --quiet \
  && chmod 755 /usr/local/bin/mise \
  && curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/download/v${TREE_SITTER_VERSION}/tree-sitter-linux-x64.gz" -o /tmp/ts.gz \
  && echo "${TREE_SITTER_SHA256}  /tmp/ts.gz" | sha256sum -c --quiet \
  && gunzip -c /tmp/ts.gz >/usr/local/bin/tree-sitter && chmod 755 /usr/local/bin/tree-sitter && rm /tmp/ts.gz \
  && curl -fsSLo /tmp/rustup-init "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init" \
  && echo "${RUSTUP_SHA256}  /tmp/rustup-init" | sha256sum -c --quiet \
  && chmod 755 /tmp/rustup-init \
  && RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo /tmp/rustup-init -q -y --no-modify-path --profile minimal --default-toolchain none \
  && rm /tmp/rustup-init && chmod -R a+rX /usr/local/cargo /usr/local/rustup
# rustup and its proxies (rust-analyzer, cargo...) on PATH, as ~/.cargo/bin is on the host; the toolchain is the
# suite's own, data/rustup (lib.sh mise_env sets RUSTUP_HOME)
ENV LANG=C.UTF-8 PATH=/opt/nvim/bin:/usr/local/cargo/bin:$PATH NVR_NVIM=/opt/nvim/bin/nvim
RUN useradd --create-home --uid 1000 --shell /bin/bash nvr && mkdir /work && chown nvr:nvr /work

# ---- nvim: the pinned nightly ---------------------------------------------------------------------------------
# Neovim keeps no old nightly builds (the `nightly` release is replaced every night), so the pin is a commit on
# master, built here. Bump: set NVIM_COMMIT to a newer master commit, e.g. the one `nvim --version` of the latest
# nightly names (v0.13.0-dev-NNNN+g<sha>).
FROM ${BASE} AS nvim
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
ARG NVIM_COMMIT=be5167e21cfbb5d566c09a67c1852d0e18c62c38
ARG JOBS=4
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates cmake curl gcc g++ gettext git libc6-dev make ninja-build unzip \
  && rm -rf /var/lib/apt/lists/*
RUN git init -q /src && cd /src \
  && git fetch -q --depth 1 https://github.com/neovim/neovim "${NVIM_COMMIT}" && git checkout -q FETCH_HEAD \
  && cmake -S cmake.deps -B .deps -G Ninja -D CMAKE_BUILD_TYPE=RelWithDebInfo && cmake --build .deps -j "${JOBS}" \
  && cmake -B build -G Ninja -D CMAKE_BUILD_TYPE=RelWithDebInfo -D CMAKE_INSTALL_PREFIX=/opt/nvim \
  && cmake --build build -j "${JOBS}" && cmake --install build \
  && cd / && rm -rf /src && /opt/nvim/bin/nvim --version | head -1

# ---- needs: every check's @needs, as one stub check -----------------------------------------------------------
FROM ${BASE} AS needs
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
COPY tests/regress/lib.sh /work/tests/regress/
COPY tests/regress/checks /work/tests/regress/checks
COPY tests/regress/selftest /work/tests/regress/selftest
COPY tests/regress/work /work/tests/regress/work
# the same files and the same first-@needs-line parse as refresh.lua's suite_needs (lib.sh header)
RUN mkdir -p /work/nvim && cd /work/tests/regress && . ./lib.sh \
  && for f in checks/* selftest/* work/*/*; do case $f in *.lua | *.sh) header "$f" needs ;; esac; done \
  | tr ' ' '\n' | sed '/^$/d' | sort -u | paste -sd ' ' | sed 's/^/-- @needs /' >/needs.lua \
  && cat /needs.lua

# ---- tools: the suite's mise and rustup ----------------------------------------------------------------------
FROM runtime AS tools
# mise's pypi backend installs with uv; only the install needs it
ARG UV_VERSION=0.13.0
ARG UV_SHA256=1468ebd5a5541121837c5a2817b9972ba6090fa6caa3d142620850a47fb75154
RUN apt-get update && apt-get install -y --no-install-recommends bzip2 unzip xz-utils && rm -rf /var/lib/apt/lists/* \
  && curl -fsSLo /tmp/uv.tgz "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" \
  && echo "${UV_SHA256}  /tmp/uv.tgz" | sha256sum -c --quiet \
  && tar -xzf /tmp/uv.tgz -C /usr/local/bin --strip-components=1 && rm /tmp/uv.tgz
COPY --from=nvim /opt/nvim /opt/nvim
USER nvr
WORKDIR /work
COPY --chown=nvr:nvr tests/regress/suite.sh tests/regress/lib.sh tests/regress/nv.sh tests/regress/refresh.lua tests/regress/
# the tools step needs the catalog only: a stub config holds it, so the rest of the config is no input here
COPY --chown=nvr:nvr nvim/lua/tools/catalog.lua stub/lua/tools/
COPY --from=needs --chown=nvr:nvr /needs.lua tests/regress/checks/
# GITHUB_TOKEN, when the build passes one, lifts GitHub's anonymous API rate limit for mise; it stays in this RUN
RUN --mount=type=secret,id=github_token,required=false,uid=1000 \
  token=$(cat /run/secrets/github_token 2>/dev/null || true) \
  && { [ -z "$token" ] || export GITHUB_TOKEN=$token; } \
  && mkdir -p nvim && touch stub/init.lua \
  && { CFG=/work/stub NVR_REFRESH_STEPS=tools tests/regress/suite.sh --refresh-only \
    || { cat tests/regress/last/refresh.log; exit 1; }; } \
  && rm -rf tests/regress/shared-cache tests/regress/last tests/regress/data/rustup/downloads tests/regress/data/rustup/tmp \
    tests/regress/data/mise/data/downloads tests/regress/data/mise/data/cache \
  && du -sh tests/regress/data/*

# ---- plugins: vim.pack, the tool check, parsers ----------------------------------------------------------------
FROM tools AS plugins
RUN rm -rf stub tests/regress/checks
COPY --chown=nvr:nvr nvim nvim
COPY --chown=nvr:nvr tests/regress tests/regress
RUN { NVR_REFRESH_STEPS="plugins resolve parsers" tests/regress/suite.sh --refresh-only \
    || { cat tests/regress/last/refresh.log; exit 1; }; } \
  && rm -rf tests/regress/shared-cache tests/regress/last \
  && find nvim -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1 >/work/.image-config.sum \
  && du -sh tests/regress/data/nvim

# ---- test: the image --------------------------------------------------------------------------------------------
FROM runtime AS test
COPY --from=nvim /opt/nvim /opt/nvim
COPY --from=tools --chown=nvr:nvr /work/tests/regress/data/rustup /work/tests/regress/data/rustup
COPY --from=tools --chown=nvr:nvr /work/tests/regress/data/mise /work/tests/regress/data/mise
COPY --from=plugins --chown=nvr:nvr /work/tests/regress/data/nvim /work/tests/regress/data/nvim
COPY --from=plugins --chown=nvr:nvr /work/.image-config.sum /work/
# suite.sh seeds each run's cache from cache-seed/; the image starts cold
RUN install -d -o nvr -g nvr /work/tests/regress/cache-seed
COPY tests/image/entrypoint.sh /usr/local/bin/nvr-test
USER nvr
WORKDIR /work
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/nvr-test"]
