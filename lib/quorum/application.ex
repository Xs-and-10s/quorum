defmodule Quorum.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      QuorumWeb.Telemetry,
      Quorum.Repo,
      Quorum.CommandedApp,
      Quorum.Projectors.ReviewSummary,
      {DNSCluster, query: Application.get_env(:quorum, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Quorum.PubSub},
      QuorumWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Quorum.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    QuorumWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
