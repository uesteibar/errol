# Errol

An opinionated framework to define and orchestrate AMQP consumers.

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
  use Errol.Wiring

  @connection "amqp://guest:guest@localhost"
  @exchange "wiring_exchange"
  @exchange_type :topic

  # You can pass a reference to a function with arity of 1
  consume "my_awesome_queue", "my.routing.key", &Sample.AwesomeConsumer.consume/1
end
```

For the `@connection` attribute, you can pass anything that fits what the [amqp](https://hexdocs.pm/amqp/1.0.2/AMQP.Connection.html#open/1) hex expects on `AMQP.Connection.open/1`.

At this point, the only thing you have to do is run `Sample.Wiring` as a _supervisor_ in your `application.ex` file:

```elixir
defmodule Sample.Application do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      supervisor(Sample.Wiring, []),
    ]

    opts = [strategy: :one_for_one, name: Sample.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Voila! This will spin up the following supervision tree:

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
                   ______________|______________
                  |                             |
                  |                             |
      -------------------------       -------------------------
     | :another_queue_consumer |     | :another_queue_consumer |
      -------------------------       -------------------------
        .     .     .     .             .    .    .    .    .
        .     .     .     .             .    .    .    .    .
        .     .     .     .             .    .    .    .    .
        .     .     .     .             .    .    .    .    .
        .     .     .     .             .    .    .    .    .

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

