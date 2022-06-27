# syntax=docker/dockerfile:1.3

ARG DIST=community

# Install the SWI-Prolog pack dependencies.
FROM terminusdb/swipl:v8.4.2 AS pack_installer
RUN set -eux; \
    BUILD_DEPS="git build-essential make libjwt-dev libssl-dev pkg-config"; \
    apt-get update; \
    apt-get install -y --no-install-recommends ${BUILD_DEPS}; \
    rm -rf /var/lib/apt/lists/*
WORKDIR /app/pack
COPY distribution/Makefile.deps Makefile
RUN make

# Install Rust. Prepare to build the Rust code.
FROM terminusdb/swipl:v8.4.2 AS rust_builder_base
RUN set -eux; \
    BUILD_DEPS="git build-essential curl clang ca-certificates"; \
    apt-get update; \
    apt-get install -y --no-install-recommends ${BUILD_DEPS}; \
    rm -rf /var/lib/apt/lists/*
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
# Initialize the crates.io index git repo to cache it.
RUN cargo install lazy_static 2> /dev/null || true
WORKDIR /app/rust
COPY distribution/Makefile.rust Makefile
COPY src/rust src/rust/

# Build the community dylib.
FROM rust_builder_base AS rust_builder_community
RUN make DIST=community

# Build the enterprise dylib.
FROM rust_builder_base AS rust_builder_enterprise
COPY terminusdb-enterprise/rust terminusdb-enterprise/rust/
RUN make DIST=enterprise

# Build the ${DIST} dylib.
FROM rust_builder_${DIST} AS rust_builder

# Copy the packs and dylib. Prepare to build the Prolog code.
FROM terminusdb/swipl:v8.4.2 AS base
RUN set -eux; \
    RUNTIME_DEPS="libjwt0 make openssl"; \
    apt-get update; \
    apt-get install -y --no-install-recommends ${RUNTIME_DEPS}; \
    rm -rf /var/cache/apt/*; \
    rm -rf /var/lib/apt/lists/*
ARG TERMINUSDB_GIT_HASH=null
ENV TERMINUSDB_GIT_HASH=${TERMINUSDB_GIT_HASH}
ARG TERMINUSDB_JWT_ENABLED=true
ENV TERMINUSDB_JWT_ENABLED=${TERMINUSDB_JWT_ENABLED}
COPY --from=pack_installer /root/.local/share/swi-prolog/pack/ /usr/share/swi-prolog/pack
WORKDIR /app/terminusdb
COPY distribution/init_docker.sh distribution/
COPY distribution/Makefile.prolog Makefile
COPY src src/
COPY --from=rust_builder /app/rust/src/rust/librust.so src/rust/

# Build the community executable.
FROM base AS base_community
RUN set -eux; \
    touch src/rust/librust.so; \
    make DIST=community

# Build the enterprise executable.
FROM base AS base_enterprise
COPY terminusdb-enterprise/prolog terminusdb-enterprise/prolog/
RUN set -eux; \
    touch src/rust/librust.so; \
    make DIST=enterprise

# Build the ${DIST} executable. Set the default command.
FROM base_${DIST}
RUN groupadd -r -g 999 terminusdb && \
    useradd -r -g terminusdb -u 999 terminusdb && \
    mkdir storage && \
    chown terminusdb:terminusdb storage
USER terminusdb
CMD ["/app/terminusdb/distribution/init_docker.sh"]
