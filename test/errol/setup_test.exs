defmodule Errol.SetupTest do
  use ExUnit.Case, async: false

  import Mock

  alias Errol.Setup

  setup do
    %{
      options: [
        connection: %AMQP.Connection{},
        queue: "setup_test_queue",
        routing_key: "setup.all",
        exchange: {"test_exchange", :topic}
      ]
    }
  end

  describe "set_consumer/1" do
    test "when AMQP.Channel.open/1 fails", %{options: options} do
      with_mock AMQP.Channel, open: fn _ -> {:error, :closing} end do
        assert {:error, :closing} = Setup.set_consumer(options)
      end
    end

    test "when AMQP.Exchange.declare/3 fails", %{options: options} do
      with_mocks [
        {AMQP.Channel, [], open: fn _ -> {:ok, %AMQP.Channel{}} end},
        {AMQP.Exchange, [], declare: fn _, _, _ -> {:error, :exchange_error} end}
      ] do
        assert {:error, :exchange_error} = Setup.set_consumer(options)
      end
    end

    test "when AMQP.Queue.declare/3 fails", %{options: options} do
      with_mocks [
        {AMQP.Channel, [], open: fn _ -> {:ok, %AMQP.Channel{}} end},
        {AMQP.Exchange, [], declare: fn _, _, _ -> :ok end},
        {AMQP.Queue, [], declare: fn _, _ -> {:error, :queue_error} end}
      ] do
        assert {:error, :queue_error} = Setup.set_consumer(options)
      end
    end

    test "when AMQP.Queue.bind/4 fails", %{options: options} do
      with_mocks [
        {AMQP.Channel, [], open: fn _ -> {:ok, %AMQP.Channel{}} end},
        {AMQP.Exchange, [], declare: fn _, _, _ -> :ok end},
        {AMQP.Queue, [], declare: fn _, _ -> {:ok, %{}} end},
        {AMQP.Queue, [], bind: fn _, _, _, _ -> {:error, :bind_error} end}
      ] do
        assert {:error, :bind_error} = Setup.set_consumer(options)
      end
    end

    test "when AMQP.Basic.consume/2 fails", %{options: options} do
      with_mocks [
        {AMQP.Channel, [], open: fn _ -> {:ok, %AMQP.Channel{}} end},
        {AMQP.Exchange, [], declare: fn _, _, _ -> :ok end},
        {AMQP.Queue, [], declare: fn _, _ -> {:ok, %{}} end},
        {AMQP.Queue, [], bind: fn _, _, _, _ -> :ok end},
        {AMQP.Basic, [], consume: fn _, _ -> {:error, :consume_error} end}
      ] do
        assert {:error, :consume_error} = Setup.set_consumer(options)
      end
    end

    test "when all is successful", %{options: options} do
      with_mocks [
        {AMQP.Channel, [], open: fn _ -> {:ok, %AMQP.Channel{}} end},
        {AMQP.Exchange, [], declare: fn _, _, _ -> :ok end},
        {AMQP.Queue, [], declare: fn _, _ -> {:ok, %{}} end},
        {AMQP.Queue, [], bind: fn _, _, _, _ -> :ok end},
        {AMQP.Basic, [], consume: fn _, _ -> {:ok, "queue_name"} end}
      ] do
        assert {:ok,
                %{
                  channel: %AMQP.Channel{},
                  connection: %AMQP.Connection{},
                  exchange: {"test_exchange", :topic},
                  queue: "setup_test_queue",
                  routing_key: "setup.all"
                }} = Setup.set_consumer(options)
      end
    end
  end
end
