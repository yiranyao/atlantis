# Stage 1: build artifact
FROM golang:1.19.4-alpine AS builder

WORKDIR /app
COPY . /app
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -v -o atlantis .

# Stage 2
# The runatlantis/atlantis-base is created by docker-base/Dockerfile.
# FROM ghcr.io/runatlantis/atlantis-base:2022.11.24 AS base

# This Dockerfile builds our base image with gosu, dumb-init and the atlantis
# user. We split this from the main Dockerfile because this base doesn't change
# and also because it kept breaking the build due to flakiness.
FROM alpine:3.16.3
LABEL authors="Anubhav Mishra, Luke Kysow"

# We use gosu to step down from root and run as the atlantis user so we need
# to create that user and group.
# We add the atlantis user to the root group and make its home directory
# owned by root so that OpenShift users can use /home/atlantis as their
# data dir because OpenShift runs containers as a random uid that's part of
# the root group.
RUN addgroup atlantis && \
    adduser -S -G atlantis atlantis && \
    adduser atlantis root && \
    chown atlantis:root /home/atlantis/ && \
    chmod g=u /home/atlantis/ && \
    chmod g=u /etc/passwd

# Install gosu and git-lfs.
ENV GOSU_VERSION=1.14
ENV GIT_LFS_VERSION=3.1.2

# Automatically populated with the architecture the image is being built for.
ARG TARGETPLATFORM

# Install packages needed for running Atlantis.
RUN apk add --no-cache \
        ca-certificates=20220614-r0 \
        curl=7.83.1-r4 \
        git=2.36.3-r0 \
        unzip=6.0-r9 \
        bash=5.1.16-r2 \
        openssh=9.0_p1-r2 \
        libcap=2.64-r0 \
        dumb-init=1.2.5-r1 \
        gcompat=1.0.0-r4 && \
    # Install packages needed for building dependencies.
    apk add --no-cache --virtual .build-deps \
        gnupg=2.2.35-r4 \
        openssl=1.1.1s-r0 && \
    mkdir -p /tmp/build && \
    cd /tmp/build && \
    # git-lfs
    case ${TARGETPLATFORM} in \
        "linux/amd64") GIT_LFS_ARCH=amd64 ;; \
        "linux/arm64") GIT_LFS_ARCH=arm64 ;; \
        "linux/arm/v7") GIT_LFS_ARCH=arm ;; \
    esac && \
    curl -L -s --output git-lfs.tar.gz "https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/git-lfs-linux-${GIT_LFS_ARCH}-v${GIT_LFS_VERSION}.tar.gz" && \
    tar -xf git-lfs.tar.gz && \
    chmod +x git-lfs && \
    mv git-lfs /usr/bin/git-lfs && \
    git-lfs --version && \
    # gosu
    case ${TARGETPLATFORM} in \
        "linux/amd64") GOSU_ARCH=amd64 ;; \
        "linux/arm64") GOSU_ARCH=arm64 ;; \
        "linux/arm/v7") GOSU_ARCH=armhf ;; \
    esac && \
    curl -L -s --output gosu "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${GOSU_ARCH}" && \
    curl -L -s --output gosu.asc "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${GOSU_ARCH}.asc" && \
    for server in $(shuf -e ipv4.pool.sks-keyservers.net \
                            hkp://p80.pool.sks-keyservers.net:80 \
                            keyserver.ubuntu.com \
                            hkp://keyserver.ubuntu.com:80 \
                            pgp.mit.edu) ; do \
        gpg --keyserver "$server" --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 && break || : ; \
    done && \
    gpg --batch --verify gosu.asc gosu && \
    chmod +x gosu && \
    cp gosu /bin && \
    gosu --version && \
    # Cleanup
    cd /tmp && \
    rm -rf /tmp/build && \
    gpgconf --kill dirmngr && \
    gpgconf --kill gpg-agent && \
    apk del .build-deps && \
    rm -rf /root/.gnupg

# Get the architecture the image is being built for
ARG TARGETPLATFORM

# install terraform binaries
ENV DEFAULT_TERRAFORM_VERSION=1.3.5

