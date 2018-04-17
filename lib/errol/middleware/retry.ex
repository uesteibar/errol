defmodule Errol.Middleware.Retry do
  alias Errol.Message

  @doc """
  Requeues the message if it has the `redelivered: false` header.

  This means the messages will be retryed once before being rejected.

  ```elixir
  pipe_error Errol.Middleware.Retry.basic_retry/2
  ```

      iex> Errol.Middleware.Retry.basic_retry(%Errol.Message{meta: %{redelivered: true}}, :error)
      {:ok, %Errol.Message{meta: %{redelivered: true}}}

      iex> Errol.Middleware.Retry.basic_retry(%Errol.Message{meta: %{redelivered: false}}, :error)
      {:retry, :error}
  """
  @spec basic_retry(message :: Message.t(), queue :: String.t()) ::
          {:ok, Message.t()} | {:retry, reason :: any()}
  def basic_retry(%Message{meta: %{redelivered: false}}, error) do
    {:retry, error}
  end

  def basic_retry(message, _error) do
    {:ok, message}
  end
end
