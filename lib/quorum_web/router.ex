defmodule QuorumWeb.Router do
  use QuorumWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", QuorumWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/", QuorumWeb do
    pipe_through :api

    post "/review", ReviewController, :create
  end

  # SSE endpoint — no pipeline (raw conn for streaming)
  scope "/", QuorumWeb do
    get "/review/:flow_id/stream", ReviewController, :stream
  end
end
