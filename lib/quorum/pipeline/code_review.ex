defmodule Quorum.Pipeline.CodeReview do
  @moduledoc """
  Three-specialist code review pipeline orchestrated by Phlox.

  Graph topology:
    validate_input
        │
    ┌───┼───┐
    ▼   ▼   ▼
  security logic style    (parallel fan-out)
    └───┼───┘
        ▼
    synthesize              (fan-in)
  """

  alias Phlox.Graph
  alias Quorum.Pipeline.Nodes

  @spec build() :: Graph.t()
  def build do
    Graph.new()
    |> Graph.add_node(:validate_input, Nodes.ValidateInput)
    |> Graph.add_node(:security, Nodes.SecurityReview)
    |> Graph.add_node(:logic, Nodes.LogicReview)
    |> Graph.add_node(:style, Nodes.StyleReview)
    |> Graph.add_node(:synthesize, Nodes.Synthesize)
    |> Graph.add_edge(:validate_input, :security)
    |> Graph.add_edge(:validate_input, :logic)
    |> Graph.add_edge(:validate_input, :style)
    |> Graph.add_edge(:security, :synthesize)
    |> Graph.add_edge(:logic, :synthesize)
    |> Graph.add_edge(:style, :synthesize)
  end
end
