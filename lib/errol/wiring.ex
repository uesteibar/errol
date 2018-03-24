defmodule Errol.Wiring do
  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :wirings, accumulate: true)
      @before_compile unquote(__MODULE__)
    end
  end

  defmacro wire(queue, routing_key, consumer) do
    quote do
      @wirings {unquote(queue), unquote(routing_key), unquote(consumer)}
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def run do
        {:ok, connection} = AMQP.Connection.open(host: "localhost")
        {:ok, channel} = AMQP.Channel.open(connection)
        :ok = AMQP.Exchange.declare(channel, @exchange, @exchange_type)

        IO.puts("Wiring...")

        Enum.each(@wirings, fn {queue, routing_key, consumer} ->
          consumer.start_link(
            queue: queue,
            routing_key: routing_key,
            channel: channel,
            exchange: @exchange
          )
        end)
      end
    end
  end
end
