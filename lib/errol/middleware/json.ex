defmodule Errol.Middleware.Json do
  alias Errol.Message

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
