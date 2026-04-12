defmodule Quorum.Middleware.Throttle do
  @moduledoc """
  Adds a random delay before LLM nodes to spread token usage across
  Groq's (or any rate-limited provider's) rolling TPM window.

  Skips the first LLM node since there are no prior tokens to worry about.
  Subsequent LLM nodes sleep for a random duration within the configured range.

  ## Configuration

  Pass options via pipeline metadata under the `:throttle` key:

      middlewares: [
        Phlox.Middleware.Simplect,
        Quorum.Middleware.Throttle
      ],
      metadata: %{
        simplect: :ultra,
        throttle: %{
          delay: 2..4,
          llm_nodes: [:security, :logic, :style, :synthesize]
        }
      }

  ## Options

    * `:delay` — range in seconds for `Enum.random/1` (default: `2..4`)
    * `:llm_nodes` — list of node IDs that call an LLM (default: `[:security, :logic, :style, :synthesize]`)
  """
  @behaviour Phlox.Middleware

  @default_delay 2..4
  @default_llm_nodes [:security, :logic, :style, :synthesize]

  @impl true
  def before_node(shared, ctx) do
    config = get_config(ctx)
    node_id = ctx.node_id
    llm_nodes = config.llm_nodes

    if node_id in llm_nodes and not first_llm_node?(node_id, llm_nodes, shared) do
      delay_s = Enum.random(config.delay)
      Process.sleep(delay_s * 1_000)
    end

    {:cont, shared}
  end

  @impl true
  def after_node(shared, action, _ctx), do: {:cont, shared, action}

  # The first LLM node has no prior reviews in shared — no need to delay
  defp first_llm_node?(node_id, llm_nodes, shared) do
    prior_nodes = Enum.take_while(llm_nodes, &(&1 != node_id))

    not Enum.any?(prior_nodes, fn n ->
      key = review_key(n)
      key && Map.has_key?(shared, key)
    end)
  end

  defp review_key(:security), do: :security_review
  defp review_key(:logic), do: :logic_review
  defp review_key(:style), do: :style_review
  defp review_key(:synthesize), do: :synthesis
  defp review_key(_), do: nil

  defp get_config(ctx) do
    throttle = get_in_metadata(ctx, :throttle) || %{}

    %{
      delay: Map.get(throttle, :delay, @default_delay),
      llm_nodes: Map.get(throttle, :llm_nodes, @default_llm_nodes)
    }
  end

  defp get_in_metadata(ctx, key) do
    case Map.get(ctx, :metadata) do
      %{} = meta -> Map.get(meta, key)
      _ -> nil
    end
  end
end
