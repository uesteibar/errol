# Errol

An opinionated framework to run and orchestrate [RabbitMQ](https://www.rabbitmq.com/) consumers.

## Index

- [Installation](#installation)
- [Usage](#usage)
- [Running Locally](#running-locally)

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

  @connection "amqp://guest:guest@localhost"
  @exchange "/users"
  @exchange_type :topic

  # Use pipe_before/1, pipe_after/1 or pipe_error/1 to run middleware functions
  # middlewares declared outside of a group will run for every consumer
  pipe_before(&Sample.StatisticsMiddleware.track/1)
  
  # Use the `group` macro to group consumers with specific middleware
  group :account do
    pipe_before(&Errol.Middleware.Json.parse/1)

    # You can pass a reference to a function with arity of 1
    consume("account_created", "users.account.created", &UsersConsumer.account_created/1)

    # or even an anonymous function
    consume("account_updated", "users.account.updated", fn message -> ... end)
  end

  group :photos do
    pipe_before(&Sample.ImagesMiddleware.uncompress/1)

    consume("profile_photo_uploaded", "users.profile.photo.uploaded", fn message -> ... end)
  end
end
```

For the `@connection` attribute, you can pass anything that fits what the [amqp](https://hexdocs.pm/amqp) hex expects on [`AMQP.Connection.open/1`](https://hexdocs.pm/amqp/1.0.2/AMQP.Connection.html#open/1).

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

