import Config

config :quorum,
  ecto_repos: [Quorum.Repo],
  event_stores: [Quorum.EventStore]

# Commanded application
config :quorum, Quorum.CommandedApp,
  event_store: [
    adapter: Commanded.EventStore.Adapters.EventStore,
    event_store: Quorum.EventStore
  ],
  pubsub: :local,
  registry: :local

# EventStore (Postgres-backed)
config :quorum, Quorum.EventStore,
  serializer: Commanded.Serialization.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "quorum_eventstore",
  hostname: "localhost"

# Ecto Repo (read-side projections)
config :quorum, Quorum.Repo,
  username: "postgres",
  password: "postgres",
  database: "quorum_dev",
  hostname: "localhost",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :quorum, QuorumWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: QuorumWeb.ErrorHTML, json: QuorumWeb.ErrorJSON]],
  pubsub_server: Quorum.PubSub,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev-only-replace-in-prod-with-mix-phx-gen-secret-output-at-least-64-bytes-long!",
  watchers: [],
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/quorum_web/(controllers|templates)/.*(ex|heex)$"
    ]
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