# In the official Atlantis image we only have the latest of each Terraform version.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN AVAILABLE_TERRAFORM_VERSIONS="0.12.31 0.13.7 1.0.11 1.1.9 1.2.9 ${DEFAULT_TERRAFORM_VERSION}" && \
    case "${TARGETPLATFORM}" in \
        "linux/amd64") TERRAFORM_ARCH=amd64 ;; \
        "linux/arm64") TERRAFORM_ARCH=arm64 ;; \
        "linux/arm/v7") TERRAFORM_ARCH=arm ;; \
        *) echo "ERROR: 'TARGETPLATFORM' value expected: ${TARGETPLATFORM}"; exit 1 ;; \
    esac && \
    for VERSION in ${AVAILABLE_TERRAFORM_VERSIONS}; do \
        curl -LOs "https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_${TERRAFORM_ARCH}.zip" && \
        curl -LOs "https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_SHA256SUMS" && \
        sed -n "/terraform_${VERSION}_linux_${TERRAFORM_ARCH}.zip/p" "terraform_${VERSION}_SHA256SUMS" | sha256sum -c && \
        mkdir -p "/usr/local/bin/tf/versions/${VERSION}" && \
        unzip "terraform_${VERSION}_linux_${TERRAFORM_ARCH}.zip" -d "/usr/local/bin/tf/versions/${VERSION}" && \
        ln -s "/usr/local/bin/tf/versions/${VERSION}/terraform" "/usr/local/bin/terraform${VERSION}" && \
        rm "terraform_${VERSION}_linux_${TERRAFORM_ARCH}.zip" && \
        rm "terraform_${VERSION}_SHA256SUMS"; \
    done && \
    ln -s "/usr/local/bin/tf/versions/${DEFAULT_TERRAFORM_VERSION}/terraform" /usr/local/bin/terraform

ENV DEFAULT_CONFTEST_VERSION=0.35.0

RUN AVAILABLE_CONFTEST_VERSIONS="${DEFAULT_CONFTEST_VERSION}" && \
    case ${TARGETPLATFORM} in \
        "linux/amd64") CONFTEST_ARCH=x86_64 ;; \
        "linux/arm64") CONFTEST_ARCH=arm64 ;; \
        # There is currently no compiled version of conftest for armv7
        "linux/arm/v7") CONFTEST_ARCH=x86_64 ;; \
    esac && \
    for VERSION in ${AVAILABLE_CONFTEST_VERSIONS}; do \
        curl -LOs https://github.com/open-policy-agent/conftest/releases/download/v${VERSION}/conftest_${VERSION}_Linux_${CONFTEST_ARCH}.tar.gz && \
        curl -LOs https://github.com/open-policy-agent/conftest/releases/download/v${VERSION}/checksums.txt && \
        sed -n "/conftest_${VERSION}_Linux_${CONFTEST_ARCH}.tar.gz/p" checksums.txt | sha256sum -c && \
        mkdir -p /usr/local/bin/cft/versions/${VERSION} && \
        tar -C /usr/local/bin/cft/versions/${VERSION} -xzf conftest_${VERSION}_Linux_${CONFTEST_ARCH}.tar.gz && \
        ln -s /usr/local/bin/cft/versions/${VERSION}/conftest /usr/local/bin/conftest${VERSION} && \
        rm conftest_${VERSION}_Linux_${CONFTEST_ARCH}.tar.gz && \
        rm checksums.txt; \
    done

RUN ln -s /usr/local/bin/cft/versions/${DEFAULT_CONFTEST_VERSION}/conftest /usr/local/bin/conftest

# Download Terragrunt v0.25.3
RUN TERRAGRUNT_VS=0.25.3 && \
    curl -LOs https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VS}/terragrunt_linux_amd64 && \
    curl -LOs https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VS}/SHA256SUMS && \
    sed -n "/terragrunt_linux_amd64/p" SHA256SUMS | sha256sum -c && \
    chmod +x terragrunt_linux_amd64 && \
    mv terragrunt_linux_amd64 /usr/local/bin/terragrunt && \
    rm SHA256SUMS;

# copy binary
COPY --from=builder /app/atlantis /usr/local/bin/atlantis

# copy docker entrypoint
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["server"]
