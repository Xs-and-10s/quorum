defmodule Quorum.Pipeline.Nodes.Synthesize do
  use Phlox.Node

  intercept Phlox.Interceptor.Complect, level: :full

  def prep(shared, _params) do
    reviews =
      [:security_review, :logic_review, :style_review]
      |> Enum.map(&Map.get(shared, &1))
      |> Enum.reject(&is_nil/1)

    review_text =
      reviews
      |> Enum.map(fn r -> "## #{r.specialist} Review\n#{r.review}" end)
      |> Enum.join("\n\n---\n\n")

    language = shared[:validated_language]

    system = """
    You are a lead engineer synthesizing three specialist code reviews
    (security, logic, style) into one actionable summary.

    Deduplicate overlapping findings. Group by severity. Lead with the
    most critical items. End with an overall assessment (1-2 sentences).
    Keep the synthesis under 400 words.
    """

    user = "Language: #{language}\n\n#{review_text}"

    [
      %{role: "system", content: system},
      %{role: "user", content: user}
    ]
  end

  # Let chat! raise — Phlox retry catches and retries
  def exec(messages, params) do
    provider = Map.fetch!(params, :llm)
    llm_opts = Map.get(params, :llm_opts, [])

    Phlox.LLM.chat!(provider, messages, llm_opts)
  end

  # Called when all retries exhausted — degrade gracefully
  def exec_fallback(_prep, _params, exception) do
    {:error, Exception.message(exception)}
  end

  def post(shared, _prep, {:error, reason}, _params) do
    result = %{
      specialist: "Synthesis",
      review: "Synthesis failed: #{reason}",
      error: true,
      completed_at: DateTime.utc_now()
    }

    {:default, Map.put(shared, :synthesis, result)}
  end

  def post(shared, _prep, review, _params) when is_binary(review) do
    result = %{
      specialist: "Synthesis",
      review: review,
      completed_at: DateTime.utc_now()
    }

    {:default, Map.put(shared, :synthesis, result)}
  end
end
