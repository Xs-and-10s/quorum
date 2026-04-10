defmodule Quorum.MixProject do
  use Mix.Project

  def project do
    [
      app: :quorum,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Quorum.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},

      # Postgres + Ecto
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},

      # Event Sourcing
      {:commanded, "~> 1.4"},
      {:commanded_eventstore_adapter, "~> 1.4"},
      {:commanded_ecto_projections, "~> 1.3"},
      {:eventstore, "~> 1.4"},

      # Orchestration + Validation
      {:phlox, "~> 0.3.0"},
      {:gladius, "~> 0.6.0"},

      # Datastar SSE
      {:datastar_ex, "~> 0.1"},

      # HTTP client for Groq
      {:req, "~> 0.5"},

      # Static analysis (dev/test)
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "event_store.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "event_store.setup": ["event_store.create", "event_store.init"],
      "assets.deploy": ["phx.digest"]
    ]
  end
end
