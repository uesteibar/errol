defmodule Errol.Setup do
  @moduledoc false

  def declare_queue({channel, queue}) do
    {status, result} = AMQP.Queue.declare(channel, queue)

    {status, result, {channel, queue}}
  end

  def bind_queue({:ok, _, {channel, queue}}, exchange, routing_key: routing_key) do
    status = AMQP.Queue.bind(channel, queue, exchange, routing_key: routing_key)

    {status, nil, {channel, queue}}
  end

  def bind_queue({error, _, _} = derail, _, _), do: derail

  def set_consumer({:ok, _, {channel, queue}}) do
    {status, result} = AMQP.Basic.consume(channel, queue)

    {status, result, {channel, queue}}
  end

  def set_consumer({error, _, _} = derail), do: derail
end
