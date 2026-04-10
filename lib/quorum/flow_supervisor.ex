defmodule Quorum.FlowSupervisor do
  @moduledoc """
  DynamicSupervisor for Phlox flow executions.

  Each code review runs as a supervised task, tracked by flow_id.
  Phlox.Monitor broadcasts node completions for SSE streaming.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start a new code review flow. Returns {:ok, flow_id}."
  def start_review(code, language) do
    flow_id = generate_flow_id()
    graph = Quorum.Pipeline.CodeReview.build()

    initial_state = %{
      code: code,
      language: language
    }

    task_spec = %{
      id: flow_id,
      start: {Task, :start_link, [fn -> run_flow(flow_id, graph, initial_state) end]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(__MODULE__, task_spec) do
      {:ok, _pid} -> {:ok, flow_id}
      error -> error
    end
  end

  defp run_flow(flow_id, graph, initial_state) do
    review_id = flow_id

    # Record the review request as an event
    Quorum.CommandedApp.dispatch(%Quorum.Commands.RequestReview{
      review_id: review_id,
      code: initial_state.code,
      language: initial_state.language
    })

    # Register this flow for monitoring
    Phlox.Monitor.register(flow_id)

    context =
      Phlox.Context.new(initial_state)
      |> Phlox.Context.put(:flow_id, flow_id)
      |> Phlox.Context.put(:review_id, review_id)

    case Phlox.execute(graph, context, monitor: flow_id) do
      {:ok, final_context} ->
        Phlox.Monitor.broadcast(flow_id, {:flow_complete, final_context})

      {:error, reason} ->
        Phlox.Monitor.broadcast(flow_id, {:flow_error, reason})
    end
  end

  defp generate_flow_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
