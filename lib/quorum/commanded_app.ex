defmodule Quorum.CommandedApp do
  use Commanded.Application, otp_app: :quorum

  router(Quorum.Router)
end
