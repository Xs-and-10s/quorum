defmodule Quorum.Pipeline.Nodes.Specialist do
  @moduledoc """
  Shared logic for specialist review nodes.

  Each specialist defines its own system_prompt/0 and result_key.
  The Phlox prep/exec/post lifecycle is identical across specialists.

  Messages are built in `prep/2` so that `Phlox.Interceptor.Complect`
  can inject the token-compression system prompt in `before_exec`.

  `exec/2` lets `chat!` raise naturally — Phlox's retry mechanism
  catches the exception and retries with backoff. If all retries are
  exhausted, `exec_fallback/3` returns a graceful error result that
  `post/4` writes into shared state as an error card.
  """

  defmacro __using__(opts) do
    result_key = Keyword.fetch!(opts, :result_key)
    specialist_name = Keyword.fetch!(opts, :name)

    quote do
      use Phlox.Node

      intercept Phlox.Interceptor.Complect, level: :ultra

      def prep(shared, _params) do
        code = shared[:validated_code]
        language = shared[:validated_language]

        user_prompt = """
        Language: #{language}

        ```#{language}
        #{code}
        ```
        """

        [
          %{role: "system", content: system_prompt()},
          %{role: "user", content: user_prompt}
        ]
      end

      # Let chat! raise — Phlox retry catches exceptions and retries
      def exec(messages, params) do
        provider = Map.fetch!(params, :llm)
        llm_opts = Map.get(params, :llm_opts, [])

        Phlox.LLM.chat!(provider, messages, llm_opts)
      end

      # Called when all retries are exhausted — degrade gracefully
      def exec_fallback(_prep, _params, exception) do
        {:error, Exception.message(exception)}
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

      def post(shared, _prep, review, _params) when is_binary(review) do
        result = %{
          specialist: unquote(specialist_name),
          review: review,
          completed_at: DateTime.utc_now()
        }

        {:default, Map.put(shared, unquote(result_key), result)}
      end
    end
  end
end
