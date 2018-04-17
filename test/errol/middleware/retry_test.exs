defmodule Errol.Middleware.RetryTest do
  use ExUnit.Case, async: true
  doctest Errol.Middleware.Retry

  alias Errol.Message
  alias Errol.Middleware.Retry

  describe "retry_once/2" do
    test "returns {:ok, message} when message is already redelivered" do
      message = %Message{meta: %{redelivered: true}}

      assert {:ok, ^message} = Retry.basic_retry(message, :error)
    end

    test "returns {:retry, :redeliver} when message is not redelivered" do
      message = %Message{meta: %{redelivered: false}}

      assert {:retry, :error} = Retry.basic_retry(message, :error)
    end
  end
end
