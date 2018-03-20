FROM bitwalker/alpine-elixir-phoenix

ENV DEBIAN_FRONTEND=noninteractive

RUN mix local.hex --force
RUN mix local.rebar --force

WORKDIR /app
ADD . /app

RUN mix deps.get

