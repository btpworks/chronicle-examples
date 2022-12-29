ARG CHRONICLE_BUILDER_IMAGE=blockchaintp/chronicle-builder
ARG CHRONICLE_VERSION=BTP2.1.0
FROM ${CHRONICLE_BUILDER_IMAGE}:${CHRONICLE_VERSION} as builder

ARG DOMAIN=artworld
ARG RELEASE=no
ARG FEATURES=""
COPY domains/${DOMAIN}/domain.yaml crates/chronicle-domain/
RUN /usr/local/bin/chronicle-domain-lint crates/chronicle-domain/domain.yaml
RUN cat crates/chronicle-domain/domain.yaml
RUN if [ "${RELEASE}" = "yes" ]; then \
    if [ -n "${FEATURES}" ]; then \
      cargo build --release --frozen --features "${FEATURES}" --bin chronicle; \
    else \
      cargo build --release --frozen --bin chronicle; \
    fi \
    && cp target/release/chronicle /usr/local/bin/; \
  else \
    if [ -n "${FEATURES}" ]; then \
      cargo build --frozen --features "${FEATURES}" --bin chronicle; \
    else \
      cargo build --frozen --bin chronicle; \
    fi \
    && cp target/debug/chronicle /usr/local/bin/; \
  fi;

WORKDIR /
FROM ubuntu:focal AS domain

RUN apt-get update && \
  apt-get install -y \
  libpq-dev \
  ca-certificates

COPY --from=builder --chown=root:bin /usr/local/bin/chronicle /usr/local/bin
COPY --chown=root:bin entrypoint /entrypoint
RUN chmod 755 \
  /entrypoint \
  /usr/local/bin/chronicle

ENTRYPOINT [ "/entrypoint" ]
