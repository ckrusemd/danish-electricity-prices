# syntax=docker/dockerfile:1
FROM rocker/r-ver:4.6.1@sha256:4e6e6696ff54a86625c7f80046478e67014a2184e942b85eeff43db7b992d93e

LABEL org.opencontainers.image.source="https://github.com/ckrusemd/danish-electricity-prices"
LABEL org.opencontainers.image.description="Locked R environment for the Danish electricity prices publication"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    R_LIBS_USER=/opt/electricity/library \
    RENV_CONFIG_REPOS_OVERRIDE=https://cloud.r-project.org \
    RENV_CONFIG_CACHE_ENABLED=FALSE

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        libcurl4-openssl-dev \
        libfontconfig1-dev \
        libfreetype6-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libssl-dev \
        libxml2-dev \
        pkg-config \
        ca-certificates curl git python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /environment

COPY Dockerfile .dockerignore .Rprofile renv.lock ./
COPY renvinfra/ renvinfra/
COPY scripts/environment-*.sh scripts/verify-environment.R scripts/

RUN bash scripts/environment-install-quarto.sh /opt/quarto \
    && bash scripts/environment-restore.sh /opt/electricity/library
ENV PATH=/opt/quarto/bin:$PATH
RUN bash scripts/environment-fingerprint.sh > /opt/electricity/environment.sha256 \
    && Rscript --vanilla scripts/verify-environment.R
WORKDIR /project

CMD ["Rscript", "--vanilla"]
