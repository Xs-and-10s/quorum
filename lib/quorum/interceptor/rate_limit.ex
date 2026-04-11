defmodule Quorum.Interceptor.RateLimit do
  @moduledoc """
  Sleeps before `exec/2` to stay under API rate limits.

  Runs inside the retry loop, so each attempt gets the delay —
  exactly what you want for 429 backoff.

  ## Usage

      defmodule MyNode do
        use Phlox.Node

        intercept Quorum.Interceptor.RateLimit, delay: 4_000

        def exec(input, params), do: ...
      end

  ## Options

    * `:delay` — milliseconds to sleep before exec (default: 4_000)
  """
  @behaviour Phlox.Interceptor

  @default_delay 4_000

  @impl true
  def before_exec(prep_res, ctx) do
    delay = ctx.interceptor_opts[:delay] || @default_delay
    Process.sleep(delay)
    {:cont, prep_res}
  end

  @impl true
  def after_exec(exec_res, _ctx) do
    {:cont, exec_res}
  end
end
