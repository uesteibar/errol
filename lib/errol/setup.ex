defmodule Errol.Setup do
  @moduledoc false

  def open_channel({connection, queue, exchange, exchange_type}) do
    case AMQP.Channel.open(connection) do
      {:ok, channel} ->
        :ok = AMQP.Exchange.declare(channel, exchange, exchange_type)
        {channel, queue}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def declare_queue({channel, queue}) do
    case AMQP.Queue.declare(channel, queue) do
      {:ok, _} ->
        {:ok, {channel, queue}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def declare_queue({:error, _, _} = derail, _, _), do: derail

  def bind_queue({:ok, {channel, queue}}, exchange, routing_key: routing_key) do
    case AMQP.Queue.bind(channel, queue, exchange, routing_key: routing_key) do
      :ok ->
        {:ok, {channel, queue}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def bind_queue({:error, _, _} = derail, _, _), do: derail

  def set_consumer({:ok, {channel, queue}}) do
    case AMQP.Basic.consume(channel, queue) do
      {:ok, _} ->
        {:ok, {channel, queue}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def set_consumer({:error, _, _} = derail), do: derail
end
