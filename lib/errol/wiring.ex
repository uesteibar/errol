defmodule Errol.Wiring do
  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :wirings, accumulate: true)
      Module.register_attribute(__MODULE__, :pipe_before, accumulate: true)
      Module.register_attribute(__MODULE__, :pipe_after, accumulate: true)
      Module.register_attribute(__MODULE__, :pipe_error, accumulate: true)
      Module.register_attribute(__MODULE__, :connection, [])
      @connection []
      @before_compile unquote(__MODULE__)

      use Supervisor

      def start_link(_) do
        Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
      end
    end
  end

  defmacro pipe_before(callback) do
    quote bind_quoted: [callback: callback] do
      @pipe_before callback
    end
  end

  defmacro pipe_after(callback) do
    quote bind_quoted: [callback: callback] do
      @pipe_after callback
    end
  end

  defmacro pipe_error(callback) do
    quote bind_quoted: [callback: callback] do
      @pipe_error callback
    end
  end

  defmacro consume(queue, routing_key, callback) do
    quote bind_quoted: [queue: queue, routing_key: routing_key, callback: callback] do
      @wirings {queue, routing_key, callback}
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def init(_) do
        {:ok, connection} = AMQP.Connection.open(@connection)

        @wirings
        |> Enum.map(fn {queue, routing_key, callback} ->
          Supervisor.child_spec(
            {
              Errol.Consumer.Server,
              [
                name: :"#{queue}_consumer",
                queue: queue,
                routing_key: routing_key,
                connection: connection,
                callback: callback,
                pipe_before: @pipe_before,
                pipe_after: @pipe_after,
                pipe_error: @pipe_error,
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
