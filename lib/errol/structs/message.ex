defmodule Errol.Message do
  @moduledoc false

  defstruct payload: nil, meta: %{}

  @type t :: %Errol.Message{payload: any(), meta: Map.t()}
end
