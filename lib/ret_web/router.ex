defmodule RetWeb.Router do
  use RetWeb, :router
  use Plug.ErrorHandler
  use Sentry.Plug

  pipeline :secure_headers do
    plug(:put_secure_browser_headers)
    plug(RetWeb.Plugs.AddCSP)
  end

  pipeline :ssl_only do
    plug(Plug.SSL, hsts: true, rewrite_on: [:x_forwarded_proto])
  end

  pipeline :parsed_body do
    plug(
      Plug.Parsers,
      parsers: [:urlencoded, :multipart, :json],
      pass: ["*/*"],
      json_decoder: Phoenix.json_library(),
      length: 157_286_400,
      read_timeout: 300_000
    )
  end

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:put_layout, false)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :proxy_api do
    plug(:accepts, ["json"])
    plug(RetWeb.Plugs.RewriteAuthorizationHeaderToPerms)
  end

  pipeline :auth_optional do
    plug(RetWeb.Guardian.AuthOptionalPipeline)
  end

  pipeline :auth_required do
    plug(RetWeb.Guardian.AuthPipeline)
    plug(RetWeb.Canary.AuthorizationPipeline)
  end

  pipeline :admin_required do
    plug(RetWeb.Guardian.AuthPipeline)
    plug(RetWeb.Plugs.AdminOnly)
  end

  pipeline :bot_header_auth do
    plug(RetWeb.Plugs.BotHeaderAuthorization)
  end

  pipeline :canonicalize_domain do
    plug(RetWeb.Plugs.RedirectToMainDomain)
  end

  scope "/health", RetWeb do
    get("/", HealthController, :index)
  end

  scope "/api/postgrest" do
    pipe_through([:secure_headers, :auth_required, :admin_required, :proxy_api])
    forward("/", RetWeb.Plugs.PostgrestProxy)
  end

  scope "/api/ita" do
    pipe_through([:secure_headers, :auth_required, :admin_required, :proxy_api])
    forward("/", RetWeb.Plugs.ItaProxy)
  end

  scope "/api", RetWeb do
    pipe_through(
      [:secure_headers, :parsed_body, :api] ++ if(Mix.env() == :prod, do: [:ssl_only, :canonicalize_domain], else: [])
    )

    scope "/v1", as: :api_v1 do
      get("/meta", Api.V1.MetaController, :show)
      resources("/media", Api.V1.MediaController, only: [:create])
      get("/avatars/:id/base.gltf", Api.V1.AvatarController, :show_base_gltf)
      get("/avatars/:id/avatar.gltf", Api.V1.AvatarController, :show_avatar_gltf)
      get("/oauth/:type", Api.V1.OAuthController, :show)

      scope "/support" do
        resources("/subscriptions", Api.V1.SupportSubscriptionController, only: [:create, :delete])
        resources("/availability", Api.V1.SupportSubscriptionController, only: [:index])
      end

      resources("/ret_notices", Api.V1.RetNoticeController, only: [:create])
    end

    scope "/v1", as: :api_v1 do
      pipe_through([:bot_header_auth])
      resources("/hub_bindings", Api.V1.HubBindingController, only: [:create])
    end

    scope "/v1", as: :api_v1 do
      pipe_through([:auth_optional])
      resources("/hubs", Api.V1.HubController, only: [:create, :delete])
      resources("/media/search", Api.V1.MediaSearchController, only: [:index])
      resources("/avatars", Api.V1.AvatarController, only: [:show])
      resources("/scenes", Api.V1.SceneController, only: [:show])
    end

    scope "/v1", as: :api_v1 do
      pipe_through([:auth_required])
      resources("/scenes", Api.V1.SceneController, only: [:create, :update])
      resources("/avatars", Api.V1.AvatarController, only: [:create, :update, :delete])
      resources("/hubs", Api.V1.HubController, only: [:update])
      resources("/assets", Api.V1.AssetsController, only: [:create, :delete])
      post("/twitter/tweets", Api.V1.TwitterController, :tweets)

      resources("/projects", Api.V1.ProjectController, only: [:index, :show, :create, :update, :delete]) do
        post("/publish", Api.V1.ProjectController, :publish)
        resources("/assets", Api.V1.ProjectAssetsController, only: [:index, :create, :delete])
      end
    end

    scope "/v1", as: :api_v1 do
      pipe_through([:admin_required])
      resources("/app_configs", Api.V1.AppConfigController, only: [:index, :create])
    end
  end

  scope "/", RetWeb do
    pipe_through([:secure_headers, :parsed_body, :browser] ++ if(Mix.env() == :prod, do: [:ssl_only], else: []))

    head("/files/:id", FileController, :head)
    get("/files/:id", FileController, :show)
  end

  scope "/", RetWeb do
    pipe_through(
      [:secure_headers, :parsed_body, :browser] ++
        if(Mix.env() == :prod, do: [:ssl_only, :canonicalize_domain], else: [])
    )

    get("/*path", PageController, only: [:index])
  end
end
