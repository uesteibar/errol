defmodule Errol.WiringTest do
  use ExUnit.Case, async: false
  doctest Errol.Wiring

  alias Errol.{Wiring, Consumer}

  defmodule AllConsumer do
    use Consumer

    def consume(_payload, _meta), do: :ok
  end

  defmodule TestConsumer do
    use Consumer

    def consume(_payload, _meta), do: :ok
  end

  defmodule TestWiring do
    use Wiring

    @exchange "wiring_exchange"
    @exchange_type :topic

    wire("message_success", "message.success", TestConsumer)
    wire("message_all", "message.*", AllConsumer)
  end

  describe "start_link/1" do
    test "starts the consumers" do
      {:ok, connection} = AMQP.Connection.open(host: "localhost")
      {:ok, channel} = AMQP.Channel.open(connection)
      {:ok, _} = AMQP.Queue.purge(channel, "message_success")
      {:ok, _} = AMQP.Queue.purge(channel, "message_all")

      TestWiring.run()
      :timer.sleep(2000)

      assert %{queue: "message_success", routing_key: "message.success"} =
               TestConsumer.get_config()

      assert %{queue: "message_all", routing_key: "message.*"} =
               AllConsumer.get_config()
    end
  end
end
