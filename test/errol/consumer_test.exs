defmodule Errol.ConsumerTest do
  use ExUnit.Case, async: false
  doctest Errol.Consumer

  import ExUnit.CaptureIO

  defmodule TestConsumer do
    use Errol.Consumer

    def consume(payload, _meta) do
      IO.puts(payload)
    end
  end

  defmodule FailConsumer do
    use Errol.Consumer

    def consume(_payload, _meta), do: raise("Error")
  end

  setup do
    {:ok, connection} = AMQP.Connection.open(host: "localhost")
    {:ok, channel} = AMQP.Channel.open(connection)
    :ok = AMQP.Exchange.declare(channel, "test_exchange", :topic)
    {:ok, _} = AMQP.Queue.purge(channel, "test_queue")
    {:ok, _} = AMQP.Queue.purge(channel, "fail_queue")
    {:ok, _} = AMQP.Queue.purge(channel, "queue_to_unbind")

    %{channel: channel}
  end

  describe "consume/2" do
    test "receives message with correct payload", %{channel: channel} do
      {:ok, pid} =
        TestConsumer.start_link(
          channel: channel,
          queue: "test_queue",
          exchange: "test_exchange",
          routing_key: "test"
        )

      :timer.sleep(1000)

      :erlang.trace(pid, true, [:receive])

      AMQP.Basic.publish(channel, "test_exchange", "test", "Hello amqp world!")

      assert 1 == AMQP.Queue.consumer_count(channel, "test_queue")
      assert_receive {:trace, ^pid, :receive, {:basic_deliver, "Hello amqp world!", _}}, 500
    end

    test "requeues message on error", %{channel: channel} do
      {:ok, pid} =
        FailConsumer.start_link(
          channel: channel,
          queue: "fail_queue",
          exchange: "test_exchange",
          routing_key: "test.fail"
        )

      :timer.sleep(1000)

      :erlang.trace(pid, true, [:receive])

      AMQP.Basic.publish(channel, "test_exchange", "test.fail", "Fail!")

      assert_receive {:trace, ^pid, :receive, {:basic_deliver, "Fail!", %{redelivered: true}}},
                     1000
    end
  end

  describe "handle_info/2" do
    test "executes consume/2", %{channel: channel} do
      self_pid = self()

      capture_io(fn ->
        Process.group_leader(self(), self_pid)

        TestConsumer.handle_info(
          {:basic_deliver, "Hello world", %{delivery_tag: "tag", redelivered: false}},
          %{channel: channel, running_messages: %{}}
        )
      end)

      assert_receive {:io_request, _, _, {:put_chars, :unicode, "Hello world\n"}}, 1000
    end
  end

  describe "stop/0" do
    test "unbinds the queue from the exchange and stops consuming", %{channel: channel} do
      {:ok, _} =
        TestConsumer.start_link(
          channel: channel,
          queue: "queue_to_unbind",
          exchange: "test_exchange",
          routing_key: "test"
        )

      assert 1 == AMQP.Queue.consumer_count(channel, "queue_to_unbind")

      :ok = TestConsumer.stop()

      assert 0 == AMQP.Queue.consumer_count(channel, "queue_to_unbind")
    end
  end

  describe "start_link/1" do
    test "returns :ok when consumer is successfully set up", %{channel: channel} do
      assert {:ok, _pid} =
               TestConsumer.start_link(
                 channel: channel,
                 queue: "success_queue",
                 exchange: "test_exchange",
                 routing_key: "test.success"
               )
    end
  end
end
