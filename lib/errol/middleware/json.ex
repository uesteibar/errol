defmodule Errol.Middleware.Json do
  alias Errol.Message

  @doc """
  Parses json payload in an `%Errol.Message{}` struct.

  This is thought to be used in your wiring as:

  ```elixir
  pipe_before Errol.Middleware.Json.parse/1
  ```

  This way the payload of every message consumed will be parsed before
  executing the consumer callback.


  iex> Errol.Middleware.Json.parse(%Errol.Message{payload: ~s({"userId": 1})})
  {:ok, %Errol.Message{meta: %{}, payload: %{"userId" => 1}}}
  """
  @spec parse(Message.t()) :: {:ok, Message.t()} | {:error, reason :: any()}
  def parse(%Message{payload: payload} = message) do
    case Jason.decode(payload) do
      {:ok, parsed_payload} ->
        {:ok, %Message{message | payload: parsed_payload}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
