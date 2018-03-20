defmodule Errol.ConsumerTest do
  use ExUnit.Case
  doctest Errol.Consumer

  import ExUnit.CaptureIO

  defmodule TestConsumer do
    use Errol.Consumer

    def consume(payload, _meta), do: IO.puts(payload)
  end

  setup do
    {:ok, connection} = AMQP.Connection.open(host: "rabbit")
    {:ok, channel} = AMQP.Channel.open(connection)
    :ok = AMQP.Exchange.declare(channel, "test_exchange")

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

      assert_receive {:trace, ^pid, :receive, {:basic_deliver, "Hello amqp world!", _}}, 500
    end
  end

  describe "handle_info/2" do
    test "executes consume/2", %{channel: channel} do
      {:ok, _} =
        TestConsumer.start_link(
          channel: channel,
          queue: "test_queue",
          exchange: "test_exchange",
          routing_key: "test"
        )

      assert capture_io(fn ->
               TestConsumer.handle_info(
                 {:basic_deliver, "Hello world", %{delivery_tag: "tag", redelivered: false}},
                 %{channel: channel}
               )
             end) =~ ~r/Hello world/
    end
  end
end
