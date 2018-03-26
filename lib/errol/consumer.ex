defmodule Errol.Consumer do
  defmacro __using__(_) do
    quote do
      use GenServer
      require Logger

      alias Errol.{Setup, Message}

      @callback consume(Message.t()) :: any()

      def start_link(args) do
        GenServer.start_link(__MODULE__, args, name: __MODULE__)
      end

      def init(options) do
        case setup_queue(options) do
          {:ok, channel, queue, exchange, routing_key} ->
            {:ok,
             %{
               channel: channel,
               queue: queue,
               exchange: exchange,
               routing_key: routing_key,
               running_messages: %{}
             }}

          _ ->
            {:stop, :normal, "Consumer couldn't be set up"}
        end
      end

      defp setup_queue(options) do
        channel = Keyword.get(options, :channel)
        queue = Keyword.get(options, :queue)
        exchange = Keyword.get(options, :exchange, "")
        routing_key = Keyword.get(options, :routing_key, "*")

        {status, _} =
          {channel, queue}
          |> Setup.declare_queue()
          |> Setup.bind_queue(exchange, routing_key: routing_key)
          |> Setup.set_consumer()

        {status, channel, queue, exchange, routing_key}
      end

      def handle_info(
            {:basic_deliver, payload, %{delivery_tag: tag, redelivered: redelivered} = meta},
            state
          ) do
        message = %Message{payload: payload, meta: meta}
        {pid, _ref} = spawn_monitor(fn -> consume(message) end)

        {:noreply,
         %{state | running_messages: Map.put(state.running_messages, pid, {:running, message})}}
      end

      def handle_info({:DOWN, _, :process, pid, :normal}, state) do
        {{:running, %Message{meta: %{delivery_tag: tag}}}, running_messages} =
          Map.pop(state.running_messages, pid)

        :ok = AMQP.Basic.ack(state.channel, tag)

        {:noreply, %{state | running_messages: running_messages}}
      end

      def handle_info({:DOWN, _, :process, pid, _}, state) do
        {{:running, %Message{meta: %{delivery_tag: tag, redelivered: redelivered}}},
         running_messages} = Map.pop(state.running_messages, pid)

        unless redelivered, do: Logger.error("Requeueing message: #{tag}")
        :ok = AMQP.Basic.nack(state.channel, tag, requeue: !redelivered)

        {:noreply, %{state | running_messages: running_messages}}
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

      def handle_call(:config, _from, state) do
        {:reply, state, state}
      end

      def get_config() do
        GenServer.call(__MODULE__, :config)
      end
    end
  end
end
