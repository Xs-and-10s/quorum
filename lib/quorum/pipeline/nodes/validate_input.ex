defmodule Quorum.Pipeline.Nodes.ValidateInput do
  @moduledoc "Validates and normalizes user input before specialists run."

  use Phlox.Node

  import Gladius

  defp input_spec do
    schema(%{
      required(:code)     => string(:filled?),
      required(:language) => atom(in?: [:elixir, :typescript, :javascript])
    })
  end

  def prep(shared, _params) do
    %{
      code: shared[:code],
      language: coerce_language(shared[:language])
    }
  end

  def exec(input, _params) do
    Gladius.conform(input_spec(), input)
  end

  def post(shared, _prep, {:ok, validated}, _params) do
    shared =
      shared
      |> Map.put(:validated_code, validated.code)
      |> Map.put(:validated_language, Atom.to_string(validated.language))

    {:default, shared}
  end

  def post(shared, _prep, {:error, errors}, _params) do
    {"error", Map.put(shared, :error, {:validation_error, errors})}
  end

  defp coerce_language(nil), do: :elixir
  defp coerce_language(lang) when is_binary(lang), do: String.to_existing_atom(lang)
  defp coerce_language(lang) when is_atom(lang), do: lang
end
