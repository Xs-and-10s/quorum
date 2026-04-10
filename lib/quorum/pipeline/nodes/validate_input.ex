defmodule Quorum.Pipeline.Nodes.ValidateInput do
  @moduledoc "Validates and normalizes user input before fan-out to specialists."

  @behaviour Phlox.Node

  import Gladius

  # Schemas as functions, not module attributes — Gladius specs may contain
  # anonymous functions that Elixir cannot escape at compile time.
  defp input_spec do
    schema(%{
      required(:code)     => string(:filled?),
      required(:language) => atom(in?: [:elixir, :typescript, :javascript])
    })
  end

  @impl true
  def call(context) do
    input = %{
      code: Phlox.Context.get(context, :code),
      language: coerce_language(Phlox.Context.get(context, :language))
    }

    case Gladius.conform(input_spec(), input) do
      {:ok, validated} ->
        context
        |> Phlox.Context.put(:validated_code, validated.code)
        |> Phlox.Context.put(:validated_language, Atom.to_string(validated.language))

      {:error, errors} ->
        Phlox.Context.halt(context, {:validation_error, errors})
    end
  end

  defp coerce_language(nil), do: :elixir
  defp coerce_language(lang) when is_binary(lang), do: String.to_existing_atom(lang)
  defp coerce_language(lang) when is_atom(lang), do: lang
end
