defmodule Errol.SetupTest do
  use ExUnit.Case, async: false
  doctest Errol.Setup

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
        assert {:error, _} = Setup.set_consumer(options)
      end
    end

    test "when AMQP.Exchange.declare/3 fails", %{options: options} do
      with_mocks [
        {AMQP.Channel, [], open: fn _ -> {:ok, %AMQP.Channel{}} end},
        {AMQP.Exchange, [], declare: fn _, _, _ -> {:error, "Super error"} end}
      ] do
        assert {:error, _} = Setup.set_consumer(options)
      end
    end

    test "when AMQP.Queue.declare/3 fails", %{options: options} do
      with_mocks [
        {AMQP.Channel, [], open: fn _ -> {:ok, %AMQP.Channel{}} end},
        {AMQP.Exchange, [], declare: fn _, _, _ -> :ok end},
        {AMQP.Queue, [], declare: fn _, _ -> {:error, "Error"} end}
      ] do
        assert {:error, _} = Setup.set_consumer(options)
      end
    end

    test "when AMQP.Queue.bind/4 fails", %{options: options} do
      with_mocks [
        {AMQP.Channel, [], open: fn _ -> {:ok, %AMQP.Channel{}} end},
        {AMQP.Exchange, [], declare: fn _, _, _ -> :ok end},
        {AMQP.Queue, [], declare: fn _, _ -> {:ok, %{}} end},
        {AMQP.Queue, [], bind: fn _, _, _, _ -> {:error, "Error"} end}
      ] do
        assert {:error, _} = Setup.set_consumer(options)
      end
    end

    test "when AMQP.Basic.consume/2 fails", %{options: options} do
      with_mocks [
        {AMQP.Channel, [], open: fn _ -> {:ok, %AMQP.Channel{}} end},
        {AMQP.Exchange, [], declare: fn _, _, _ -> :ok end},
        {AMQP.Queue, [], declare: fn _, _ -> {:ok, %{}} end},
        {AMQP.Queue, [], bind: fn _, _, _, _ -> :ok end},
        {AMQP.Basic, [], consume: fn _, _ -> {:error, "Error"} end}
      ] do
        assert {:error, _} = Setup.set_consumer(options)
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
        assert {:ok, _} = Setup.set_consumer(options)
      end
    end
  end
end
