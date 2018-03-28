defmodule Errol.WiringTest do
  use ExUnit.Case, async: false
  doctest Errol.Wiring

  alias Errol.{Wiring, Consumer}

  defmodule AllConsumer do
    use Consumer

    def consume(_message), do: :ok
  end

  defmodule TestConsumer do
    use Consumer

    def consume(_message), do: :ok
  end

  defmodule TestWiring do
    use Wiring

    @exchange "wiring_exchange"
    @exchange_type :topic

    consume("message_success", "message.success", TestConsumer)
    consume("message_all", "message.*", AllConsumer)
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
             } = TestConsumer.get_config()

      assert %{queue: "message_all", routing_key: "message.*", exchange: "wiring_exchange"} =
               AllConsumer.get_config()
    end
  end
end
