defmodule Errol.Monitoring.RabbitMQ do
  @moduledoc false

  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    {:ok, %{}}
  end

  def handle_call({:monitor, {connection_pid, process_name}}, _from, state) do
    Process.monitor(connection_pid)
    process_names = process_names_for_connection(connection_pid, state)
    new_state = Map.put(state, connection_pid, process_names ++ [process_name])

    {:reply, :ok, new_state}
  end

  defp process_names_for_connection(pid, state) do
    case Map.get(state, pid) do
      nil ->
        []

      names ->
        names
    end
  end

  def handle_info({:DOWN, _, :process, connection_pid, _}, state) do
    process_names = process_names_for_connection(connection_pid, state)
    {_, new_state} = Map.pop(state, connection_pid)

    Enum.each(process_names, fn process_name ->
      process_name
      |> Process.whereis()
      |> IO.inspect()
      |> Process.exit(:kill)
    end)

    {:noreply, new_state}
  end

  def monitor(connection_pid, process_name) do
    GenServer.call(__MODULE__, {:monitor, {connection_pid, process_name}})
  end
end
