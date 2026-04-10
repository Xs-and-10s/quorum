defmodule Quorum.Pipeline.Nodes.ValidateInput do
  @moduledoc "Validates and normalizes user input before fan-out to specialists."

  @behaviour Phlox.Node

  alias Gladius.Spec

  @supported_languages ~w(elixir typescript javascript)

  @input_spec Spec.keys(%{
    required: %{
      code: Spec.and([Spec.is_binary(), &(String.length(&1) > 0)]),
      language: Spec.enum(@supported_languages)
    }
  })

  @impl true
  def call(context) do
    input = %{
      code: Phlox.Context.get(context, :code),
      language: Phlox.Context.get(context, :language) || "elixir"
    }

    case Gladius.conform(input, @input_spec) do
      {:ok, validated} ->
        context
        |> Phlox.Context.put(:validated_code, validated.code)
        |> Phlox.Context.put(:validated_language, validated.language)

      {:error, errors} ->
        Phlox.Context.halt(context, {:validation_error, errors})
    end
  end
end
