defmodule Errol.Setup do
  @moduledoc false

  def set_consumer(options) do
    {:ok,
     %{
       connection: Keyword.get(options, :connection),
       queue: Keyword.get(options, :queue),
       exchange: Keyword.get(options, :exchange),
       routing_key: Keyword.get(options, :routing_key, "*"),
       channel: nil
     }}
    |> open_channel()
    |> declare_exchange()
    |> declare_queue()
    |> bind_queue()
    |> connect_consumer()
  end

  defp open_channel({:ok, %{connection: connection} = options}) do
    case AMQP.Channel.open(connection) do
      {:ok, channel} ->
        {:ok, %{options | channel: channel}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp declare_exchange({:ok, %{channel: channel, exchange: {exchange, exchange_type}} = options}) do
    case AMQP.Exchange.declare(channel, exchange, exchange_type) do
      :ok ->
        {:ok, options}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp declare_exchange({:error, _} = derail), do: derail

  defp declare_queue({:ok, %{channel: channel, queue: queue} = options}) do
    case AMQP.Queue.declare(channel, queue) do
      {:ok, _} ->
        {:ok, options}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp declare_queue({:error, _} = derail), do: derail

  defp bind_queue(
         {:ok,
          %{channel: channel, queue: queue, exchange: {exchange, _}, routing_key: routing_key} =
            options}
       ) do
    case AMQP.Queue.bind(channel, queue, exchange, routing_key: routing_key) do
      :ok ->
        {:ok, options}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp bind_queue({:error, _} = derail), do: derail

  defp connect_consumer({:ok, %{channel: channel, queue: queue} = options}) do
    case AMQP.Basic.consume(channel, queue) do
      {:ok, _} ->
        {:ok, options}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp connect_consumer({:error, _} = derail), do: derail
end
