defmodule Errol.Consumer.Server do
  @moduledoc """
  `GenServer` that creates a `queue`, binds it to a given `routing_key` and
   consumes messages from that queue.

  The preferred way of spinning up consumer this is through `Errol.Wiring.consume/3`
  when declaring your _Wiring_, but you can also use this module to start them on your own.

  ## Examples

      iex> {:ok, connection} = AMQP.Connection.open()
      iex> {:ok, _pid} = Errol.Consumer.Server.start_link(name: :queue_consumer, queue: "queue_name", routing_key: "my.routing.key", callback: fn _message -> :ok end, exchange: {"/", :topic}, connection: connection)
      iex> Errol.Consumer.Server.unbind(:queue_consumer)
      :ok
  """

  use GenServer
  require Logger

  alias Errol.{Setup, Message}

  @doc """
  Creates a `queue`, binds it to a given `routing_key` and
  Starts a process that consumes messages from that queue.

  It expects the following arguments:

    - `name` A name for the process.
    - `queue` A name for the queue that will be created.
    - `routing_key`: A rabbitmq compatible routing key (e.g. `my.routing.key`).
    - `callback`: A function with arity of 1.
    - `exchange`: The expected format is `{exchange_path, exchange_type}`. `exchange_type` can be `:topic`, `:fanout` or `:direct`.
    - `connection`: You can create a connection through `AMQP.Connection.open/1`.
  """
  @spec start_link(options :: keyword()) :: {:ok, pid()} | {:error, reason :: atom()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: Keyword.get(args, :name))
  end

  @doc false
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

  @doc false
  defp apply_middlewares(message, data, middlewares) do
    Enum.reduce(middlewares, {:ok, message}, fn middleware, {status, message} ->
      if status == :ok do
        middleware.(message, data)
      else
        {status, message}
      end
    end)
  end

  @doc false
  def handle_info(
        {:basic_deliver, payload, meta},
        %{callback: callback, pipe_before: pipe_before, pipe_after: pipe_after, queue: queue} =
          state
      ) do
    message = %Message{payload: payload, meta: meta}
    monitor_pid = self()

    {pid, _ref} =
      spawn_monitor(fn ->
        result =
          case apply_middlewares(message, queue, pipe_before) do
            {:ok, message} ->
              with message <- callback.(message),
                   {:ok, message} <- apply_middlewares(message, queue, pipe_after) do
                {:ok, message}
              else
                {:error, reason} ->
                  {:error, reason}
              end

            {result, reason} ->
              {result, reason}
          end

        with {:ok, message} <- apply_middlewares(message, queue, pipe_before),
             message <- callback.(message),
             {:ok, message} <- apply_middlewares(message, queue, pipe_after) do
          {:ok, message}
        end

        GenServer.cast(monitor_pid, {:processed, {result, self()}})
      end)

    {:noreply,
     %{state | running_messages: Map.put(state.running_messages, pid, {:running, message})}}
  end

  @doc false
  def handle_info({:DOWN, _, :process, _, :normal}, state), do: {:noreply, state}

  @doc false
  def handle_info({:DOWN, _, :process, pid, exception}, state) do
    GenServer.cast(self(), {:processed, {{:error, exception}, pid}})

    {:noreply, state}
  end

  # Confirmation sent by the broker after registering this process as a consumer
  @doc false
  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
    {:noreply, Map.put(state, :consumer_tag, consumer_tag)}
  end

  # Sent by the broker when the consumer is unexpectedly cancelled (such as after a queue deletion)
  @doc false
  def handle_info({:basic_cancel, _payload}, state) do
    {:stop, :normal, state}
  end

  # Confirmation sent by the broker to the consumer process after a Basic.cancel
  @doc false
  def handle_info({:basic_cancel_ok, _payload}, state) do
    {:noreply, state}
  end

  @doc false
  def handle_call(
        :unbind,
        _from,
        %{channel: channel, queue: queue, consumer_tag: consumer_tag, exchange: exchange} = state
      ) do
    AMQP.Queue.unbind(channel, queue, exchange)
    AMQP.Basic.cancel(channel, consumer_tag)

    {:reply, :ok, state}
  end

  @doc false
  def handle_call(:config, _from, state) do
    {:reply, state, state}
  end

  @doc false
  def handle_cast({:processed, {{:ok, %Message{meta: %{delivery_tag: tag}}}, pid}}, state) do
    {_, running_messages} = Map.pop(state.running_messages, pid)

    :ok = AMQP.Basic.ack(state.channel, tag)

    {:noreply, %{state | running_messages: running_messages}}
  end

  @doc false
  def handle_cast({:processed, {{:reject, reason}, pid}}, state) do
    {{:running, %Message{meta: %{delivery_tag: tag}} = message}, running_messages} =
      Map.pop(state.running_messages, pid)

    log_error(:reject, message, state.queue, reason)

    :ok = AMQP.Basic.reject(state.channel, tag, requeue: false)

    {:noreply, %{state | running_messages: running_messages}}
  end

  @doc false
  def handle_cast({:processed, {{:error, error}, pid}}, state) do
    new_state = processing_failed(pid, error, state)

    {:noreply, new_state}
  end

  @doc false
  def processing_failed(
        pid,
        error,
        %{pipe_error: pipe_error, queue: queue, channel: channel} = state
      ) do
    {{:running, %Message{meta: %{delivery_tag: tag, redelivered: redelivered}} = message},
     running_messages} = Map.pop(state.running_messages, pid)

    {status, _} = apply_middlewares(message, {queue, error}, pipe_error)

    log_error(status, message, queue, error)

    :ok = AMQP.Basic.reject(channel, tag, requeue: status == :retry)

    %{state | running_messages: running_messages}
  end

  defp log_error(reason, message, queue, error) do
    Logger.error("""
    #{error_header(reason)}

      * message: #{inspect(message)}
      * queue:   #{queue}
      * error:   #{inspect(error)}
    """)
  end

  defp error_header(:retry), do: "Retrying message"
  defp error_header(_), do: "Rejecting message"

  @doc """
  Unbinds the given process from the rabbitmq queue it is subscribed to and
  shuts down the process.
  """
  @spec unbind(consume_name :: atom() | pid()) :: :ok
  def unbind(consumer_name) do
    GenServer.call(consumer_name, :unbind)
  end
end
