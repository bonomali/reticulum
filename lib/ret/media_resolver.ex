defmodule Ret.ResolvedMedia do
  @enforce_keys [:uri]
  defstruct [:uri, :audio_uri, :meta]
end

defmodule Ret.MediaResolverQuery do
  @enforce_keys [:url]
  defstruct [:url, supports_webm: true, quality: :high, version: 1]
end

defmodule Ret.MediaResolver do
  use Retry
  import Ret.HttpUtils

  require Logger

  alias Ret.{CachedFile, MediaResolverQuery, Statix}

  @ytdl_valid_status_codes [200, 302, 500]

  @non_video_root_hosts [
    "sketchfab.com",
    "giphy.com",
    "tenor.com"
  ]

  @deviant_id_regex ~r/\"DeviantArt:\/\/deviation\/([^"]+)/

  def resolve(%MediaResolverQuery{url: url} = query) when is_binary(url) do
    uri = url |> URI.parse()
    root_host = get_root_host(uri.host)
    resolve(query |> Map.put(:url, uri), root_host)
  end

  def resolve(%MediaResolverQuery{url: %URI{host: nil}}, _root_host) do
    {:commit, nil}
  end

  # Necessary short circuit around google.com root_host to skip YT-DL check for Poly
  def resolve(%MediaResolverQuery{url: %URI{host: "poly.google.com"}} = query, root_host) do
    resolve_non_video(query, root_host)
  end

  def resolve(%MediaResolverQuery{} = query, root_host) when root_host in @non_video_root_hosts do
    resolve_non_video(query, root_host)
  end

  def resolve(%MediaResolverQuery{} = query, root_host) do
    resolve_with_ytdl(query, root_host, query |> ytdl_format(root_host))
  end

  def resolve_with_ytdl(%MediaResolverQuery{} = query, root_host, ytdl_format) do
    with ytdl_host when is_binary(ytdl_host) <- module_config(:ytdl_host) do
      case fetch_ytdl_response(query, ytdl_format) do
        %HTTPoison.Response{status_code: 302, headers: headers} ->
          # todo: it would be really nice to return video/* content type here!
          # but it seems that the way we're using youtube-dl will return a 302 with the
          # direct URL for various non-video files, e.g. PDFs seem to trigger this, so until
          # we figure out how to change that behavior or distinguish between them, we can't
          # be confident that it's video/* in this branch
          media_url = headers |> media_url_from_ytdl_headers

          if query_ytdl_audio?(query) do
            # For 360 video quality types, we fetch the audio track separately since
            # YouTube serves up a separate webm for audio.
            resolve_with_ytdl_audio(query, media_url)
          else
            {:commit, media_url |> URI.parse() |> resolved(%{})}
          end

        _ ->
          resolve_non_video(query, root_host)
      end
    else
      _err ->
        resolve_non_video(query, root_host)
    end
  end

  def resolve_with_ytdl_audio(%MediaResolverQuery{} = query, media_url) do
    case fetch_ytdl_response(query, ytdl_audio_format(query)) do
      %HTTPoison.Response{status_code: 302, headers: headers} ->
        audio_url = headers |> media_url_from_ytdl_headers

        if media_url != audio_url do
          {:commit, media_url |> URI.parse() |> resolved(audio_url |> URI.parse(), %{})}
        else
          {:commit, media_url |> URI.parse() |> resolved(%{})}
        end

      _ ->
        {:commit, media_url |> URI.parse() |> resolved(%{})}
    end
  end

  defp fetch_ytdl_response(%MediaResolverQuery{url: %URI{} = uri, quality: quality}, ytdl_format) do
    ytdl_host = module_config(:ytdl_host)

    ytdl_query_args =
      %{
        format: ytdl_format,
        url: URI.to_string(uri),
        playlist_items: 1
      }
      |> ytdl_add_user_agent_for_quality(quality)

    ytdl_query = URI.encode_query(ytdl_query_args)

    "#{ytdl_host}/api/play?#{ytdl_query}" |> retry_get_until_valid_ytdl_response
  end

  defp ytdl_add_user_agent_for_quality(args, quality) when quality in [:low_360, :high_360] do
    # See https://github.com/ytdl-org/youtube-dl/issues/15267#issuecomment-370122336
    args
    |> Map.put(:user_agent, "")
  end

  defp ytdl_add_user_agent_for_quality(args, _quality), do: args

  defp resolve_non_video(%MediaResolverQuery{url: %URI{} = uri}, "deviantart.com") do
    Statix.increment("ret.media_resolver.deviant.requests")

    [uri, meta] =
      with client_id when is_binary(client_id) <- module_config(:deviantart_client_id),
           client_secret when is_binary(client_secret) <- module_config(:deviantart_client_secret) do
        page_resp = uri |> URI.to_string() |> retry_get_until_success
        deviant_id = Regex.run(@deviant_id_regex, page_resp.body) |> Enum.at(1)
        token_host = "https://www.deviantart.com/oauth2/token"
        api_host = "https://www.deviantart.com/api/v1/oauth2"

        token =
          "#{token_host}?client_id=#{client_id}&client_secret=#{client_secret}&grant_type=client_credentials"
          |> retry_get_until_success
          |> Map.get(:body)
          |> Poison.decode!()
          |> Map.get("access_token")

        uri =
          "#{api_host}/deviation/#{deviant_id}?access_token=#{token}"
          |> retry_get_until_success
          |> Map.get(:body)
          |> Poison.decode!()
          |> Kernel.get_in(["content", "src"])
          |> URI.parse()

        Statix.increment("ret.media_resolver.deviant.ok")
        # todo: determine appropriate content type here if possible
        [uri, nil]
      else
        _err -> [uri, nil]
      end

    {:commit, uri |> resolved(meta)}
  end

  defp resolve_non_video(%MediaResolverQuery{url: %URI{path: "/gifs/" <> _rest} = uri}, "giphy.com") do
    resolve_giphy_media_uri(uri, "mp4")
  end

  defp resolve_non_video(%MediaResolverQuery{url: %URI{path: "/stickers/" <> _rest} = uri}, "giphy.com") do
    resolve_giphy_media_uri(uri, "url")
  end

  defp resolve_non_video(%MediaResolverQuery{url: %URI{path: "/videos/" <> _rest} = uri}, "tenor.com") do
    {:commit, uri |> resolved(%{expected_content_type: "video/mp4"})}
  end

  defp resolve_non_video(%MediaResolverQuery{url: %URI{path: "/gallery/" <> gallery_id} = uri}, "imgur.com") do
    [resolved_url, meta] =
      "https://imgur-apiv3.p.mashape.com/3/gallery/#{gallery_id}"
      |> image_data_for_imgur_collection_api_url

    {:commit, (resolved_url || uri) |> resolved(meta)}
  end

  defp resolve_non_video(%MediaResolverQuery{url: %URI{path: "/a/" <> album_id} = uri}, "imgur.com") do
    [resolved_url, meta] =
      "https://imgur-apiv3.p.mashape.com/3/album/#{album_id}"
      |> image_data_for_imgur_collection_api_url

    {:commit, (resolved_url || uri) |> resolved(meta)}
  end

  defp resolve_non_video(
         %MediaResolverQuery{url: %URI{host: "poly.google.com", path: "/view/" <> asset_id} = uri},
         "google.com"
       ) do
    [uri, meta] =
      with api_key when is_binary(api_key) <- module_config(:google_poly_api_key) do
        Statix.increment("ret.media_resolver.poly.requests")

        payload =
          "https://poly.googleapis.com/v1/assets/#{asset_id}?key=#{api_key}"
          |> retry_get_until_success
          |> Map.get(:body)
          |> Poison.decode!()

        meta =
          %{expected_content_type: "model/gltf"}
          |> Map.put(:name, payload["displayName"])
          |> Map.put(:author, payload["authorName"])
          |> Map.put(:license, payload["license"])

        formats = payload |> Map.get("formats")

        uri =
          (Enum.find(formats, &(&1["formatType"] == "GLTF2")) || Enum.find(formats, &(&1["formatType"] == "GLTF")))
          |> Kernel.get_in(["root", "url"])
          |> URI.parse()

        Statix.increment("ret.media_resolver.poly.ok")

        [uri, meta]
      else
        _err -> [uri, nil]
      end

    {:commit, uri |> resolved(meta)}
  end

  defp resolve_non_video(
         %MediaResolverQuery{url: %URI{path: "/models/" <> model_id}} = query,
         "sketchfab.com"
       ) do
    resolve_sketchfab_model(model_id, query)
  end

  defp resolve_non_video(
         %MediaResolverQuery{url: %URI{path: "/3d-models/" <> model_id}} = query,
         "sketchfab.com"
       ) do
    model_id = model_id |> String.split("-") |> Enum.at(-1)
    resolve_sketchfab_model(model_id, query)
  end

  defp resolve_non_video(%MediaResolverQuery{url: %URI{host: host} = uri, version: version}, _root_host) do
    photomnemonic_endpoint = module_config(:photomnemonic_endpoint)

    # Crawl og tags for hubs rooms + scenes
    is_local_url = host === RetWeb.Endpoint.host()

    case uri |> URI.to_string() |> retry_head_then_get_until_success([{"Range", "bytes=0-32768"}]) do
      :error ->
        nil

      %HTTPoison.Response{headers: headers} ->
        content_type = headers |> content_type_from_headers
        has_entity_type = headers |> get_http_header("hub-entity-type") != nil

        if content_type |> String.starts_with?("text/html") do
          if !has_entity_type && !is_local_url && photomnemonic_endpoint do
            case uri |> screenshot_commit_for_uri(content_type, version) do
              :error -> uri |> opengraph_result_for_uri()
              commit -> commit
            end
          else
            uri |> opengraph_result_for_uri()
          end
        else
          {:commit, uri |> resolved(%{expected_content_type: content_type})}
        end
    end
  end

  defp screenshot_commit_for_uri(uri, content_type, version) do
    photomnemonic_endpoint = module_config(:photomnemonic_endpoint)

    query = URI.encode_query(url: uri |> URI.to_string())

    cached_file_result =
      CachedFile.fetch(
        "screenshot-#{query}-#{version}",
        fn path ->
          Statix.increment("ret.media_resolver.screenshot.requests")

          url = "#{photomnemonic_endpoint}/screenshot?#{query}"

          case Download.from(url, path: path) do
            {:ok, _path} -> {:ok, %{content_type: "image/png"}}
            error -> {:error, error}
          end
        end
      )

    case cached_file_result do
      {:ok, file_uri} ->
        meta = %{thumbnail: file_uri |> URI.to_string(), expected_content_type: content_type}

        {:commit, uri |> resolved(meta)}

      {:error, _reason} ->
        :error
    end
  end

  defp opengraph_result_for_uri(uri) do
    case uri |> URI.to_string() |> retry_get_until_success([{"Range", "bytes=0-32768"}]) do
      :error ->
        :error

      resp ->
        # note that there exist og:image:type and og:video:type tags we could use,
        # but our OpenGraph library fails to parse them out.
        # also, we could technically be correct to emit an "image/*" content type from the OG image case,
        # but our client right now will be confused by that because some images need to turn into
        # image-like views and some (GIFs) need to turn into video-like views.

        parsed_og = resp.body |> OpenGraph.parse()

        thumbnail =
          if parsed_og && parsed_og.image do
            parsed_og.image
          else
            nil
          end

        meta = %{
          expected_content_type: content_type_from_headers(resp.headers),
          thumbnail: thumbnail
        }

        {:commit, uri |> resolved(meta)}
    end
  end

  defp resolve_sketchfab_model(model_id, %MediaResolverQuery{url: %URI{} = uri, version: version}) do
    [uri, meta] =
      with api_key when is_binary(api_key) <- module_config(:sketchfab_api_key) do
        resolve_sketchfab_model(model_id, api_key, version)
      else
        _err -> [uri, nil]
      end

    {:commit, uri |> resolved(meta)}
  end

  defp resolve_sketchfab_model(model_id, api_key, version \\ 1) do
    cached_file_result =
      CachedFile.fetch(
        "sketchfab-#{model_id}-#{version}",
        fn path ->
          Statix.increment("ret.media_resolver.sketchfab.requests")

          res =
            "https://api.sketchfab.com/v3/models/#{model_id}/download"
            |> retry_get_until_success([{"Authorization", "Token #{api_key}"}])

          case res do
            :error ->
              Statix.increment("ret.media_resolver.sketchfab.errors")

              :error

            res ->
              Statix.increment("ret.media_resolver.sketchfab.ok")

              zip_url =
                res
                |> Map.get(:body)
                |> Poison.decode!()
                |> Kernel.get_in(["gltf", "url"])

              Download.from(zip_url, path: path)

              {:ok, %{content_type: "model/gltf+zip"}}
          end
        end
      )

    case cached_file_result do
      {:ok, uri} -> [uri, %{expected_content_type: "model/gltf+zip"}]
      {:error, _reason} -> :error
    end
  end

  defp resolve_giphy_media_uri(%URI{} = uri, preferred_type) do
    Statix.increment("ret.media_resolver.giphy.requests")

    [uri, meta] =
      with api_key when is_binary(api_key) <- module_config(:giphy_api_key) do
        gif_id = uri.path |> String.split("/") |> List.last() |> String.split("-") |> List.last()

        original_image =
          "https://api.giphy.com/v1/gifs/#{gif_id}?api_key=#{api_key}"
          |> retry_get_until_success
          |> Map.get(:body)
          |> Poison.decode!()
          |> Kernel.get_in(["data", "images", "original"])

        # todo: determine appropriate content type here if possible
        [(original_image[preferred_type] || original_image["url"]) |> URI.parse(), nil]
      else
        _err -> [uri, nil]
      end

    {:commit, uri |> resolved(meta)}
  end

  defp image_data_for_imgur_collection_api_url(imgur_api_url) do
    with headers when is_list(headers) <- get_imgur_headers() do
      image_data =
        imgur_api_url
        |> retry_get_until_success(headers)
        |> Map.get(:body)
        |> Poison.decode!()
        |> Kernel.get_in(["data", "images"])
        |> List.first()

      image_url = URI.parse(image_data["link"])
      meta = %{expected_content_type: image_data["type"]}
      [image_url, meta]
    else
      _err -> [nil, nil]
    end
  end

  # Performs a GET until we get response with a valid status code from ytdl.
  #
  # Oddly, valid status codes are 200, 302, and 500 since that indicates
  # the server successfully attempted to resolve the video URL(s). If we get
  # a different status code, this could indicate an outage or error in the
  # request.
  #
  # https://youtube-dl-api-server.readthedocs.io/en/latest/api.html#api-methods
  defp retry_get_until_valid_ytdl_response(url) do
    retry with: exponential_backoff() |> randomize |> cap(1_000) |> expiry(10_000) do
      Statix.increment("ret.media_resolver.ytdl.requests")

      case HTTPoison.get(url) do
        {:ok, %HTTPoison.Response{status_code: status_code} = resp}
        when status_code in @ytdl_valid_status_codes ->
          Statix.increment("ret.media_resolver.ytdl.ok")
          resp

        _ ->
          Statix.increment("ret.media_resolver.ytdl.errors")
          :error
      end
    after
      result -> result
    else
      error -> error
    end
  end

  defp get_root_host(nil) do
    nil
  end

  defp get_root_host(host) do
    # Drop subdomains
    host |> String.split(".") |> Enum.slice(-2..-1) |> Enum.join(".")
  end

  defp media_url_from_ytdl_headers(headers) do
    headers |> Enum.find(fn h -> h |> elem(0) |> String.downcase() === "location" end) |> elem(1)
  end

  defp get_imgur_headers() do
    with client_id when is_binary(client_id) <- module_config(:imgur_client_id),
         api_key when is_binary(api_key) <- module_config(:imgur_mashape_api_key) do
      [{"Authorization", "Client-ID #{client_id}"}, {"X-Mashape-Key", api_key}]
    else
      _err -> nil
    end
  end

  def resolved(:error), do: nil
  def resolved(%URI{} = uri), do: %Ret.ResolvedMedia{uri: uri}
  def resolved(%URI{} = uri, meta), do: %Ret.ResolvedMedia{uri: uri, meta: meta}

  def resolved(%URI{} = uri, %URI{} = audio_uri, meta),
    do: %Ret.ResolvedMedia{uri: uri, audio_uri: audio_uri, meta: meta}

  defp module_config(key) do
    Application.get_env(:ret, __MODULE__)[key]
  end

  defp ytdl_resolution(%MediaResolverQuery{quality: :low}), do: "[height<=480]"
  defp ytdl_resolution(%MediaResolverQuery{quality: :low_360}), do: "[height<=1440]"
  defp ytdl_resolution(%MediaResolverQuery{quality: :high_360}), do: "[height<=2160]"
  defp ytdl_resolution(_query), do: "[height<=720]"

  defp ytdl_qualifier(%MediaResolverQuery{quality: quality}) when quality in [:low, :high], do: "best"
  # for 360, we always grab dedicated audio track
  defp ytdl_qualifier(_query), do: "bestvideo"

  defp query_ytdl_audio?(%MediaResolverQuery{quality: quality}) when quality in [:low, :high], do: false
  defp query_ytdl_audio?(_query), do: true

  defp ytdl_format(query, "crunchyroll.com") do
    resolution = query |> ytdl_resolution
    ext = query |> ytdl_ext

    # Prefer a version with baked in (english) subtitles. Client locale should eventually determine this
    crunchy_format =
      ["best#{ext}[format_id*=hardsub-enUS]#{resolution}", "best#{ext}[format_id*=hardsub-enUS]"]
      |> Enum.join("/")

    crunchy_format <> "/" <> ytdl_format(query, nil)
  end

  defp ytdl_format(query, _root_host) do
    qualifier = query |> ytdl_qualifier
    resolution = query |> ytdl_resolution
    ext = query |> ytdl_ext
    ytdl_format(qualifier, resolution, ext)
  end

  defp ytdl_audio_format(query) do
    qualifier = "bestaudio"
    resolution = query |> ytdl_resolution
    ext = query |> ytdl_ext
    ytdl_format(qualifier, resolution, ext)
  end

  defp ytdl_format(qualifier, resolution, ext) do
    [
      "#{qualifier}#{ext}[protocol*=http]#{resolution}[format_id!=0]",
      "#{qualifier}#{ext}[protocol*=m3u8]#{resolution}[format_id!=0]",
      "#{qualifier}#{ext}[protocol*=http][format_id!=0]",
      "#{qualifier}#{ext}[protocol*=m3u8][format_id!=0]"
    ]
    |> Enum.join("/")
  end

  def ytdl_ext(%MediaResolverQuery{supports_webm: false}), do: "[ext=mp4]"
  def ytdl_ext(_query), do: ""
end
