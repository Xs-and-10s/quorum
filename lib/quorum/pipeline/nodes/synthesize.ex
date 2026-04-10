defmodule Quorum.Pipeline.Nodes.Synthesize do
  @behaviour Phlox.Node

  @impl true
  def call(context) do
    reviews =
      [:security_review, :logic_review, :style_review]
      |> Enum.map(&Phlox.Context.get(context, &1))
      |> Enum.reject(&is_nil/1)

    review_text =
      reviews
      |> Enum.map(fn r -> "## #{r.specialist} Review\n#{r.review}" end)
      |> Enum.join("\n\n---\n\n")

    language = Phlox.Context.get(context, :validated_language)

    system = """
    You are a lead engineer synthesizing three specialist code reviews
    (security, logic, style) into one actionable summary.

    Deduplicate overlapping findings. Group by severity. Lead with the
    most critical items. End with an overall assessment (1-2 sentences).
    Keep the synthesis under 400 words.
    """

    user = """
    Language: #{language}

    #{review_text}
    """

    case Quorum.LLM.Groq.chat(system, user) do
      {:ok, synthesis} ->
        Phlox.Context.put(context, :synthesis, %{
          specialist: "Synthesis",
          review: synthesis,
          completed_at: DateTime.utc_now()
        })

      {:error, reason} ->
        Phlox.Context.put(context, :synthesis, %{
          specialist: "Synthesis",
          review: "Synthesis failed: #{inspect(reason)}",
          error: true,
          completed_at: DateTime.utc_now()
        })
    end
  end
end
