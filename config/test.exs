import Config

config :quorum, Quorum.Repo,
  username: "postgres",
  password: "postgres",
  database: "quorum_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :quorum, Quorum.EventStore,
  username: "postgres",
  password: "postgres",
  database: "quorum_eventstore_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: "localhost"

config :quorum, QuorumWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test-only-secret-key-base-at-least-64-bytes-long-for-phoenix-to-be-happy-about-it",
  server: false

config :logger, level: :warning
