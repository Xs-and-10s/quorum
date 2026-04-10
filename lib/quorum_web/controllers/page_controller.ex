defmodule QuorumWeb.PageController do
  use QuorumWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: {QuorumWeb.Layouts, :root})
  end
end
