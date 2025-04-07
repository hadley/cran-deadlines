# syntax=docker/dockerfile:1.7-labs
# ^^^ needed for COPY --exclude

# This is the SHA of a multi-arch manifest, so it'll use the native
# container on amd64 / arm64.
ARG BASE=ghcr.io/r-lib/rig/ubuntu-22.04-release@sha256:1dc2de2cf32dd10945a4ed3714ae35e73b01e1ea47f458c3e9dc82eef016a3e2

# -------------------------------------------------------------------------
# build stage has stuff needed for everything, e.g. R, hard dependencies
# -------------------------------------------------------------------------
FROM --platform=linux/amd64 ${BASE} AS build

COPY ./DESCRIPTION .
RUN R -q -e 'pak::pkg_install("deps::.", lib = .Library); pak::pak_cleanup(force = TRUE)' && \
    apt-get clean && \
    rm -rf DESCRIPTION /tmp/*

# -------------------------------------------------------------------------
# test-deps stage have stuff needed to run the tests and also for dev
# -------------------------------------------------------------------------
FROM build AS test-deps

ENV NOT_CRAN=true

COPY ./DESCRIPTION .
RUN R -q -e 'pak::pkg_install("deps::.", dependencies = TRUE)'; \
    apt-get clean && \
    rm -rf DESCRIPTION /tmp/*

# -------------------------------------------------------------------------
# This stage actually runs the tests + test coverage
# -------------------------------------------------------------------------
FROM test-deps AS test

COPY . /app
WORKDIR /app

RUN if [ -d tests ]; then \
      R -q -e 'testthat::test_local()'; \
    fi

# -------------------------------------------------------------------------
# production stage, this is deployed. Has the extra stuff only needed
# for deployment
# -------------------------------------------------------------------------
FROM build AS prod
COPY --from=test /tmp/dummy* /tmp/

# copy everything, except the tests
COPY --exclude=tests . /app

# tools neeed for prod
RUN apt-get update && \
    apt-get install -y git rsync && \
    apt-get clean

# -------------------------------------------------------------------------
# for development. This is the default, so devcontainers run this.
# it has the test-deps, plus stuff only needed for development
# -------------------------------------------------------------------------
FROM test-deps AS dev

RUN R -q -e 'pak::pkg_install(c("devtools", "usethis", "profvis"))'
RUN R -q -e 'pak::pkg_install("languageserver")'

RUN apt-get update && \
    apt-get install -y openssh-server && \
    apt-get clean

RUN echo PermitRootLogin yes >> /etc/ssh/sshd_config && \
    echo PermitEmptyPasswords yes >> /etc/ssh/sshd_config && \
    echo Port 2222 >> /etc/ssh/sshd_config && \
    passwd -d root

RUN git config --global --add safe.directory '/workspaces/*'
