defmodule Errol.Consumer.ServerTest do
  use ExUnit.Case, async: false
  doctest Errol.Consumer.Server

  alias Errol.Consumer.Server

  defmodule TestConsumer do
    def consume(%Errol.Message{payload: payload} = message) do
      IO.puts(payload)
      message
    end
  end

  defmodule FailConsumer do
    def consume(%Errol.Message{}), do: raise("Error")
  end

  setup do
    {:ok, connection} = AMQP.Connection.open(host: "localhost")
    {:ok, channel} = AMQP.Channel.open(connection)
    exchange = {exchange_name, exchange_type} = {"test_exchange", :topic}
    :ok = AMQP.Exchange.declare(channel, exchange_name, exchange_type)

    %{channel: channel, connection: connection, exchange: exchange}
  end

  describe "receiving message" do
    setup %{channel: channel} do
      on_exit(fn ->
        {:ok, _} = AMQP.Queue.purge(channel, "test_queue")
      end)
    end

    test "receives message with correct payload", %{
      connection: connection,
      channel: channel,
      exchange: exchange
    } do
      self_pid = self()

      {:ok, _pid} =
        Server.start_link(
          connection: connection,
          name: :test_queue_consumer,
          queue: "test_queue",
          exchange: exchange,
          callback: fn message ->
            send(self_pid, :assert)
            message
          end,
          routing_key: "test"
        )

      AMQP.Basic.publish(channel, "test_exchange", "test", "Hello amqp world!")

      assert 1 == AMQP.Queue.consumer_count(channel, "test_queue")
      assert_receive :assert
    end

    test "requeues message on error", %{
      channel: channel,
      connection: connection,
      exchange: exchange
    } do
      {:ok, pid} =
        Server.start_link(
          connection: connection,
          name: :fail_queue_consumer,
          queue: "test_queue",
          exchange: exchange,
          callback: &FailConsumer.consume/1,
          routing_key: "test.fail"
        )

      :timer.sleep(1000)

      :erlang.trace(pid, true, [:receive])

      AMQP.Basic.publish(channel, "test_exchange", "test.fail", "Fail!")

      assert_receive {:trace, ^pid, :receive, {:basic_deliver, "Fail!", %{redelivered: true}}},
                     1000
    end

    test "applies pipe_before and pipe_after middlewares to messages", %{
      connection: connection,
      channel: channel,
      exchange: exchange
    } do
      self_pid = self()

      {:ok, _pid} =
        Server.start_link(
          connection: connection,
          name: :success_queue_consumer,
          queue: "test_queue",
          exchange: exchange,
          callback: fn message ->
            send(self_pid, {:assert, message.payload})
            message
          end,
          pipe_before: [
            fn message ->
              {:ok, %Errol.Message{message | payload: "replaced payload"}}
            end
          ],
          pipe_after: [
            fn message ->
              send(self_pid, {:assert_after, message.payload})
              {:ok, message}
            end
          ],
          routing_key: "test.success"
        )

      AMQP.Basic.publish(channel, "test_exchange", "test.success", "Hello amqp world!")

      assert_receive {:assert, "replaced payload"}
      assert_receive {:assert_after, "replaced payload"}
    end

    test "applies pipe_error middlewares to messages", %{
      connection: connection,
      channel: channel,
      exchange: exchange
    } do
      self_pid = self()

      {:ok, _pid} =
        Server.start_link(
          connection: connection,
          name: :success_queue_consumer,
          queue: "test_queue",
          exchange: exchange,
          callback: &FailConsumer.consume/1,
          pipe_error: [
            fn message ->
              send(self_pid, :assert_error)
              {:ok, message}
            end
          ],
          routing_key: "test.success"
        )

      AMQP.Basic.publish(channel, "test_exchange", "test.success", "Hello amqp world!")

      assert_receive :assert_error
    end

    test "failing middleware requeues message", %{
      channel: channel,
      connection: connection,
      exchange: exchange
    } do
      {:ok, pid} =
        Server.start_link(
          connection: connection,
          name: :success_queue_consumer,
          queue: "test_queue",
          exchange: exchange,
          callback: &TestConsumer.consume/1,
          pipe_before: [
            fn _ -> {:error, :unknown} end
          ],
          routing_key: "test.success"
        )

      :timer.sleep(1000)

      :erlang.trace(pid, true, [:receive])

      AMQP.Basic.publish(channel, "test_exchange", "test.success", "Failing middleware")

      assert_receive {:trace, ^pid, :receive,
                      {:basic_deliver, "Failing middleware", %{redelivered: true}}},
                     1000
    end
  end

  describe ":unbind" do
    test "unbinds the queue from the exchange and stops consuming", %{
      channel: channel,
      connection: connection,
      exchange: exchange
    } do
      {:ok, _} =
        Server.start_link(
          connection: connection,
          name: :queue_to_unbind_consumer,
          queue: "test_queue",
          exchange: exchange,
          callback: &TestConsumer.consume/1,
          routing_key: "test"
        )

      assert 1 == AMQP.Queue.consumer_count(channel, "test_queue")

      :ok = GenServer.call(:queue_to_unbind_consumer, :unbind)

      assert 0 == AMQP.Queue.consumer_count(channel, "test_queue")
    end
  end

  describe "start_link/1" do
    test "returns :ok when consumer is successfully set up", %{
      connection: connection,
      exchange: exchange
    } do
      assert {:ok, _pid} =
               Server.start_link(
                 connection: connection,
                 name: :success_queue_consumer,
                 queue: "test_queue",
                 exchange: exchange,
                 callback: &TestConsumer.consume/1,
                 routing_key: "test.success"
               )
    end
  end
end
