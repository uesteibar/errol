defmodule Errol.Middleware.JsonTest do
  use ExUnit.Case, async: true
  doctest Errol.Middleware.Json

  alias Errol.Message
  alias Errol.Middleware.Json

  describe "parse/1" do
    test "returns Errol.Message with parsed payload" do
      message = %Message{payload: ~s({"userId": 1})}

      assert {:ok, %Message{payload: %{"userId" => 1}}} = Json.parse(message)
    end

    test "for non json input returns {:error, reason} tuple" do
      message = %Message{payload: ~s({invalid_json})}

      assert {:error, _} = Json.parse(message)
    end
  end
end
