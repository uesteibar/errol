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

    test "requeues message on error", %{
      channel: channel,
      connection: connection,
      exchange: exchange,
      exchange_name: exchange_name
    } do
      {:ok, pid} =
        start_server(
          connection: connection,
          exchange: exchange,
          callback: fn _ -> raise("Error") end,
          routing_key: "test.requeue"
        )

      :erlang.trace(pid, true, [:receive])

      AMQP.Basic.publish(channel, exchange_name, "test.requeue", "Fail!")

      assert_receive {:trace, ^pid, :receive, {:basic_deliver, "Fail!", %{redelivered: true}}},
                     1000
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
          pipe_before: [fn message -> {:ok, %Message{message | payload: "replaced payload"}} end],
          pipe_after: [
            fn message ->
              send(self_pid, {:assert_after, message.payload})
              {:ok, message}
            end
          ],
          pipe_error: [],
          routing_key: "test.middleware.pipes"
        )

      AMQP.Basic.publish(channel, exchange_name, "test.middleware.pipes", "Hello amqp world!")

      assert_receive {:assert, "replaced payload"}
      assert_receive {:assert_after, "replaced payload"}
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
            fn message ->
              send(self_pid, :assert_error)
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

      assert_receive :assert_error
    end

    test "failing middleware requeues message", %{
      channel: channel,
      connection: connection,
      exchange: exchange,
      exchange_name: exchange_name
    } do
      {:ok, pid} =
        start_server(
          connection: connection,
          name: :success_queue_consumer,
          exchange: exchange,
          pipe_before: [
            fn _ -> {:error, :unknown} end
          ],
          routing_key: "test.middleware.failure"
        )

      :erlang.trace(pid, true, [:receive])

      AMQP.Basic.publish(
        channel,
        exchange_name,
        "test.middleware.failure",
        "Failing middleware"
      )

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
      queue = "queue_to_unbind"

      {:ok, _} =
        start_server(
          connection: connection,
          name: :queue_to_unbind_consumer,
          queue: queue,
          exchange: exchange
        )

      assert 1 == AMQP.Queue.consumer_count(channel, queue)

      :ok = GenServer.call(:queue_to_unbind_consumer, :unbind)

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
