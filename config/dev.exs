use Mix.Config

host = "hubs.local"

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with brunch.io to recompile .js and .css sources.
config :ret, RetWeb.Endpoint,
  url: [scheme: "https", host: host, port: 4000],
  static_url: [scheme: "https", host: host, port: 4000],
  https: [
    port: 4000,
    otp_app: :ret,
    keyfile: "#{System.get_env("PWD")}/priv/dev-ssl.key",
    certfile: "#{System.get_env("PWD")}/priv/dev-ssl.cert"
  ],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  secret_key_base: "txlMOtlaY5x3crvOCko4uV5PM29ul3zGo1oBGNO3cDXx+7GHLKqt0gR9qzgThxb5",
  allowed_origins: "*",
  watchers: [
    node: [
      "node_modules/brunch/bin/brunch",
      "watch",
      "--stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

# ## SSL Support
#
# In order to use HTTPS in development, a self-signed
# certificate can be generated by running the following
# command from your terminal:
#
#     openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com" -keyout priv/server.key -out priv/server.pem
#
# The `http:` config above can be replaced with:
#
#     https: [port: 4000, keyfile: "priv/server.key", certfile: "priv/server.pem"],
#
# If desired, both `http:` and `https:` keys can be
# configured to run both http and https servers on
# different ports.

# Watch static and templates for browser reloading.
config :ret, RetWeb.Endpoint,
  # static_url: [scheme: "https", host: "assets-prod.reticulum.io", port: 443],
  live_reload: [
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{priv/gettext/.*(po)$},
      ~r{lib/ret_web/views/.*(ex)$},
      ~r{lib/ret_web/templates/.*(eex)$}
    ]
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

env_db_host = "#{System.get_env("DB_HOST")}"

# Configure your database
config :ret, Ret.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "ret_dev",
  hostname: if(env_db_host == "", do: "localhost", else: env_db_host),
  template: "template0",
  pool_size: 10

config :ret, RetWeb.Plugs.HeaderAuthorization,
  header_name: "x-ret-admin-access-key",
  header_value: "admin-only"

# Allow any origin for API access in dev
config :cors_plug, origin: ["*"]

config :ret,
  upload_encryption_key: "a8dedeb57adafa7821027d546f016efef5a501bd",
  farspark_signature_key:
    "248cf801c4f5d6fd70c1b0dfea8dedeb57adafa7821027d546f016efef5a501bd8168c8479d33b466199d0ac68c71bb71b68c27537102a63cd70776aa83bca76",
  farspark_signature_salt:
    "da914bb89e332b2a815a667875584d067b698fe1f6f5c61d98384dc74d2ed85b67eea0a51325afb9d9c7d798f4bbbd630102a261e152aceb13d9469b02da6b31",
  farspark_host: "https://farspark-dev.reticulum.io"

config :ret, Ret.PageOriginWarmer,
  page_origin: "https://#{host}:8080",
  insecure_ssl: true

config :ret, Ret.MediaResolver,
  giphy_api_key: nil,
  deviantart_client_id: nil,
  deviantart_client_secret: nil,
  imgur_mashape_api_key: nil,
  imgur_client_id: nil,
  google_poly_api_key: nil,
  sketchfab_api_key: nil,
  ytdl_host: "http://localhost:9191"

config :ret, Ret.Storage,
  storage_path: "storage/dev",
  ttl: 60 * 60 * 24

asset_hosts =
  "https://localhost:4000 https://localhost:8080 " <>
    "https://#{host}:4000 https://#{host}:8080 " <>
    "https://asset-bundles-dev.reticulum.io https://asset-bundles-prod.reticulum.io " <>
    "https://farspark-prod.reticulum.io https://farspark-dev.reticulum.io " <> "https://hubs-proxy.com"

websocket_hosts =
  "https://localhost:4000 https://localhost:8080 wss://localhost:4000 " <>
    "https://#{host}:4000 https://#{host}:8080 wss://#{host}:4000 wss://#{host}:8080 " <>
    "wss://dev-janus.reticulum.io wss://prod-janus.reticulum.io"

config :secure_headers, SecureHeaders,
  secure_headers: [
    config: [
      content_security_policy:
        "default-src 'none'; script-src 'self' #{asset_hosts} https://cdn.rawgit.com https://aframe.io 'unsafe-eval'; worker-src 'self' blob:; font-src 'self' https://fonts.googleapis.com https://fonts.gstatic.com https://cdn.aframe.io #{
          asset_hosts
        }; style-src 'self' https://fonts.googleapis.com #{asset_hosts} 'unsafe-inline'; connect-src 'self' https://sentry.prod.mozaws.net https://dpdb.webvr.rocks #{
          asset_hosts
        } #{websocket_hosts} https://cdn.aframe.io https://www.mozilla.org data: blob:; img-src 'self' #{asset_hosts} https://cdn.aframe.io data: blob:; media-src 'self' #{
          asset_hosts
        } data: blob:; frame-src 'self'; frame-ancestors 'self'; base-uri 'none'; form-action 'self';"
    ]
  ]

config :ret, Ret.Mailer, adapter: Bamboo.LocalAdapter

config :ret, RetWeb.Email, from: "info@hubs-mail.com"

