defmodule Errol.Consumer do
  defmacro __using__(_) do
    quote do
      use GenServer

      def start_link(args) do
        GenServer.start_link(__MODULE__, args)
      end

      def init(options) do
        {:ok, channel} = setup_queue(options)

        {:ok, %{channel: channel}}
      end

      defp setup_queue(options) do
        channel = Keyword.get(options, :channel)
        queue = Keyword.get(options, :queue)
        exchange = Keyword.get(options, :exchange, "")
        routing_key = Keyword.get(options, :routing_key, "*")

        {:ok, _} = AMQP.Queue.declare(channel, queue)
        :ok = AMQP.Queue.bind(channel, queue, exchange, routing_key: routing_key)
        {:ok, _} = AMQP.Basic.consume(channel, queue)

        {:ok, channel}
      end

      def handle_info(
            {:basic_deliver, payload, %{delivery_tag: tag, redelivered: redelivered} = meta},
            state
          ) do
        spawn(fn -> consume(payload, meta) end)
        :ok = AMQP.Basic.ack(state.channel, tag)

        {:noreply, state}
      rescue
        exception ->
          :ok = Basic.reject(state.channel, tag, requeue: !redelivered)
          IO.puts("Error consuming #{payload}")

          {:noreply, state}
      end

      # Confirmation sent by the broker after registering this process as a consumer
      def handle_info({:basic_consume_ok, _payload}, state) do
        {:noreply, state}
      end

      # Sent by the broker when the consumer is unexpectedly cancelled (such as after a queue deletion)
      def handle_info({:basic_cancel, _payload}, state) do
        {:stop, :normal, state}
      end

      # Confirmation sent by the broker to the consumer process after a Basic.cancel
      def handle_info({:basic_cancel_ok, _payload}, state) do
        {:noreply, state}
      end
    end
  end
end
