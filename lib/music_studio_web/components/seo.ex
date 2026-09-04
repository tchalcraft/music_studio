defmodule MusicStudioWeb.SEO do
  @moduledoc """
  SEO helpers for meta tags, Open Graph, Twitter cards, and structured data.
  Provides defaults for the whole site with per-page overrides via assigns.
  """
  use MusicStudioWeb, :html

  @site_name "Tristan Chalcraft Music"
  @site_description "In-person voice, piano, and guitar lessons in White Rock, BC — from a professional opera singer, for beginners and returning musicians of all ages."
  @site_url System.get_env("SITE_URL") || "https://tristanchalcraftmusic.com"
  @default_image "/images/tristan.jpeg"

  @doc """
  Renders meta tags for the page: description, Open Graph, Twitter card, and canonical.
  Uses assigns overrides with fallback to site-wide defaults.
  """
  attr :page_title, :string, default: @site_name
  attr :meta_description, :string, default: @site_description
  attr :og_title, :string, default: nil
  attr :og_description, :string, default: nil
  attr :og_image, :string, default: @default_image
  attr :og_type, :string, default: "website"
  attr :canonical_url, :string, default: nil

  def seo_meta_tags(assigns) do
    meta_tags(assigns)
  end

  def meta_tags(assigns) do
    meta_description = assigns.meta_description || @site_description
    og_title = assigns.og_title || assigns.page_title
    og_description = assigns.og_description || meta_description
    site_url = assigns[:site_url] || @site_url

    assigns =
      assigns
      |> assign(:meta_description, meta_description)
      |> assign(:og_title, og_title)
      |> assign(:og_description, og_description)
      |> assign(:site_url, site_url)

    ~H"""
    <meta name="description" content={@meta_description} />
    <meta property="og:title" content={@og_title} />
    <meta property="og:description" content={@og_description} />
    <meta property="og:type" content={@og_type} />
    <meta property="og:url" content={@canonical_url || @site_url} />
    <meta property="og:image" content={url_for_image(@og_image)} />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content={@og_title} />
    <meta name="twitter:description" content={@og_description} />
    <meta name="twitter:image" content={url_for_image(@og_image)} />
    <%= if @canonical_url do %>
      <link rel="canonical" href={@canonical_url} />
    <% end %>
    """
  end

  @doc """
  Renders JSON-LD structured data for a local music school/business.
  """
  def music_school_schema(assigns) do
    schema = %{
      "@context" => "https://schema.org",
      "@type" => "MusicSchool",
      "name" => @site_name,
      "description" => @site_description,
      "url" => @site_url,
      "image" => url_for_image(@default_image),
      "areaServed" => %{
        "@type" => "City",
        "name" => "White Rock",
        "addressRegion" => "BC",
        "addressCountry" => "CA"
      },
      "priceRange" => "$35–$70"
    }

    assigns = assign(assigns, :schema_json, Jason.encode!(schema))

    ~H"""
    <script type="application/ld+json">
      <%= raw(@schema_json) %>
    </script>
    """
  end

  defp url_for_image(nil), do: @site_url <> @default_image

  defp url_for_image(path) when is_binary(path) do
    if String.starts_with?(path, "http") do
      path
    else
      @site_url <> path
    end
  end
end
