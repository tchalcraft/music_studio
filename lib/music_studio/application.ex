defmodule MusicStudio.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MusicStudioWeb.Telemetry,
      MusicStudio.Repo,
      {DNSCluster, query: Application.get_env(:music_studio, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MusicStudio.PubSub},
      # Beacon CMS — starts before the endpoint so its sites/content are ready to serve.
      {Beacon, sites: [Application.fetch_env!(:beacon, :music_studio)]},
      # Start a worker by calling: MusicStudio.Worker.start_link(arg)
      # {MusicStudio.Worker, arg},
      # Start to serve requests, typically the last entry
      MusicStudioWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MusicStudio.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MusicStudioWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
