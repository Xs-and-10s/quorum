defmodule Quorum.Pipeline.Nodes.Specialist do
  @moduledoc """
  Shared logic for specialist review nodes.

  Each specialist defines its own system_prompt/0 and result_key.
  The Phlox prep/exec/post lifecycle is identical across specialists.
  """

  defmacro __using__(opts) do
    result_key = Keyword.fetch!(opts, :result_key)
    specialist_name = Keyword.fetch!(opts, :name)

    quote do
      use Phlox.Node

      def prep(shared, _params) do
        {shared[:validated_code], shared[:validated_language]}
      end

      def exec({code, language}, params) do
        provider = Map.fetch!(params, :llm)
        llm_opts = Map.get(params, :llm_opts, [])

        user_prompt = """
        Language: #{language}

        ```#{language}
        #{code}
        ```
        """

        messages = [
          %{role: "system", content: system_prompt()},
          %{role: "user", content: user_prompt}
        ]

        try do
          {:ok, Phlox.LLM.chat!(provider, messages, llm_opts)}
        rescue
          e -> {:error, Exception.message(e)}
        end
      end

      def post(shared, _prep, {:ok, review}, _params) do
        result = %{
          specialist: unquote(specialist_name),
          review: review,
          completed_at: DateTime.utc_now()
        }

        {:default, Map.put(shared, unquote(result_key), result)}
      end

      def post(shared, _prep, {:error, reason}, _params) do
        result = %{
          specialist: unquote(specialist_name),
          review: "Review failed: #{reason}",
          error: true,
          completed_at: DateTime.utc_now()
        }

        {:default, Map.put(shared, unquote(result_key), result)}
      end
    end
  end
end
