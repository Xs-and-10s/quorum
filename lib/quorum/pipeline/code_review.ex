defmodule Quorum.Pipeline.CodeReview do
  @moduledoc """
  Three-specialist code review pipeline orchestrated by Phlox.

  Graph topology:
    validate_input
        │
    ┌───┼───┐
    ▼   ▼   ▼
  security logic style    (parallel fan-out via batch)
    └───┼───┘
        ▼
    synthesize              (fan-in)
  """

  alias Phlox.Graph

  @spec build() :: Phlox.Flow.t()
  def build do
    Graph.new()
    |> Graph.add_node(:validate_input, Quorum.Pipeline.Nodes.ValidateInput)
    |> Graph.add_node(:security, Quorum.Pipeline.Nodes.SecurityReview,
         %{llm: Phlox.LLM.Groq, llm_opts: [model: "llama-3.3-70b-versatile"]},
         max_retries: 2, wait_ms: 6_000)
    |> Graph.add_node(:logic, Quorum.Pipeline.Nodes.LogicReview,
         %{llm: Phlox.LLM.Groq, llm_opts: [model: "llama-3.3-70b-versatile"]},
         max_retries: 2, wait_ms: 6_000)
    |> Graph.add_node(:style, Quorum.Pipeline.Nodes.StyleReview,
         %{llm: Phlox.LLM.Groq, llm_opts: [model: "llama-3.3-70b-versatile"]},
         max_retries: 2, wait_ms: 6_000)
    |> Graph.add_node(:synthesize, Quorum.Pipeline.Nodes.Synthesize,
         %{llm: Phlox.LLM.Groq, llm_opts: [model: "llama-3.3-70b-versatile"]},
         max_retries: 2, wait_ms: 6_000)
    |> Graph.connect(:validate_input, :security)
    |> Graph.connect(:security, :logic)
    |> Graph.connect(:logic, :style)
    |> Graph.connect(:style, :synthesize)
    |> Graph.start_at(:validate_input)
    |> Graph.to_flow!()
  end
end
