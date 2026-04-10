defmodule Quorum.Pipeline.Nodes.Specialist do
  @moduledoc """
  Shared logic for specialist review nodes.

  Each specialist defines its own system prompt and result key.
  The actual LLM call and context update pattern is identical.
  """

  defmacro __using__(opts) do
    result_key = Keyword.fetch!(opts, :result_key)
    specialist_name = Keyword.fetch!(opts, :name)

    quote do
      @behaviour Phlox.Node

      @impl true
      def call(context) do
        code = Phlox.Context.get(context, :validated_code)
        language = Phlox.Context.get(context, :validated_language)

        user_prompt = """
        Language: #{language}

        ```#{language}
        #{code}
        ```
        """

        case Quorum.LLM.Groq.chat(system_prompt(), user_prompt) do
          {:ok, review} ->
            Phlox.Context.put(context, unquote(result_key), %{
              specialist: unquote(specialist_name),
              review: review,
              completed_at: DateTime.utc_now()
            })

          {:error, reason} ->
            Phlox.Context.put(context, unquote(result_key), %{
              specialist: unquote(specialist_name),
              review: "Review failed: #{inspect(reason)}",
              error: true,
              completed_at: DateTime.utc_now()
            })
        end
      end
    end
  end
end