config :ret, Ret.PermsToken,
  perms_key:
    "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEAq7o6egtZRhWyUYt9U/hUdxWRi2bO8yG4ZVm/CDqk+IJMFh3/\nXl88X5iQwxQxQrIv94Po/H5dnB8Bbw0toSw58HSk8L6BVBsOkIDic1Bfa82WxLWq\nWhhgkKWBOXctbUFoSCUWFQ/YGMH4Ur66pEhsqqodkPj3lJdFt3in0nu6w1duepnQ\nj3en9YUW3m387Oj1oCaLQtmLAPZ0VlBnLnwT9Y4Nr76Dww2FKoqBZH+Cb6ku12jM\naAwoZpRhIX6LVr/GPsHbuIdd+vOyQxD6EwBbtue6KQimkITwxnPxStdwPbhGIO63\ndPdv+rgw6u1iFIjMGEGCQmo0MoH9i5rvg42ThQIDAQABAoIBAQCMn9SxCkgRx0Sd\n2C9KKunoFoZ39Dl2Cd/5RtPThkp/ohtyZSAwhKZo1gN9bDSmnEoBU0jgMw6vAQjo\nio8aE6BikvJannZDjGCR3qkRqvhozBMxhF46pwm0iYNXrotJk600nwIFP1NDetvB\nzqQCUbiCzQmnJOmBCZsykiBDkcSvnrqw3kQocWu2vZ0vsuTqNwJT1gCW12hzeFu7\n/OYy5DgQkG7fjaxWyv1+OJSw2zg7jQmEG43C/W95C0uZ1aiVARM+dl6YYLdSGIxi\nioP9FwrqGuZGPQm1d6LBkoo/KgFdvQWl6poXT7oQJ4WS/kTGrWX9I29wsfC4gi6I\nVtqwoBEFAoGBANgY/OInP5pwa2YlVxGHEdko56yuXEcRDxwnDrIA8UPC2k/Emaye\nXDNVdH6olQ8yU9dy2UbitDy01yKV5r+u0Y+B4YCp6I6wsM5QUCQtpgmaPJKb90tL\njM9ZJLtR74Ch+IcOs8wG0sSYVNxWElhuWQg/eKgXq80fpStjepeWvTMjAoGBAMtv\n2Ozn6JTNAQ69xgAb+/tfBqMGfv7cbs03/1IQiG2r55dlEj8xSgBgTEHf4OK0dkPC\nFrkFi5RLDtWzjluxRan2kFEkIxU1CONGdd/wYGIzdhWubv18WChUEumCEhZaUw+v\n6Uh8o/9anVipii4LtEgVITsdcVfyBAgK75eiCv03AoGAFsgDmN/kX6asW9dh53Ii\n2o7qZZT4G3Hb8u7XKMLarHcVRsWGIeGL/Mlsf5HMLQ70MclkyIlL0P6Lk5TT/68x\nXnylxkejQa+04/sph7bcQzTkX9xbZK+xR4axTaIkqp3osmxFXiP2Ak3A3H2ib3oq\nnqj6UlY0gWptojZZjTOR/JsCgYAZPWg5hFBL3d9qt8rQCqjJuDF3mn+5GRo6Jd9s\njBaRHMnf868+3dujjk8HwUICfodJwtPU4sY9gM53Xw6je6v7+VZQat5bbDgNEpnf\nTdB3fpEBAaJNmtbJMh0ikXuzAEPb52RXFPe338Mz090L93HHm6+CyRVd5u3vHYQ6\nWOVqIwKBgGrPEPHO8a1/pa4+K/w/OkY6JSdZPtkJQs/PWULqI8QriTpJH290hMAD\nfnplvB2eaTLWopchYcMVxJJW5nJX48yPiNwuwWfajnvLlGMguKxWGseqpxbMgCPP\nBnnWTFVMfeX0s7sNgmF7OmpZU87V4NiQRk/mmr+7a/zr7hXvp0t1\n-----END RSA PRIVATE KEY-----"

config :ret, Ret.Guardian,
  issuer: "ret",
  secret_key: "47iqPEdWcfE7xRnyaxKDLt9OGEtkQG3SycHBEMOuT2qARmoESnhc76IgCUjaQIwX",
  ttl: {12, :weeks}

config :web_push_encryption, :vapid_details,
  subject: "mailto:admin@mozilla.com",
  public_key: "BAb03820kHYuqIvtP6QuCKZRshvv_zp5eDtqkuwCUAxASBZMQbFZXzv8kjYOuLGF16A3k8qYnIN10_4asB-Aw7w",
  private_key: "w76tXh1d3RBdVQ5eINevXRwW6Ow6uRcBa8tBDOXfmxM"

config :sentry,
  environment_name: :dev,
  json_library: Poison,
  included_environments: [],
  tags: %{
    env: "dev"
  }

config :ret, Ret.Habitat, ip: "127.0.0.1", http_port: 9631

config :ret, Ret.JanusLoadStatus, default_janus_host: "dev-janus.reticulum.io"

config :ret, Ret.RoomAssigner, balancer_weights: [{600, 1}, {300, 50}, {0, 500}]

config :ret, DiscordBot,
  hostnames: "localhost hubs.local"
  # token: "foo"
