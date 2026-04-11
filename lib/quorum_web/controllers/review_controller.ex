defmodule QuorumWeb.ReviewController do
  use QuorumWeb, :controller

  alias Datastar.{SSE, Elements, Signals}
  alias Quorum.FlowSupervisor

  @specialist_nodes [:security, :logic, :style]

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
  each node completion as Datastar signal patches + element patches.

  Handles the race condition where the flow may partially or fully
  complete before the SSE connection opens by checking Monitor state
  immediately after subscribing.
  """
  def stream(conn, %{"flow_id" => flow_id}) do
    # Subscribe first — any events after this point land in our mailbox
    :ok = Phlox.Monitor.subscribe(flow_id)

    server = Phlox.FlowSupervisor.server(String.to_atom(flow_id))

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> send_chunked(200)

    sse = SSE.new(conn)

    # Catch up on nodes that completed before we subscribed
    {sse, emitted} = catch_up(sse, flow_id, server)

    # Check if flow is already done
    case Phlox.Monitor.get(flow_id) do
      %{status: :done} ->
        emit_synthesis(sse, server, flow_id)

      _ ->
        stream_loop(sse, flow_id, server, emitted)
    end

    # Return the chunked conn — Phoenix will close it
    conn
  end

  # Emit results for nodes that already completed before SSE connected
  defp catch_up(sse, flow_id, server) do
    case Phlox.Monitor.get(flow_id) do
      nil ->
        {sse, MapSet.new()}

      snapshot ->
        done_nodes =
          snapshot.nodes
          |> Enum.filter(fn {_id, info} -> info.status == :done end)
          |> Enum.map(fn {id, _info} -> id end)
          |> Enum.filter(&(&1 in @specialist_nodes))

        %{shared: shared} = Phlox.FlowServer.state(server)

        emitted =
          Enum.reduce(done_nodes, MapSet.new(), fn node_name, acc ->
            case extract_review(node_name, shared) do
              nil ->
                acc

              result ->
                dispatch_specialist(flow_id, result)
                html = render_specialist_card(result)

                sse
                |> Elements.patch(html, selector: "#review-results", mode: :append)
                |> Signals.patch(%{"#{node_name}_status" => "complete"})

                MapSet.put(acc, node_name)
            end
          end)

        {sse, emitted}
    end
  end

  defp stream_loop(sse, flow_id, server, emitted) do
    receive do
      {:phlox_monitor, :node_done, snapshot} ->
        node_name = snapshot.current_id

        if node_name in @specialist_nodes and node_name not in emitted do
          %{shared: shared} = Phlox.FlowServer.state(server)
          result = extract_review(node_name, shared)

          if result do
            dispatch_specialist(flow_id, result)
            html = render_specialist_card(result)

            sse
            |> Elements.patch(html, selector: "#review-results", mode: :append)
            |> Signals.patch(%{"#{node_name}_status" => "complete"})
          end

          stream_loop(sse, flow_id, server, MapSet.put(emitted, node_name))
        else
          stream_loop(sse, flow_id, server, emitted)
        end

      {:phlox_monitor, :flow_done, _snapshot} ->
        emit_synthesis(sse, server, flow_id)

      {:phlox_monitor, _event, _snapshot} ->
        # Ignore :flow_started, :node_started
        stream_loop(sse, flow_id, server, emitted)

    after
      90_000 ->
        Signals.patch(sse, %{"flow_status" => "timeout"})
    end
  end

  defp emit_synthesis(sse, server, flow_id) do
    %{shared: shared} = Phlox.FlowServer.state(server)
    synthesis = Map.get(shared, :synthesis)

    if synthesis do
      Quorum.CommandedApp.dispatch(%Quorum.Commands.RecordSynthesis{
        review_id: flow_id,
        synthesis: synthesis.review,
        error: Map.get(synthesis, :error)
      })

      synth_html = render_synthesis_card(synthesis)

      sse
      |> Elements.patch(synth_html, selector: "#synthesis-result", mode: :inner)
      |> Signals.patch(%{"flow_status" => "complete", "active_reviewers" => 0})
    end
  end

  defp dispatch_specialist(flow_id, result) do
    Quorum.CommandedApp.dispatch(%Quorum.Commands.RecordSpecialistReview{
      review_id: flow_id,
      specialist: result.specialist,
      review: result.review,
      error: Map.get(result, :error)
    })
  end

  defp extract_review(node_name, shared) do
    key =
      case node_name do
        :security -> :security_review
        :logic -> :logic_review
        :style -> :style_review
        _ -> nil
      end

    if key, do: Map.get(shared, key)
  end

  defp render_specialist_card(%{specialist: name, review: review} = result) do
    error_class = if Map.get(result, :error), do: " error", else: ""

    """
    <article class="specialist-card#{error_class}" data-specialist="#{String.downcase(name)}">
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
