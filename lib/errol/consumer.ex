defmodule Errol.Consumer do
  defmacro __using__(_) do
    quote do
      use GenServer
      require Logger

      def start_link(args) do
        GenServer.start_link(__MODULE__, args, name: __MODULE__)
      end

      def init(options) do
        {:ok, channel, queue, exchange} = setup_queue(options)

        {:ok, %{channel: channel, queue: queue, exchange: exchange}}
      end

      defp setup_queue(options) do
        channel = Keyword.get(options, :channel)
        queue = Keyword.get(options, :queue)
        exchange = Keyword.get(options, :exchange, "")
        routing_key = Keyword.get(options, :routing_key, "*")

        {:ok, _} = AMQP.Queue.declare(channel, queue)
        :ok = AMQP.Queue.bind(channel, queue, exchange, routing_key: routing_key)
        {:ok, _} = AMQP.Basic.consume(channel, queue)

        {:ok, channel, queue, exchange}
      end

      def handle_info(
            {:basic_deliver, payload, %{delivery_tag: tag, redelivered: redelivered} = meta},
            state
          ) do
        consume(payload, meta)
        :ok = AMQP.Basic.ack(state.channel, tag)

        {:noreply, state}
      rescue
        exception ->
          :ok = AMQP.Basic.reject(state.channel, tag, requeue: !redelivered)
          Logger.error("Error consuming #{payload}")
          Logger.error(exception.message)

          {:noreply, state}
      end

      # Confirmation sent by the broker after registering this process as a consumer
      def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
        {:noreply, Map.put(state, :consumer_tag, consumer_tag)}
      end

      # Sent by the broker when the consumer is unexpectedly cancelled (such as after a queue deletion)
      def handle_info({:basic_cancel, _payload}, state) do
        {:stop, :normal, state}
      end

      # Confirmation sent by the broker to the consumer process after a Basic.cancel
      def handle_info({:basic_cancel_ok, _payload}, state) do
        {:noreply, state}
      end

      def handle_call(
            :unbind,
            _from,
            %{channel: channel, queue: queue, consumer_tag: consumer_tag, exchange: exchange} =
              state
          ) do
        AMQP.Queue.unbind(channel, queue, exchange)
        AMQP.Basic.cancel(channel, consumer_tag)

        {:reply, :ok, state}
      end

      def stop() do
        GenServer.call(__MODULE__, :unbind)
      end
    end
  end
end
