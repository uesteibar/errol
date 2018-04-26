defmodule Errol.MixProject do
  use Mix.Project

  @version "0.1.0"
  @github "https://github.com/uesteibar/errol"

  def project do
    [
      app: :errol,
      version: @version,
      description: "Opinionated RabbitMQ framework for Elixir",
      elixir: "~> 1.5",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      package: package(),
      docs: docs(),
      source_url: @github,
      test_coverage: [tool: Coverex.Task]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Errol.Application, []},
      extra_applications: [:logger, :amqp]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:amqp, "~> 1.0"},
      {:jason, "~> 1.0", optional: true},
      {:coverex, "~> 1.4", only: :test},
      {:mock, "~> 0.3.0", only: :test},
      {:ex_doc, "~> 0.16", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "LICENSE"
      ],
      links: %{"github" => @github},
      maintainers: ["Unai Esteibar <uesteibar@gmail.com>"],
      licenses: ["MIT"]
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      extras: ["README.md"]
    ]
  end

  defp aliases do
    [
      test: "test --cover"
    ]
  end
end
