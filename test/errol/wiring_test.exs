defmodule Errol.WiringTest do
  use ExUnit.Case, async: false
  doctest Errol.Wiring

  alias Errol.{Wiring, Consumer}

  defmodule Consumer do
    def consume_success(_message), do: :ok
    def consume_all(_message), do: :ok
  end

  defmodule TestWiring do
    use Wiring

    @exchange "wiring_exchange"
    @exchange_type :topic

    consume("message_success", "message.success", &Consumer.consume_success/1)
    consume("message_all", "message.*", &Consumer.consume_all/1)
  end

  describe "start_link/1" do
    setup do
      {:ok, connection} = AMQP.Connection.open(host: "localhost")
      {:ok, channel} = AMQP.Channel.open(connection)

      on_exit(fn ->
        {:ok, _} = AMQP.Queue.purge(channel, "message_success")
        {:ok, _} = AMQP.Queue.purge(channel, "message_all")
      end)
    end

    test "starts the consumers" do
      {:ok, _} = TestWiring.start_link(nil)
      :timer.sleep(2000)

      assert %{
               queue: "message_success",
               routing_key: "message.success",
               exchange: "wiring_exchange"
             } = GenServer.call(:message_success_consumer, :config)

      assert %{queue: "message_all", routing_key: "message.*", exchange: "wiring_exchange"} =
               GenServer.call(:message_all_consumer, :config)
    end
  end
end
