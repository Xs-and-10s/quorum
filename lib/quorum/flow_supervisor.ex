defmodule Quorum.FlowSupervisor do
  @moduledoc """
  Thin wrapper around Phlox.FlowSupervisor for starting code review flows.

  Handles Commanded event dispatch for ReviewRequested, then delegates
  flow execution to Phlox's built-in OTP supervision.

  Uses Simplect middleware at :full level to compress LLM output tokens
  and stay under Groq's free-tier 12K TPM limit.
  """

  @doc "Start a new code review flow. Returns {:ok, flow_id}."
  def start_review(code, language) do
    flow_id = generate_flow_id()
    flow = Quorum.Pipeline.CodeReview.build()
    name = String.to_atom(flow_id)

    shared = %{
      code: code,
      language: language,
      flow_id: flow_id,
      phlox_flow_id: flow_id
    }

    # Record the review request as an event
    Quorum.CommandedApp.dispatch(%Quorum.Commands.RequestReview{
      review_id: flow_id,
      code: code,
      language: language
    })

    case Phlox.FlowSupervisor.start_flow(name, flow, shared,
           middlewares: [Phlox.Middleware.Simplect],
           metadata: %{simplect: :full}
         ) do
      {:ok, _pid} ->
        server = Phlox.FlowSupervisor.server(name)
        Task.start(fn -> Phlox.FlowServer.run(server) end)
        {:ok, flow_id}

      error ->
        error
    end
  end

  defp generate_flow_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
