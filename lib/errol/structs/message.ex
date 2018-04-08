defmodule Errol.Message do
  defstruct payload: nil, meta: %{}

  @typedoc """
  Represents a message received from RabbitMQ.
  """
  @type t :: %Errol.Message{payload: any(), meta: Map.t()}
end
