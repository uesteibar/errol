defmodule Errol.Wiring do
  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :wirings, accumulate: true)
      Module.register_attribute(__MODULE__, :connection, acumulate: false)
      @connection []
      @before_compile unquote(__MODULE__)

      use Supervisor

      def start_link(_) do
        Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
      end
    end
  end

  defmacro consume(queue, routing_key, callback) do
    quote do
      @wirings {unquote(queue), unquote(routing_key), unquote(callback)}
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def init(_) do
        {:ok, connection} = AMQP.Connection.open(@connection)

        Enum.map(@wirings, fn {queue, routing_key, callback} ->
          Supervisor.child_spec(
            {
              Errol.Consumer.Server,
              [
                name: :"#{queue}_consumer",
                queue: queue,
                routing_key: routing_key,
                connection: connection,
                callback: callback,
                exchange: {@exchange, @exchange_type}
              ]
            },
            id: queue
          )
        end)
        |> Supervisor.init(strategy: :one_for_one)
      end
    end
  end
end
