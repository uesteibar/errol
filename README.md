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

You can configure the connection in your `config.exs` file:

```elixir
config :sample, Sample.Wiring,
  connection: "amqp://guest:guest@localhost"
```

or

```elixir
config :sample, Sample.Wiring,
  connection: [
    host: "localhost",
    port: "1234",
    ...
  ]
```

To define consumers, you can use the `Errol.Consumer` module:

```elixir
defmodule Sample.AwesomeConsumer do
  use Errol.Consumer

  def consume(%Errol.Message{payload: payload, meta: meta}) do
    ...
  end
end

defmodule Sample.AnotherConsumer do
  use Errol.Consumer

  def consume(%Errol.Message{payload: payload, meta: meta}) do
    ...
  end
end
```

To bind consumers to queue, you can use the `Errol.Wiring` module:

```elixir
defmodule Sample.Wiring do
  use Errol.Wiring

  @exchange "wiring_exchange"
  @exchange_type :topic

  consume "my_awesome_queue", "my.routing.key", Sample.AwesomeConsumer
  consume "another_queue", "another.*.key", Sample.AnotherConsumer
end
```

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
      ------------------------       ------------------------
     | Sample.AwesomeConsumer |     | Sample.AnotherConsumer |
      ------------------------       ------------------------
        .     .     .     .           .    .    .    .    .
        .     .     .     .           .    .    .    .    .
        .     .     .     .           .    .    .    .    .
        .     .     .     .           .    .    .    .    .
        .     .     .     .           .    .    .    .    .

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

