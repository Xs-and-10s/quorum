defmodule Quorum.Repo do
  use Ecto.Repo,
    otp_app: :quorum,
    adapter: Ecto.Adapters.Postgres
end
