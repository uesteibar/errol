defmodule Errol.Behaviours.Consumer do
  @callback consume(any, Map.t) :: any()
end
