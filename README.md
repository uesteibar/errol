# Errol

[![Build Status](https://travis-ci.org/uesteibar/errol.svg?branch=master)](https://travis-ci.org/uesteibar/errol)
[![Hex Version](https://img.shields.io/hexpm/v/errol.svg)](https://hex.pm/packages/errol)

An opinionated framework to run and orchestrate [RabbitMQ](https://www.rabbitmq.com/) consumers.

## Index

- [Installation](#installation)
- [Usage](#usage)
- [Running Locally](#running-locally)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [Credit](#credit)

## Installation

The package can be installed by adding `errol` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:errol, "~> 0.1.0"}]
end
```

You should also update your application list to include `:errol`:

```elixir
def application do
  [applications: [:errol]]
end
```

Documentation can be found at [https://hexdocs.pm/errol](https://hexdocs.pm/errol).

## Usage

To bind consumers to queue, you can use the `Errol.Wiring` module:

```elixir
defmodule Sample.Wiring do
  use Wiring

  connection "amqp://guest:guest@localhost"

  @exchange "/users"
  @exchange_type :topic

  # You can pass a reference to a function with arity of 1
  consume("account_created", "users.account.created", &UsersConsumer.account_created/1)

  # or even an anonymous function
  consume("account_updated", "users.account.updated", fn message -> ... end)
end
```

For more complex setups, you can add middleware and group different
consumers for more granularity.

```elixir
defmodule Sample.Wiring do
  use Wiring

  connection "amqp://guest:guest@localhost"

  @exchange "/users"
  @exchange_type :topic

  # Use pipe_before/1, pipe_after/1 or pipe_error/1 to run middleware functions
  # middlewares declared outside of a group will run for every consumer
  pipe_after(&Sample.StatisticsMiddleware.track/2)
  
  # Use the `group` macro to group consumers with specific middleware
  group :account do
    # This middlewares will run only for consumers in the :account group
    pipe_before(&Errol.Middleware.Json.parse/2)
    pipe_error(&Errol.Middleware.Retry.basic_retry/2)

    consume("account_created", "users.account.created", &UsersConsumer.account_created/1)
    consume("account_updated", "users.account.updated", fn message -> ... end)
  end

  group :photos do
    pipe_before(&Sample.ImagesMiddleware.uncompress/2)

    consume("profile_photo_uploaded", "users.profile.photo.uploaded", fn message -> ... end)
  end
end
```

At this point, the only thing left is to run `Sample.Wiring` as a _supervisor_ in your `application.ex` file:

```elixir
defmodule Sample.Application do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      supervisor(Sample.Wiring, []),
      ...
    ]

    opts = [strategy: :one_for_one, name: Sample.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Voilà! This will spin up the following supervision tree:

```

                                      --------------------
                                     | Sample.Application |
                                      --------------------
                                               |
                                               |
                                        ---------------
                                       | Sample.Wiring |
                                        ---------------
                                               |
                  _____________________________|_____________________________
                 |                             |                             |
                 |                             |                             |
   ---------------------------    ---------------------------    -------------------------
  | :account_created_consumer |  | :account_updated_consumer |  | :profile_photo_uploaded |
   ---------------------------    ---------------------------    -------------------------
       .     .     .     .           .    .    .    .    .          .     .     .     .
       .     .     .     .           .    .    .    .    .          .     .     .     .
       .     .     .     .           .    .    .    .    .          .     .     .     .
       .     .     .     .           .    .    .    .    .          .     .     .     .
       .     .     .     .           .    .    .    .    .          .     .     .     .

                       New monitored process per each message received


```

Compatibility with other AMQP implementations exists but is not guaranteed (at least for now 😁).

## Running locally

Clone the repository
```bash
git clone git@github.com:uesteibar/errol.git
```

Install dependencies
```bash
cd errol
mix deps.get
```

To run the tests (you will need [docker](https://www.docker.com/) installed)
```bash
./scripts/test_prepare.sh
mix test
```

## Roadmap

- [x] Allow to retry messages from `pipe_error` middleware. This would enable users to handle retries and requeuing to dead letter exchange.
- [ ] Allow to specify number of workers per consumer. [Poolboy](https://github.com/devinus/poolboy) would come handy here.
- [ ] Handle RabbitMQ outages, following the great explanation in the [amqp hex documentation](https://hexdocs.pm/amqp/readme.html#stable-rabbitmq-connection).
- [ ] Publish messages.
- [ ] Add a middleware to ensure duplicated messages are not consumed more than once.

## Contributing

Pull requests are always welcome =)

The project uses [standard-changelog](https://github.com/conventional-changelog/conventional-changelog) to update the _Changelog_ with each commit message and upgrade the package version.
For that reason every contribution must have a title and body that follows the [conventional commits standard](https://conventionalcommits.org/) conventions (e.g. `feat(consumer): Consume it all`).

To make this process easier, you can do the following:

Install `commitizen` and `cz-conventional-changelog` globally
```bash
npm i -g commitizen cz-conventional-changelog
```

Save `cz-conventional-changelog` as default
```bash
echo '{ "path": "cz-conventional-changelog" }' > ~/.czrc
```

Instead of `git commit`, you can now run
```
git cz
```
and follow the instructions to generate the commit message.

### Credit

🎉 Special thanks to [**@pma**](https://github.com/pma) for the amazing work on the [amqp hex](https://github.com/pma/amqp).

