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

  defmacro consume(queue, routing_key, consumer) do
    quote do
      @wirings {unquote(queue), unquote(routing_key), unquote(consumer)}
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def init(_) do
        [connection: config] = Application.get_env(:errol, __MODULE__)
        {:ok, connection} = AMQP.Connection.open(config)

        Enum.map(@wirings, fn {queue, routing_key, consumer} ->
          {consumer,
           [
             queue: queue,
             routing_key: routing_key,
             connection: connection,
             exchange: {@exchange, @exchange_type}
           ]}
        end)
        |> Supervisor.init(strategy: :one_for_one)
      end
    end
  end
end
