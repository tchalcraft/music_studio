defmodule MusicStudioWeb.Router do
  use MusicStudioWeb, :router
  use Beacon.Router
  use Beacon.LiveAdmin.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MusicStudioWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :beacon do
    plug Beacon.Plug
  end

  pipeline :beacon_admin do
    plug Beacon.LiveAdmin.Plug
  end

  # The hand-built marketing page currently owns the exact "/" route. The Beacon
  # site is mounted below as a catch-all, so it serves every other path; when we
  # port the marketing content into Beacon we can drop this and let Beacon own "/".
  scope "/", MusicStudioWeb do
    pipe_through :browser

    live "/", HomeLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", MusicStudioWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development.
  # Declared before the Beacon site catch-all so they aren't shadowed.
  if Application.compile_env(:music_studio, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MusicStudioWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Beacon LiveAdmin — content management UI. Before the site catch-all.
  scope "/" do
    pipe_through [:browser, :beacon_admin]

    beacon_live_admin "/cms"
  end

  # Beacon public site — CMS-managed pages, backed by MusicStudio.Repo (Neon in dev).
  # A catch-all, so it MUST be last. Serves every path except the ones declared above.
  scope "/", MusicStudioWeb do
    pipe_through [:browser, :beacon]

    beacon_site "/", site: :music_studio
  end
end
