defmodule Errol.Consumer.ServerTest do
  use ExUnit.Case, async: false
  doctest Errol.Consumer.Server

  import Mock

  alias Errol.Consumer.Server
  alias Errol.Message

  def start_server(options) do
    [
      name: :test_queue_consumer,
      queue: "test_queue",
      routing_key: "test",
      callback: fn message -> message end
    ]
    |> Keyword.merge(options)
    |> Server.start_link()
  end

  setup do
    {:ok, connection} = AMQP.Connection.open(host: "localhost")
    {:ok, channel} = AMQP.Channel.open(connection)
    exchange = {exchange_name, exchange_type} = {"/test_exchange", :topic}
    :ok = AMQP.Exchange.declare(channel, exchange_name, exchange_type)

    %{channel: channel, connection: connection, exchange: exchange, exchange_name: exchange_name}
  end

  setup %{channel: channel} do
    on_exit(fn ->
      {:ok, _} = AMQP.Queue.purge(channel, "test_queue")
    end)
  end

  describe "consuming message" do
    test "receives message with correct payload", %{
      connection: connection,
      channel: channel,
      exchange: exchange,
      exchange_name: exchange_name
    } do
      self_pid = self()

      {:ok, _pid} =
        start_server(
          connection: connection,
          exchange: exchange,
          callback: fn message ->
            send(self_pid, :assert)
            message
          end,
          routing_key: "test.success"
        )

      AMQP.Basic.publish(channel, exchange_name, "test.success", "Hello amqp world!")

      assert 1 == AMQP.Queue.consumer_count(channel, "test_queue")
      assert_receive :assert
    end
  end

  describe "middleware" do
    test "applies pipe_before and pipe_after middlewares to messages", %{
      connection: connection,
      channel: channel,
      exchange: exchange,
      exchange_name: exchange_name
    } do
      self_pid = self()

      {:ok, _pid} =
        start_server(
          connection: connection,
          exchange: exchange,
          callback: fn message ->
            send(self_pid, {:assert, message.payload})
            message
          end,
          pipe_before: [
            fn message, queue ->
              {:ok, %Message{message | payload: "replaced payload: #{queue}"}}
            end
          ],
          pipe_after: [
            fn message, queue ->
              send(self_pid, {:assert_after, message.payload, queue})
              {:ok, message}
            end
          ],
          pipe_error: [],
          routing_key: "test.middleware.pipes"
        )

      AMQP.Basic.publish(channel, exchange_name, "test.middleware.pipes", "Hello amqp world!")

      assert_receive {:assert, "replaced payload: test_queue"}
      assert_receive {:assert_after, "replaced payload: test_queue", "test_queue"}
    end

    test "applies pipe_error middlewares to messages", %{
      connection: connection,
      channel: channel,
      exchange: exchange,
      exchange_name: exchange_name
    } do
      self_pid = self()

      {:ok, _pid} =
        start_server(
          connection: connection,
          exchange: exchange,
          callback: fn _ -> raise("Error") end,
          pipe_error: [
            fn message, error ->
              send(self_pid, {:assert_error, error})
              {:ok, message}
            end
          ],
          routing_key: "test.middleware.pipe_error"
        )

      AMQP.Basic.publish(
        channel,
        exchange_name,
        "test.middleware.pipe_error",
        "Hello amqp world!"
      )

      assert_receive {:assert_error, {"test_queue", {%RuntimeError{message: "Error"}, _}}}
    end

    test "returning {:retry, reason} from pipe_error middleware retries message", %{
      connection: connection,
      channel: channel,
      exchange: exchange,
      exchange_name: exchange_name
    } do
      {:ok, pid} =
        start_server(
          connection: connection,
          exchange: exchange,
          callback: fn _ -> raise("Error") end,
          pipe_error: [
            fn message, _ ->
              if message.meta.redelivered do
                {:ok, message}
              else
                {:retry, :test}
              end
            end
          ],
          routing_key: "test.middleware.retry"
        )

      AMQP.Basic.publish(
        channel,
        exchange_name,
        "test.middleware.retry",
        "Requeue"
      )

      :erlang.trace(pid, true, [:receive])

      assert_receive {:trace, ^pid, :receive, {:basic_deliver, "Requeue", %{redelivered: false}}},
                     1000

      assert_receive {:trace, ^pid, :receive, {:basic_deliver, "Requeue", %{redelivered: true}}},
                     1000

      refute_receive {:trace, ^pid, :receive, {:basic_deliver, "Requeue", %{redelivered: true}}},
                     1000
    end

    test "returning {:reject, reason} from pipe_before middleware retries message", %{
      connection: connection,
      channel: channel,
      exchange: exchange,
      exchange_name: exchange_name
    } do
      self_pid = self()

      {:ok, pid} =
        start_server(
          connection: connection,
          exchange: exchange,
          callback: fn message ->
            send(self_pid, :assert_callback)
            message
          end,
          pipe_before: [fn _, _ -> {:reject, :test} end],
          routing_key: "test.middleware.reject_before"
        )

      AMQP.Basic.publish(
        channel,
        exchange_name,
        "test.middleware.reject_before",
        "Reject"
      )

      :erlang.trace(pid, true, [:receive])

      assert_receive {:trace, ^pid, :receive, {:basic_deliver, "Reject", %{redelivered: false}}},
                     1000

      refute_receive {:trace, ^pid, :receive, {:basic_deliver, "Requeue", %{redelivered: true}}},
                     1000
    end

    test "returning {:reject, reason} from pipe_before skips executing callback", %{
      connection: connection,
      channel: channel,
      exchange: exchange,
      exchange_name: exchange_name
    } do
      self_pid = self()

      {:ok, pid} =
        start_server(
          connection: connection,
          exchange: exchange,
          callback: fn message ->
            send(self_pid, :refute_callback)
            message
          end,
          pipe_before: [fn _, _ -> {:reject, :test} end],
          routing_key: "test.middleware.reject_before"
        )

      AMQP.Basic.publish(
        channel,
        exchange_name,
        "test.middleware.reject_before",
        "Reject"
      )

      refute_receive :refute_callback
    end

    test "failing pipe_before pipes error to error middleware", %{
      channel: channel,
      connection: connection,
      exchange: exchange,
      exchange_name: exchange_name
    } do
      self_pid = self()

      {:ok, _pid} =
        start_server(
          connection: connection,
          name: :success_queue_consumer,
          exchange: exchange,
          pipe_before: [
            fn _, _ -> {:error, :unknown} end
          ],
          pipe_error: [
            fn message, error ->
              send(self_pid, {:assert_error, error})
              {:ok, message}
            end
          ],
          routing_key: "test.middleware.failure"
        )

      AMQP.Basic.publish(
        channel,
        exchange_name,
        "test.middleware.failure",
        "Failing middleware"
      )

      assert_receive {:assert_error, {"test_queue", :unknown}}
    end

    test "failing pipe_after pipes error to error middleware", %{
      channel: channel,
      connection: connection,
      exchange: exchange,
      exchange_name: exchange_name
    } do
      self_pid = self()

      {:ok, _pid} =
        start_server(
          connection: connection,
          name: :success_queue_consumer,
          exchange: exchange,
          pipe_after: [
            fn _, _ -> {:error, :unknown} end
          ],
          pipe_error: [
            fn message, error ->
              send(self_pid, {:assert_error, error})
              {:ok, message}
            end
          ],
          routing_key: "test.middleware.failure"
        )

      AMQP.Basic.publish(
        channel,
        exchange_name,
        "test.middleware.failure",
        "Failing middleware"
      )

      assert_receive {:assert_error, {"test_queue", :unknown}}
    end

    test "pipe_before returning {:reject, reason} does not redeliver message", %{
      channel: channel,
      connection: connection,
      exchange: exchange,
      exchange_name: exchange_name
    } do
      self_pid = self()

      {:ok, pid} =
        start_server(
          connection: connection,
          name: :success_queue_consumer,
          exchange: exchange,
          pipe_before: [
            fn _, _ -> {:reject, :duplicated} end
          ],
          pipe_error: [
            fn message, error ->
              send(self_pid, {:assert_error, error})
              {:ok, message}
            end
          ],
          routing_key: "test.message.rejected"
        )

      :erlang.trace(pid, true, [:receive])

      AMQP.Basic.publish(
        channel,
        exchange_name,
        "test.message.rejected",
        "Rejected"
      )

      refute_receive {:assert_error, {"test_queue", :unknown}}

      refute_receive {:trace, ^pid, :receive, {:basic_deliver, "Rejected", %{redelivered: true}}},
                     1000
    end

    test "pipe_after returning {:reject, reason} does not reject message", %{
      channel: channel,
      connection: connection,
      exchange: exchange,
      exchange_name: exchange_name
    } do
      self_pid = self()

      {:ok, pid} =
        start_server(
          connection: connection,
          name: :success_queue_consumer,
          exchange: exchange,
          pipe_before: [
            fn _, _ -> {:reject, :duplicated} end
          ],
          pipe_error: [
            fn message, error ->
              send(self_pid, {:assert_error, error})
              {:ok, message}
            end
          ],
          routing_key: "test.message.rejected"
        )

      :erlang.trace(pid, true, [:receive])

      AMQP.Basic.publish(
        channel,
        exchange_name,
        "test.message.not_rejected",
        "Not rejected"
      )

      refute_receive {:trace, ^pid, :receive,
                      {:basic_deliver, "Not rejected", %{redelivered: true}}},
                     1000
    end
  end

  describe "unbind/1" do
    test "unbinds the queue from the exchange and stops consuming", %{
      channel: channel,
      connection: connection,
      exchange: exchange
    } do
      queue = "queue_to_unbind"

      {:ok, _} =
        start_server(
          connection: connection,
          name: :queue_to_unbind_consumer,
          queue: queue,
          exchange: exchange
        )

      assert 1 == AMQP.Queue.consumer_count(channel, queue)

      :ok = Server.unbind(:queue_to_unbind_consumer)

      assert 0 == AMQP.Queue.consumer_count(channel, queue)
    end
  end

  describe "start_link/1" do
    test "starts the server when consumer is successfully set up", %{
      connection: connection,
      channel: channel,
      exchange: exchange
    } do
      with_mock Errol.Setup,
        set_consumer: fn _ ->
          {:ok,
           %{
             channel: channel,
             queue: "test_queue",
             exchange: exchange,
             routing_key: "test.start_link.success"
           }}
        end do
        assert {:ok, _pid} = start_server(connection: connection, exchange: exchange)
      end
    end

    test "does not start the server when setup fails", %{
      connection: connection,
      exchange: exchange
    } do
      with_mock Errol.Setup, set_consumer: fn _ -> {:error, :normal} end do
        assert {:error, :normal} == start_server(connection: connection, exchange: exchange)
      end
    end
  end
end
