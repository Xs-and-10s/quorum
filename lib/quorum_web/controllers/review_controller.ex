defmodule QuorumWeb.ReviewController do
  use QuorumWeb, :controller

  alias Quorum.FlowSupervisor

  @doc "POST /review — start a new code review pipeline"
  def create(conn, %{"code" => code} = params) do
    language = Map.get(params, "language", "elixir")

    case FlowSupervisor.start_review(code, language) do
      {:ok, flow_id} ->
        conn
        |> put_status(200)
        |> json(%{flow_id: flow_id})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: inspect(reason)})
    end
  end

  @doc """
  GET /review/:flow_id/stream — SSE endpoint via datastar_ex.

  Subscribes to Phlox.Monitor for this flow_id, then streams
  each node completion as a Datastar signal patch + element patch.
  """
  def stream(conn, %{"flow_id" => flow_id}) do
    Phlox.Monitor.subscribe(flow_id)

    DatastarEx.stream(conn, fn stream ->
      stream_loop(stream, flow_id)
    end)
  end

  defp stream_loop(stream, flow_id) do
    review_id = flow_id

    receive do
      {:phlox_monitor, ^flow_id, {:node_complete, node_name, context}} ->
        result = extract_review(node_name, context)

        if result do
          # Dispatch to event store in real-time
          Quorum.CommandedApp.dispatch(%Quorum.Commands.RecordSpecialistReview{
            review_id: review_id,
            specialist: result.specialist,
            review: result.review,
            error: Map.get(result, :error)
          })

          # Patch the specialist card into the DOM
          html = render_specialist_card(result)

          stream
          |> DatastarEx.patch_elements("#review-results", html, mode: :append)
          |> DatastarEx.patch_signals(%{
            "#{node_name}_status" => "complete",
            "active_reviewers" => active_count(context)
          })
        end

        stream_loop(stream, flow_id)

      {:phlox_monitor, ^flow_id, {:flow_complete, context}} ->
        synthesis = Phlox.Context.get(context, :synthesis)

        if synthesis do
          # Dispatch synthesis to event store
          Quorum.CommandedApp.dispatch(%Quorum.Commands.RecordSynthesis{
            review_id: review_id,
            synthesis: synthesis.review,
            error: Map.get(synthesis, :error)
          })

          html = render_synthesis_card(synthesis)

          stream
          |> DatastarEx.patch_elements("#synthesis-result", html, mode: :inner)
          |> DatastarEx.patch_signals(%{
            "flow_status" => "complete",
            "active_reviewers" => 0
          })
        end

        # Stream ends naturally

      {:phlox_monitor, ^flow_id, {:flow_error, reason}} ->
        stream
        |> DatastarEx.patch_signals(%{
          "flow_status" => "error",
          "error_message" => inspect(reason)
        })

    after
      90_000 ->
        DatastarEx.patch_signals(stream, %{"flow_status" => "timeout"})
    end
  end

  defp extract_review(node_name, context) do
    key =
      case node_name do
        :security -> :security_review
        :logic -> :logic_review
        :style -> :style_review
        _ -> nil
      end

    if key, do: Phlox.Context.get(context, key)
  end

  defp active_count(context) do
    [:security_review, :logic_review, :style_review]
    |> Enum.count(fn key -> is_nil(Phlox.Context.get(context, key)) end)
  end

  defp render_specialist_card(%{specialist: name, review: review} = result) do
    error_class = if Map.get(result, :error), do: "error", else: ""

    """
    <article class="specialist-card #{error_class}" data-specialist="#{String.downcase(name)}">
      <header>
        <h3>#{icon_for(name)} #{name}</h3>
        <time datetime="#{result.completed_at}">#{format_time(result.completed_at)}</time>
      </header>
      <div class="review-content">
        #{md_to_html(review)}
      </div>
    </article>
    """
  end

  defp render_synthesis_card(%{review: review} = result) do
    """
    <article class="synthesis-card">
      <header>
        <h3>⚡ Synthesis</h3>
        <time datetime="#{result.completed_at}">#{format_time(result.completed_at)}</time>
      </header>
      <div class="review-content">
        #{md_to_html(review)}
      </div>
    </article>
    """
  end

  defp icon_for("Security"), do: "🛡"
  defp icon_for("Logic"), do: "🧠"
  defp icon_for("Style"), do: "✨"
  defp icon_for(_), do: "📋"

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_time(_), do: ""

  # Minimal markdown → HTML (bold, code blocks, headings).
  # In production, use Earmark or similar.
  defp md_to_html(text) do
    text
    |> String.replace(~r/```(\w*)\n(.*?)```/s, "<pre><code>\\2</code></pre>")
    |> String.replace(~r/\*\*(.*?)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/^## (.+)$/m, "<h4>\\1</h4>")
    |> String.replace(~r/^- (.+)$/m, "<li>\\1</li>")
    |> String.replace("\n\n", "</p><p>")
    |> then(&"<p>#{&1}</p>")
  end
end
