defmodule Errol.Wiring do
  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :wirings, accumulate: true)
      @before_compile unquote(__MODULE__)

      use Supervisor

      def start_link(_) do
        Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
      end
    end
  end

  defmacro wire(queue, routing_key, consumer) do
    quote do
      @wirings {unquote(queue), unquote(routing_key), unquote(consumer)}
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def init(_) do
        {:ok, connection} = AMQP.Connection.open(host: "localhost")
        {:ok, channel} = AMQP.Channel.open(connection)
        :ok = AMQP.Exchange.declare(channel, @exchange, @exchange_type)

        Enum.map(@wirings, fn {queue, routing_key, consumer} ->
          {consumer,
           [queue: queue, routing_key: routing_key, channel: channel, exchange: @exchange]}
        end)
        |> Supervisor.init(strategy: :one_for_one)
      end
    end
  end
end
