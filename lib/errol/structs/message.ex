defmodule Errol.Message do
  defstruct payload: nil, meta: %{}

  @type t :: %Errol.Message{payload: any(), meta: Map.t()}
end
