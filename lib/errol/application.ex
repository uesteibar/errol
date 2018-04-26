defmodule Errol.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      worker(Errol.Monitoring.RabbitMQ, [])
    ]

    opts = [strategy: :one_for_one, name: Errol.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
