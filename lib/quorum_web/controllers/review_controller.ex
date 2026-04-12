defmodule QuorumWeb.ReviewController do
  use QuorumWeb, :controller

  alias Datastar.{SSE, Elements, Signals, Script}
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
  """
  def stream(conn, %{"flow_id" => flow_id}) do
    :ok = Phlox.Monitor.subscribe(flow_id)

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> send_chunked(200)

    sse = SSE.new(conn)

    # Clear any existing cards from a previous SSE connection (prevents duplicates)
    sse_send(sse, fn ->
      sse
      |> Elements.patch("", selector: "#review-results", mode: :inner)
      |> Elements.patch("", selector: "#synthesis-result", mode: :inner)
    end)

    # Send skeleton cards
    sse_send(sse, fn ->
      for node_name <- @specialist_nodes do
        Elements.patch(sse, render_skeleton_card(node_name),
          selector: "#review-results", mode: :append)
      end

      Elements.patch(sse, render_skeleton_synthesis(),
        selector: "#synthesis-result", mode: :inner)
    end)

    # Catch up on already-completed nodes
    {sse, emitted} = catch_up(sse, flow_id)

    # Check if flow is already done
    case Phlox.Monitor.get(flow_id) do
      %{status: :done, shared: shared} ->
        emit_remaining_specialists(sse, flow_id, shared, emitted)
        emit_synthesis(sse, flow_id, shared)

      _ ->
        stream_loop(sse, flow_id, emitted)
    end

    halt(conn)
  end

  defp catch_up(sse, flow_id) do
    case Phlox.Monitor.get(flow_id) do
      nil ->
        {sse, MapSet.new()}

      %{shared: nil} ->
        {sse, MapSet.new()}

      %{nodes: nodes, shared: shared} ->
        done_specialists =
          nodes
          |> Enum.filter(fn {id, info} -> id in @specialist_nodes and info.status == :done end)
          |> Enum.map(fn {id, _} -> id end)

        emitted =
          Enum.reduce(done_specialists, MapSet.new(), fn node_name, acc ->
            case extract_review(node_name, shared) do
              nil -> acc
              result ->
                dispatch_specialist(flow_id, result)
                emit_specialist_card(sse, node_name, result)
                MapSet.put(acc, node_name)
            end
          end)

        maybe_all_specialists_done(sse, emitted)
        {sse, emitted}
    end
  end

  defp stream_loop(sse, flow_id, emitted) do
    receive do
      {:phlox_monitor, :node_done, %{current_id: node_name, shared: shared}} ->
        if node_name in @specialist_nodes and node_name not in emitted do
          result = extract_review(node_name, shared)

          if result do
            dispatch_specialist(flow_id, result)
            emit_specialist_card(sse, node_name, result)
          end

          new_emitted = MapSet.put(emitted, node_name)
          maybe_all_specialists_done(sse, new_emitted)
          stream_loop(sse, flow_id, new_emitted)
        else
          stream_loop(sse, flow_id, emitted)
        end

      {:phlox_monitor, :flow_done, %{shared: shared}} ->
        emit_synthesis(sse, flow_id, shared)

      {:phlox_monitor, _event, _snapshot} ->
        stream_loop(sse, flow_id, emitted)

    after
      90_000 ->
        # Before giving up, check if the flow completed while we were waiting
        # (handles race where :flow_done went to a previous SSE connection)
        case Phlox.Monitor.get(flow_id) do
          %{status: :done, shared: shared} ->
            emit_remaining_specialists(sse, flow_id, shared, emitted)
            emit_synthesis(sse, flow_id, shared)

          _ ->
            sse_send(sse, fn ->
              Signals.patch(sse, %{"flow_status" => "timeout"})
            end)
        end
    end
  end

  # When all 3 specialists are done, scroll to synthesis and update its label
  defp maybe_all_specialists_done(sse, emitted) do
    if MapSet.size(emitted) == length(@specialist_nodes) do
      sse_send(sse, fn ->
        # Update the synthesis skeleton label
        sse
        |> Elements.patch(
            ~s(<span class="loading-label synthesizing">synthesizing specialists' findings…</span>),
            selector: "#card-synthesis .loading-label",
            mode: :outer
          )
        |> Script.execute(scroll_to("card-synthesis"))
      end)
    end
  end

  defp emit_specialist_card(sse, node_name, result) do
    sse_send(sse, fn ->
      sse
      |> Elements.patch(render_specialist_card(node_name, result),
           selector: "#card-#{node_name}", mode: :outer)
      |> Signals.patch(%{"#{node_name}_status" => "complete"})
      |> Script.execute(scroll_to("card-#{node_name}"))
    end)
  end

  defp emit_remaining_specialists(sse, flow_id, shared, emitted) do
    for node_name <- @specialist_nodes, node_name not in emitted do
      case extract_review(node_name, shared) do
        nil -> :skip
        result ->
          dispatch_specialist(flow_id, result)
          emit_specialist_card(sse, node_name, result)
      end
    end
  end

  defp emit_synthesis(sse, flow_id, shared) do
    synthesis = Map.get(shared, :synthesis)

    if synthesis do
      Quorum.CommandedApp.dispatch(%Quorum.Commands.RecordSynthesis{
        review_id: flow_id,
        synthesis: synthesis.review,
        error: Map.get(synthesis, :error)
      })

      sse_send(sse, fn ->
        sse
        |> Elements.patch(render_synthesis_card(synthesis),
             selector: "#card-synthesis", mode: :outer)
        |> Signals.patch(%{"flow_status" => "complete", "active_reviewers" => 0})
        |> Script.execute(scroll_to("card-synthesis"))
      end)
    end
  end

  defp scroll_to(element_id) do
    "setTimeout(function(){var el=document.getElementById('#{element_id}');if(el)el.scrollIntoView({behavior:'smooth',block:'nearest'})},100)"
  end

  defp sse_send(_sse, fun) do
    try do
      fun.()
    rescue
      e in RuntimeError ->
        if String.contains?(Exception.message(e), "closed") do
          require Logger
          Logger.debug("SSE connection closed, stopping stream")
        else
          reraise e, __STACKTRACE__
        end
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

  # ---------------------------------------------------------------------------
  # Skeleton cards
  # ---------------------------------------------------------------------------

  defp render_skeleton_card(node_name) do
    name = specialist_label(node_name)
    icon = icon_for(name)
    accent = accent_for(node_name)

    """
    <article id="card-#{node_name}" class="specialist-card loading" data-specialist="#{node_name}" style="--card-accent: #{accent}">
      <header>
        <h3>#{icon} #{name}</h3>
        <span class="loading-label">analyzing…</span>
      </header>
      <div class="review-content loading-body">
        <span class="phlox-spinner spinning" style="--phlox-spinner-size: 28px">
          <span class="phlox-ring phlox-ring-outer"></span>
          <span class="phlox-ring phlox-ring-middle"></span>
          <span class="phlox-ring phlox-ring-inner"></span>
        </span>
      </div>
    </article>
    """
  end

  defp render_skeleton_synthesis do
    """
    <article id="card-synthesis" class="synthesis-card loading">
      <header>
        <h3>⚡ Synthesis</h3>
        <span class="loading-label">waiting for specialists…</span>
      </header>
      <div class="review-content loading-body">
        <span class="phlox-spinner spinning" style="--phlox-spinner-size: 28px">
          <span class="phlox-ring phlox-ring-outer"></span>
          <span class="phlox-ring phlox-ring-middle"></span>
          <span class="phlox-ring phlox-ring-inner"></span>
        </span>
      </div>
    </article>
    """
  end

  # ---------------------------------------------------------------------------
  # Completed cards
  # ---------------------------------------------------------------------------

  defp render_specialist_card(node_name, %{specialist: name, review: review} = result) do
    error_class = if Map.get(result, :error), do: " error", else: ""

    """
    <article id="card-#{node_name}" class="specialist-card#{error_class}" data-specialist="#{String.downcase(name)}">
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
    error_class = if Map.get(result, :error), do: " error", else: ""

    """
    <article id="card-synthesis" class="synthesis-card#{error_class}">
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

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp specialist_label(:security), do: "Security"
  defp specialist_label(:logic), do: "Logic"
  defp specialist_label(:style), do: "Style"

  defp accent_for(:security), do: "var(--q-security)"
  defp accent_for(:logic), do: "var(--q-logic)"
  defp accent_for(:style), do: "var(--q-style)"

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
