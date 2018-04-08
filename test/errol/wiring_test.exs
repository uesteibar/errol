defmodule Errol.WiringTest do
  use ExUnit.Case, async: false
  doctest Errol.Wiring

  alias Errol.{Wiring, Consumer}

  defmodule Consumer do
    def consume_success(_message), do: :ok
    def consume_all(_message), do: :ok
  end

  defmodule Middleware do
    def run_before(_message), do: :ok
    def run_after(_message), do: :ok
    def run_error(_message), do: :ok
  end

  defmodule TestWiring do
    use Wiring

    @exchange "wiring_exchange"
    @exchange_type :topic

    group :success do
      pipe_before(&Middleware.run_before/1)
      pipe_after(&Middleware.run_after/1)

      consume("message_success", "message.success", &Consumer.consume_success/1)
    end

    group :fail do
      pipe_error(&Middleware.run_error/1)

      consume("message_all", "message.*", &Consumer.consume_all/1)
      consume("message_success_anonymous", "message.success", fn message -> message end)
    end
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
               exchange: "wiring_exchange",
               callback: callback,
               pipe_before: [before_callback],
               pipe_after: [after_callback],
               pipe_error: []
             } = GenServer.call(:message_success_consumer, :config)

      assert callback == (&Consumer.consume_success/1)
      assert before_callback == (&Errol.WiringTest.Middleware.run_before/1)
      assert after_callback == (&Errol.WiringTest.Middleware.run_after/1)

      assert %{
               queue: "message_all",
               routing_key: "message.*",
               exchange: "wiring_exchange",
               callback: callback,
               pipe_before: [],
               pipe_after: [],
               pipe_error: [error_callback]
             } = GenServer.call(:message_all_consumer, :config)

      assert callback == (&Consumer.consume_all/1)
      assert error_callback == (&Errol.WiringTest.Middleware.run_error/1)

      assert %{
               queue: "message_success_anonymous",
               routing_key: "message.success",
               exchange: "wiring_exchange",
               callback: callback,
               pipe_before: [],
               pipe_after: [],
               pipe_error: [error_callback]
             } = GenServer.call(:message_success_anonymous_consumer, :config)

      assert error_callback == (&Errol.WiringTest.Middleware.run_error/1)
      assert is_function(callback)
      assert callback.(:ok) == :ok
    end
  end
end
