defmodule Errol.Wiring do
  @moduledoc """
  This module allows to declare consumers for your rabbitmq routing keys
  using the following DSL.

  After your wirigin module is started (using `start_link/1`), it will
  spin up a supervised process (`Errol.Consumer.Server`) for each consumer.

  ## Example

  ```elixir
  defmodule MyWiring do
    use Wiring

    @exchange "/users"
    @exchange_type :topic

    group :account do
      pipe_before(&Errol.Middleware.Json.parse/1)

      consume("users_account_created", "users.account.created", &UsersConsumer.account_created/1)
      consume("users_account_updated", "users.account.updated", &UsersConsumer.account_updated/1)
      consume("users_profile_updated", "users.profile.updated", &UsersConsumer.profile_updated/1)
    end

    group :photos do
      consume("users_profile_photo_uploaded", "users.profile.photo.uploaded", fn message -> ... end)
    end
  end
  ```
  """

  @doc false
  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :wirings, accumulate: true)
      Module.register_attribute(__MODULE__, :group_name, [])
      @group_name :default
      Module.register_attribute(__MODULE__, :middlewares, accumulate: false)
      @middlewares %{default: %{before: [], after: [], error: []}}
      Module.register_attribute(__MODULE__, :connection, [])
      @connection []
      @before_compile unquote(__MODULE__)

      use Supervisor

      def start_link(_) do
        Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
      end
    end
  end

  @doc """
  Allows to group multiple consumer declarations. This can be useful to scope
  certain middlewares to a specific set of consumers.

  ## Example

  ```elixir
    group :account do
      # This middleware will only run for consumers on this group
      pipe_before(&Errol.Middleware.Json.parse/1)

      consume("users_account_created", "users.account.created", &UsersConsumer.account_created/1)
      consume("users_account_updated", "users.account.updated", &UsersConsumer.account_updated/1)
      consume("users_profile_updated", "users.profile.updated", &UsersConsumer.profile_updated/1)
    end

    group :photos do
      consume("users_profile_photo_uploaded", "users.profile.photo.uploaded", fn message -> ... end)
    end
  ```
  """
  defmacro group(name, do: block) do
    quote bind_quoted: [name: name, block: block] do
      @group_name name
      @middlewares put_in(@middlewares, [name], %{before: [], after: [], error: []})

      block
    end
  end

  @doc """
  Sets a middleware function that will be run **before** the message is consumed.

  ## Example

  ```elixir
  # you can pass a reference to a function
  pipe_before &Errol.Middleware.Json.parse/1

  # or an anonymous function
  pipe_before fn message -> ... end
  ```
  """
  @spec pipe_before(
          callback :: (Errol.Message.t() -> {:ok, Errol.Message.t()} | {:error, reason :: any()})
        ) :: no_return()
  defmacro pipe_before(callback) do
    quote bind_quoted: [callback: callback] do
      @middlewares put_in(
                     @middlewares,
                     [@group_name, :before],
                     get_in(@middlewares, [@group_name, :before]) ++ [callback]
                   )
    end
  end

  @doc """
  Sets a middleware function that will be run **after** the message is consumed **successfuly**.

  ## Example

  ```elixir
  # you can pass a reference to a function
  pipe_after &Notifications.notify_success/1

  # or an anonymous function
  pipe_after fn message -> ... end
  ```
  """
  @spec pipe_after(
          callback :: (Errol.Message.t() -> {:ok, Errol.Message.t()} | {:error, reason :: any()})
        ) :: no_return()
  defmacro pipe_after(callback) do
    quote bind_quoted: [callback: callback] do
      @middlewares put_in(
                     @middlewares,
                     [@group_name, :after],
                     get_in(@middlewares, [@group_name, :after]) ++ [callback]
                   )
    end
  end

  @doc """
  Sets a middleware function that will be run if either a _before middleware_ or the _consumer callback_ **fails**.

  ## Example

  ```elixir
  # you can pass a reference to a function
  pipe_error &MyErrorLogger.log/1

  # or an anonymous function
  pipe_error fn message -> ... end
  ```
  """
  @spec pipe_error(
          callback :: (Errol.Message.t() -> {:ok, Errol.Message.t()} | {:error, reason :: any()})
        ) :: no_return()
  defmacro pipe_error(callback) do
    quote bind_quoted: [callback: callback] do
      @middlewares put_in(
                     @middlewares,
                     [@group_name, :error],
                     get_in(@middlewares, [@group_name, :error]) ++ [callback]
                   )
    end
  end

  @doc """
  Declares a consumer that will be spin up as a `Errol.Consumer.Server` process
  and supervised when your wiring module is started using `start_link/1`.

  ## Example

  ```elixir
  # you can pass a reference to a function
  consume("users_profile_updated", "users.profile.updated", &UsersConsumer.profile_updated/1)

  # or an anonymous function
  consume("users_profile_photo_uploaded", "users.profile.photo.uploaded", fn message -> ... end)
  ```
  """
  @spec consume(
          queue :: String.t(),
          routing_key :: String.t(),
          callback :: (Errol.Message.t() -> Errol.Message.t())
        ) :: no_return()
  defmacro consume(queue, routing_key, callback) do
    queue = String.to_atom(queue)

    quote do
      @wirings {unquote(queue), unquote(routing_key), @group_name}
      def unquote(queue)() do
        unquote(callback)
      end
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      def init(_) do
        {:ok, connection} = AMQP.Connection.open(@connection)

        @wirings
        |> Enum.map(fn {queue, routing_key, group_name} ->
          callback = apply(__MODULE__, queue, [])

          Supervisor.child_spec(
            {
              Errol.Consumer.Server,
              [
                name: :"#{queue}_consumer",
                queue: Atom.to_string(queue),
                routing_key: routing_key,
                connection: connection,
                callback: callback,
                pipe_before: get_in(@middlewares, [group_name, :before]) || [],
                pipe_after: get_in(@middlewares, [group_name, :after]) || [],
                pipe_error: get_in(@middlewares, [group_name, :error]) || [],
                exchange: {@exchange, @exchange_type}
              ]
            },
            id: queue
          )
        end)
        |> Supervisor.init(strategy: :one_for_one)
      end
    end
  end
end
