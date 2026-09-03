# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bullseye-20260713-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.18.4-erlang-28.5.0.2-debian-bookworm-20260610-slim
#
# Pinned to match the dev toolchain in .tool-versions (Elixir 1.18.4 / OTP 28).
# This app is a version-sensitive Phoenix 1.7 + Beacon 0.5.1 stack (see lessons.md),
# so prod must build on the same Elixir minor as dev — do NOT bump to 1.19 here.
# OTP 28.5.0.2 is the highest published hexpm image for 1.18.4 (dev runs 28.5.0.5;
# the patch gap is immaterial for compilation).
#
# Debian BOOKWORM (glibc 2.36), NOT bullseye (glibc 2.31): Beacon pulls in the
# mdex_native Rust NIF whose prebuilt binary requires GLIBC_2.33+. On bullseye the
# release builds fine but crashes at boot: "Failed to load NIF library: ... version
# `GLIBC_2.33' not found". Builder and runner must share this same Debian version.
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=28.5.0.2
ARG DEBIAN_VERSION=bookworm-20260610-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

# install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv

COPY lib lib

COPY assets assets

# Compile the app FIRST. This app uses LiveView colocated hooks, so `mix compile`
# generates _build/$MIX_ENV/phoenix-colocated/music_studio (and the assets/node_modules
# symlink to it). assets/js/app.js and assets/css/app.css import from that path, so assets
# must be built AFTER compile — otherwise `mix tailwind` fails to resolve colocated.css.
RUN mix compile

# compile assets (tailwind + esbuild + phx.digest) — needs the colocated output above
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Beacon compiles CMS JS/CSS at runtime, so it needs the esbuild + tailwind binaries
# present in the runner. `mix assets.deploy` installed them to /app/bin (the absolute
# path pinned in config/prod.exs); copy them to the same path here.
COPY --from=builder --chown=nobody:root /app/bin /app/bin

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/music_studio ./

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

# Run pending migrations, then start the server. Migrate-on-boot keeps this working on
# any Render plan (the free tier has no pre-deploy hook) and is idempotent — already-applied
# migrations are a fast no-op. Single free instance, so no migration race.
CMD ["/bin/sh", "-c", "/app/bin/migrate && /app/bin/server"]
