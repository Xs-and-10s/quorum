defmodule Quorum.LLM.Groq do
  @moduledoc """
  Minimal Groq API client using Req.

  Expects GROQ_API_KEY in environment.
  Uses llama-3.3-70b-versatile (free tier).
  """

  @base_url "https://api.groq.com/openai/v1/chat/completions"
  @model "llama-3.3-70b-versatile"
  @timeout 60_000

  @spec chat(system :: String.t(), user :: String.t(), opts :: keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def chat(system_prompt, user_prompt, opts \\ []) do
    model = Keyword.get(opts, :model, @model)
    temperature = Keyword.get(opts, :temperature, 0.3)

    body = %{
      model: model,
      messages: [
        %{role: "system", content: system_prompt},
        %{role: "user", content: user_prompt}
      ],
      temperature: temperature,
      max_tokens: 2048
    }

    case Req.post(@base_url,
           json: body,
           headers: [{"authorization", "Bearer #{api_key()}"}],
           receive_timeout: @timeout
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        {:ok, content}

      {:ok, %{status: status, body: body}} ->
        {:error, {:groq_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp api_key do
    System.fetch_env!("GROQ_API_KEY")
  end
end
