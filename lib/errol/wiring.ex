defmodule Errol.Wiring do
  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :wirings, accumulate: true)
      Module.register_attribute(__MODULE__, :group_name, [])
      @group_name :default
      Module.register_attribute(__MODULE__, :middlewares, accumulate: false)
      @middlewares %{default: %{before: [], after: [], error: []}}
      Module.register_attribute(__MODULE__, :connection, [])
      @connection []
      @before_compile unquote(__MODULE__)

      use Supervisor

      def start_link(_) do
        Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
      end
    end
  end

  defmacro group(name, do: block) do
    quote bind_quoted: [name: name, block: block] do
      @group_name name
      @middlewares put_in(@middlewares, [name], %{before: [], after: [], error: []})

      block
    end
  end

  defmacro pipe_before(callback) do
    quote bind_quoted: [callback: callback] do
      @middlewares put_in(
                     @middlewares,
                     [@group_name, :before],
                     get_in(@middlewares, [@group_name, :before]) ++ [callback]
                   )
    end
  end

  defmacro pipe_after(callback) do
    quote bind_quoted: [callback: callback] do
      @middlewares put_in(
                     @middlewares,
                     [@group_name, :after],
                     get_in(@middlewares, [@group_name, :after]) ++ [callback]
                   )
    end
  end

  defmacro pipe_error(callback) do
    quote bind_quoted: [callback: callback] do
      @middlewares put_in(
                     @middlewares,
                     [@group_name, :error],
                     get_in(@middlewares, [@group_name, :error]) ++ [callback]
                   )
    end
  end

  defmacro consume(queue, routing_key, callback) do
    queue = String.to_atom(queue)

    quote do
      @wirings {unquote(queue), unquote(routing_key), @group_name}
      def unquote(queue)() do
        unquote(callback)
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def init(_) do
        {:ok, connection} = AMQP.Connection.open(@connection)

        @wirings
        |> Enum.map(fn {queue, routing_key, group_name} ->
          callback = apply(__MODULE__, queue, [])

          Supervisor.child_spec(
            {
              Errol.Consumer.Server,
              [
                name: :"#{queue}_consumer",
                queue: Atom.to_string(queue),
                routing_key: routing_key,
                connection: connection,
                callback: callback,
                pipe_before: get_in(@middlewares, [group_name, :before]) || [],
                pipe_after: get_in(@middlewares, [group_name, :after]) || [],
                pipe_error: get_in(@middlewares, [group_name, :error]) || [],
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
