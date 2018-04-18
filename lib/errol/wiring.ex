defmodule Errol.Wiring do
  @moduledoc """
  This module allows to declare consumers for your rabbitmq routing keys
  using the following DSL.

  After your _Wiring_ module is started (using `start_link/1` that will be
  generated at compile time), it will spin up a supervised process
  (`Errol.Consumer.Server`) for each consumer.

  ## Example

  ```elixir
  defmodule MyWiring do
    use Wiring

    connection "amqp://guest:guest@localhost"

    @exchange "/users"
    @exchange_type :topic

    group :account do
      pipe_before(&Errol.Middleware.Json.parse/2)
      pipe_error(&Errol.Middleware.Retry.basic_retry/2)

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
      Module.register_attribute(__MODULE__, :middlewares, accumulate: true)
      Module.register_attribute(__MODULE__, :group_name, accumulate: false)
      @group_name :errol_default
      Module.register_attribute(__MODULE__, :connection, accumulate: false)
      @before_compile unquote(__MODULE__)

      use Supervisor

      def start_link(_) do
        Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
      end
    end
  end

  @doc """
  Sets AMQP connection configuration

  When using a keyword list, the following options can be used:
    * `:username` - The name of a user registered with the broker (defaults to \"guest\");
    * `:password` - The password of user (defaults to \"guest\");
    * `:virtual_host` - The name of a virtual host in the broker (defaults to \"/\");
    * `:host` - The hostname of the broker (defaults to \"localhost\");
    * `:port` - The port the broker is listening on (defaults to `5672`);
    * `:channel_max` - The channel_max handshake parameter (defaults to `0`);
    * `:frame_max` - The frame_max handshake parameter (defaults to `0`);
    * `:heartbeat` - The hearbeat interval in seconds (defaults to `10`);
    * `:connection_timeout` - The connection timeout in milliseconds (defaults to `60000`);
    * `:ssl_options` - Enable SSL by setting the location to cert files (defaults to `none`);
    * `:client_properties` - A list of extra client properties to be sent to the server, defaults to `[]`;
    * `:socket_options` - Extra socket options. These are appended to the default options. \
                          See http://www.erlang.org/doc/man/inet.html#setopts-2 and http://www.erlang.org/doc/man/gen_tcp.html#connect-4 \
                          for descriptions of the available options.

  To enable SSL, supply the following in the `ssl_options` field:
    * `cacertfile` - Specifies the certificates of the root Certificate Authorities that we wish to implicitly trust;
    * `certfile` - The client's own certificate in PEM format;
    * `keyfile` - The client's private key in PEM format;

  ## Example

  ```elixir
    # You can pass a url
    connection "amqp://guest:guest@localhost"

    # or a keyword list
    connection host: "rabbit", port: 5432
  ```
  """
  @spec connection(config :: String.t() | keyword()) :: no_return()
  defmacro connection(config) do
    quote do
      def connection do
        unquote(config)
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
      pipe_before(&Errol.Middleware.Json.parse/2)

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
    quote do
      @group_name unquote(name)

      unquote(block)
    end
  end

  @doc """
  Sets a middleware function that will be run **before** the message is consumed.

  ## Example

  ```elixir
  pipe_before &Errol.Middleware.Json.parse/2
  ```
  """
  @spec pipe_before(
          callback ::
            (Errol.Message.t(), queue :: String.t() ->
               {:ok, Errol.Message.t()} | {:error | :reject, reason :: any()})
        ) :: no_return()
  defmacro pipe_before(callback) do
    quote bind_quoted: [callback: callback] do
      @middlewares {@group_name, :before, callback}
    end
  end

  @doc """
  Sets a middleware function that will be run **after** the message is consumed **successfuly**.

  ## Example

  ```elixir
  pipe_after &Notifications.notify_success/2
  ```
  """
  @spec pipe_after(
          callback ::
            (Errol.Message.t(), queue :: String.t() ->
               {:ok, Errol.Message.t()} | {:error, reason :: any()})
        ) :: no_return()
  defmacro pipe_after(callback) do
    quote bind_quoted: [callback: callback] do
      @middlewares {@group_name, :after, callback}
    end
  end

  @doc """
  Sets a middleware function that will be run if either a _before_ or
  _after middleware_ or the _consumer callback_ **fails**.

  If the function returns `{:retry, reason}`, the message will be retried.
  This way you can control your own retry policy.

  ## Example

  ```elixir
  pipe_error &MyErrorLogger.log/2
  ```
  """
  @spec pipe_error(
          callback ::
            (Errol.Message.t(), {queue :: String.t(), error :: any()} ->
               {:ok, Errol.Message.t()} | {:error | :retry, reason :: any()})
        ) :: no_return()
  defmacro pipe_error(callback) do
    quote bind_quoted: [callback: callback] do
      @middlewares {@group_name, :error, callback}
    end
  end

  @doc """
  Declares a consumer that will be spin up as a `Errol.Consumer.Server` process
  and supervised when your wiring module is started using `start_link/1`.

  Messages will be requeued one time on failure.

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
      defp get_middlewares_for(group_name, scope) do
        for {^group_name, ^scope, fun} <- @middlewares, do: fun
      end

      def init(_) do
        {:ok, connection} = AMQP.Connection.open(connection)

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
                pipe_before:
                  get_middlewares_for(:errol_default, :before) ++
                    get_middlewares_for(group_name, :before),
                pipe_after:
                  get_middlewares_for(:errol_default, :after) ++
                    get_middlewares_for(group_name, :after),
                pipe_error:
                  get_middlewares_for(:errol_default, :error) ++
                    get_middlewares_for(group_name, :error),
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
