defmodule Errol.Consumer.Server do
  use GenServer
  require Logger

  alias Errol.{Setup, Message}

  @spec start_link(options :: keyword()) :: {:ok, pid()} | {:error, reason :: atom()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: Keyword.get(args, :name))
  end

  def init(options) do
    case Setup.set_consumer(options) do
      {:ok,
       %{
         channel: channel,
         queue: queue,
         exchange: {exchange, _},
         routing_key: routing_key
       }} ->
        {:ok,
         %{
           channel: channel,
           queue: queue,
           exchange: exchange,
           routing_key: routing_key,
           callback: Keyword.get(options, :callback),
           pipe_before: Keyword.get(options, :pipe_before, []),
           pipe_after: Keyword.get(options, :pipe_after, []),
           pipe_error: Keyword.get(options, :pipe_error, []),
           running_messages: %{}
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp apply_middlewares(message, middlewares) do
    Enum.reduce(middlewares, {:ok, message}, fn middleware, {status, message} ->
      if status == :ok do
        middleware.(message)
      else
        {status, message}
      end
    end)
  end

  def handle_info(
        {:basic_deliver, payload, meta},
        %{callback: callback, pipe_before: pipe_before, pipe_after: pipe_after} = state
      ) do
    message = %Message{payload: payload, meta: meta}
    monitor_pid = self()

    {pid, _ref} =
      spawn_monitor(fn ->
        {status, _} =
          with {:ok, message} <- apply_middlewares(message, pipe_before),
               message <- callback.(message),
               {:ok, message} <- apply_middlewares(message, pipe_after) do
            {:ok, message}
          end

        GenServer.cast(monitor_pid, {:processed, {status, self()}})
      end)

    {:noreply,
     %{state | running_messages: Map.put(state.running_messages, pid, {:running, message})}}
  end

  def handle_info({:DOWN, _, :process, _, :normal}, state), do: {:noreply, state}

  def handle_info({:DOWN, _, :process, pid, _}, state) do
    GenServer.cast(self(), {:processed, {:error, pid}})

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
        %{channel: channel, queue: queue, consumer_tag: consumer_tag, exchange: exchange} = state
      ) do
    AMQP.Queue.unbind(channel, queue, exchange)
    AMQP.Basic.cancel(channel, consumer_tag)

    {:reply, :ok, state}
  end

  def handle_call(:config, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:processed, {:ok, pid}}, state) do
    {{:running, %Message{meta: %{delivery_tag: tag}}}, running_messages} =
      Map.pop(state.running_messages, pid)

    :ok = AMQP.Basic.ack(state.channel, tag)

    {:noreply, %{state | running_messages: running_messages}}
  end

  def handle_cast({:processed, {:error, pid}}, state) do
    new_state = processing_failed(pid, state)

    {:noreply, new_state}
  end

  def processing_failed(pid, %{pipe_error: pipe_error} = state) do
    {{:running, %Message{meta: %{delivery_tag: tag, redelivered: redelivered}} = message},
     running_messages} = Map.pop(state.running_messages, pid)

    apply_middlewares(message, pipe_error)

    unless redelivered, do: Logger.error("Requeueing message: #{tag}")
    :ok = AMQP.Basic.nack(state.channel, tag, requeue: !redelivered)

    %{state | running_messages: running_messages}
  end

  @spec unbind(consume_name :: atom()) :: :ok
  def unbind(consumer_name) do
    GenServer.call(consumer_name, :unbind)
  end
end
