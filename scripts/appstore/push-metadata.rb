#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "optparse"
require "time"
require "uri"

API_BASE = "https://api.appstoreconnect.apple.com"
DEFAULT_METADATA_DIR = "metadata/app-store"
DEFAULT_BUNDLE_ID = "co.brevinb.TubPirates"
DEFAULT_PLATFORM = "IOS"
FIELD_LIMITS = {
  "description" => 4_000,
  "promotionalText" => 170,
  "keywords" => 100,
  "whatsNew" => 4_000
}.freeze

TEXT_FILE_ATTRIBUTES = {
  "description" => "description.txt",
  "keywords" => "keywords.txt",
  "promotionalText" => "promotional-text.txt",
  "supportUrl" => "support-url.txt",
  "whatsNew" => "whats-new.txt"
}.freeze

def abort_with(message)
  warn "error: #{message}"
  exit 1
end

def b64url(data)
  Base64.urlsafe_encode64(data).delete("=")
end

def fixed_width_integer(value, width)
  bytes = value.to_s(2)
  abort_with("ES256 signature integer is too large") if bytes.bytesize > width

  ("\x00".b * (width - bytes.bytesize)) + bytes
end

def der_ecdsa_signature_to_jose(der)
  sequence = OpenSSL::ASN1.decode(der)
  abort_with("unexpected ECDSA signature format") unless sequence.is_a?(OpenSSL::ASN1::Sequence)
  abort_with("unexpected ECDSA signature component count") unless sequence.value.length == 2

  r, s = sequence.value.map(&:value)
  fixed_width_integer(r, 32) + fixed_width_integer(s, 32)
end

def jwt_token(key_id:, issuer_id:, private_key_path:)
  private_key = OpenSSL::PKey.read(File.read(private_key_path))
  now = Time.now.to_i

  header = {
    alg: "ES256",
    kid: key_id,
    typ: "JWT"
  }

  payload = {
    iss: issuer_id,
    iat: now,
    exp: now + (19 * 60),
    aud: "appstoreconnect-v1"
  }

  signing_input = [
    b64url(JSON.generate(header)),
    b64url(JSON.generate(payload))
  ].join(".")

  digest = OpenSSL::Digest::SHA256.digest(signing_input)
  signature = private_key.dsa_sign_asn1(digest)
  "#{signing_input}.#{b64url(der_ecdsa_signature_to_jose(signature))}"
end

class AppStoreConnectClient
  def initialize(token)
    @token = token
  end

  def get(path, query = {})
    uri = build_uri(path, query)
    request = Net::HTTP::Get.new(uri)
    send_request(uri, request)
  end

  def get_all(path, query = {})
    data = []
    next_url = build_uri(path, query).to_s

    while next_url
      uri = URI(next_url)
      request = Net::HTTP::Get.new(uri)
      response = send_request(uri, request)
      data.concat(response.fetch("data", []))
      next_url = response.dig("links", "next")
    end

    data
  end

  def post(path, body)
    uri = build_uri(path)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body)
    send_request(uri, request)
  end

  def patch(path, body)
    uri = build_uri(path)
    request = Net::HTTP::Patch.new(uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body)
    send_request(uri, request)
  end

  private

  def build_uri(path, query = {})
    uri = URI("#{API_BASE}#{path}")
    uri.query = URI.encode_www_form(query) unless query.empty?
    uri
  end

  def send_request(uri, request)
    request["Authorization"] = "Bearer #{@token}"
    request["Accept"] = "application/json"

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    if response.body.nil? || response.body.empty?
      return {} if response.is_a?(Net::HTTPSuccess)

      abort_with("#{request.method} #{uri} failed: HTTP #{response.code} #{response.message}")
    end

    parsed = JSON.parse(response.body)
    return parsed if response.is_a?(Net::HTTPSuccess)
    details = parsed.fetch("errors", []).map do |error|
      status = error["status"]
      title = error["title"]
      detail = error["detail"]
      [status, title, detail].compact.join(" - ")
    end

    abort_with("#{request.method} #{uri} failed: #{details.join("; ")}")
  rescue JSON::ParserError
    abort_with("#{request.method} #{uri} returned non-JSON response: #{response.body}")
  end
end

def read_text(path)
  File.read(path, encoding: "UTF-8").sub(/\s+\z/, "")
end

def load_locale_metadata(locale_dir)
  fields = {}
  TEXT_FILE_ATTRIBUTES.each do |attribute, file_name|
    path = File.join(locale_dir, file_name)
    fields[attribute] = read_text(path) if File.file?(path)
  end
  fields
end

def validate_support_url!(locale, value)
  uri = URI.parse(value)
  return if uri.is_a?(URI::HTTP) && uri.host && %w[http https].include?(uri.scheme)

  abort_with("#{locale}/supportUrl must be an http or https URL")
rescue URI::InvalidURIError
  abort_with("#{locale}/supportUrl is not a valid URL")
end

def validate_metadata!(locale, fields)
  abort_with("#{locale} has no metadata files") if fields.empty?

  fields.each do |attribute, value|
    if attribute == "supportUrl"
      validate_support_url!(locale, value)
      next
    end

    limit = FIELD_LIMITS.fetch(attribute)
    length = attribute == "keywords" ? value.bytesize : value.length
    unit = attribute == "keywords" ? "bytes" : "characters"
    next if length <= limit

    abort_with("#{locale}/#{attribute} is #{length} #{unit}; limit is #{limit}")
  end
end

def metadata_by_locale(metadata_dir, requested_locales)
  abort_with("metadata directory not found: #{metadata_dir}") unless Dir.exist?(metadata_dir)

  locale_dirs = Dir.children(metadata_dir)
                   .map { |entry| File.join(metadata_dir, entry) }
                   .select { |path| File.directory?(path) }
                   .sort

  entries = {}
  locale_dirs.each do |path|
    locale = File.basename(path)
    next if requested_locales.any? && !requested_locales.include?(locale)

    fields = load_locale_metadata(path)
    validate_metadata!(locale, fields)
    entries[locale] = fields
  end

  abort_with("no locale metadata found in #{metadata_dir}") if entries.empty?
  entries
end

def find_app_id(client, bundle_id)
  apps = client.get_all("/v1/apps", "filter[bundleId]" => bundle_id)
  abort_with("no App Store Connect app found for bundle id #{bundle_id}") if apps.empty?
  abort_with("multiple apps found for bundle id #{bundle_id}") if apps.length > 1

  apps.first.fetch("id")
end

def find_version_id(client, app_id, version_string, version_id, platform)
  return version_id if version_id

  versions = client.get_all(
    "/v1/apps/#{app_id}/appStoreVersions",
    "filter[platform]" => platform,
    "limit" => "200"
  )
  abort_with("no #{platform} App Store versions found for app #{app_id}") if versions.empty?

  if version_string
    matches = versions.select { |version| version.dig("attributes", "versionString") == version_string }
    abort_with("no #{platform} App Store version found for version #{version_string}") if matches.empty?
    abort_with("multiple #{platform} App Store versions found for version #{version_string}") if matches.length > 1

    return matches.first.fetch("id")
  end

  versions.max_by { |version| Time.parse(version.dig("attributes", "createdDate") || "1970-01-01T00:00:00Z") }.fetch("id")
end

def localizations_by_locale(client, version_id)
  client.get_all(
    "/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations",
    "limit" => "200"
  ).each_with_object({}) do |localization, result|
    result[localization.dig("attributes", "locale")] = localization.fetch("id")
  end
end

def create_localization(client, version_id, locale)
  body = {
    data: {
      type: "appStoreVersionLocalizations",
      attributes: {
        locale: locale
      },
      relationships: {
        appStoreVersion: {
          data: {
            type: "appStoreVersions",
            id: version_id
          }
        }
      }
    }
  }

  client.post("/v1/appStoreVersionLocalizations", body).fetch("data").fetch("id")
end

def patch_localization(client, localization_id, fields)
  body = {
    data: {
      type: "appStoreVersionLocalizations",
      id: localization_id,
      attributes: fields
    }
  }

  client.patch("/v1/appStoreVersionLocalizations/#{localization_id}", body)
end

options = {
  metadata_dir: DEFAULT_METADATA_DIR,
  bundle_id: ENV.fetch("ASC_BUNDLE_ID", DEFAULT_BUNDLE_ID),
  key_id: ENV["ASC_KEY_ID"],
  issuer_id: ENV["ASC_ISSUER_ID"],
  private_key_path: ENV["ASC_PRIVATE_KEY_PATH"],
  platform: DEFAULT_PLATFORM,
  locales: [],
  apply: false
}

OptionParser.new do |parser|
  parser.banner = "Usage: scripts/appstore/push-metadata.rb [options]"

  parser.on("--apply", "Write changes to App Store Connect. Without this, the script only validates and previews.") do
    options[:apply] = true
  end

  parser.on("--metadata-dir DIR", "Metadata root directory. Default: #{DEFAULT_METADATA_DIR}") do |value|
    options[:metadata_dir] = value
  end

  parser.on("--bundle-id ID", "Bundle ID. Default: ASC_BUNDLE_ID or #{DEFAULT_BUNDLE_ID}") do |value|
    options[:bundle_id] = value
  end

  parser.on("--version VERSION", "App Store version string to update, for example 1.2.3") do |value|
    options[:version_string] = value
  end

  parser.on("--version-id ID", "Specific App Store version resource ID to update") do |value|
    options[:version_id] = value
  end

  parser.on("--platform PLATFORM", "App Store platform. Default: #{DEFAULT_PLATFORM}") do |value|
    options[:platform] = value
  end

  parser.on("--locale LOCALE", "Only process this locale. May be repeated.") do |value|
    options[:locales] << value
  end

  parser.on("--key-id ID", "App Store Connect API key ID. Default: ASC_KEY_ID") do |value|
    options[:key_id] = value
  end

  parser.on("--issuer-id ID", "App Store Connect issuer ID. Default: ASC_ISSUER_ID") do |value|
    options[:issuer_id] = value
  end

  parser.on("--private-key-path PATH", "Path to AuthKey_XXXX.p8. Default: ASC_PRIVATE_KEY_PATH") do |value|
    options[:private_key_path] = value
  end

  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
end.parse!

abort_with("ASC_KEY_ID or --key-id is required") if options[:key_id].to_s.empty?
abort_with("ASC_ISSUER_ID or --issuer-id is required") if options[:issuer_id].to_s.empty?
abort_with("ASC_PRIVATE_KEY_PATH or --private-key-path is required") if options[:private_key_path].to_s.empty?
abort_with("private key not found: #{options[:private_key_path]}") unless File.file?(options[:private_key_path])
abort_with("use --version or --version-id, not both") if options[:version_string] && options[:version_id]

metadata = metadata_by_locale(options[:metadata_dir], options[:locales])
token = jwt_token(
  key_id: options[:key_id],
  issuer_id: options[:issuer_id],
  private_key_path: options[:private_key_path]
)
client = AppStoreConnectClient.new(token)

app_id = find_app_id(client, options[:bundle_id])
version_id = find_version_id(
  client,
  app_id,
  options[:version_string],
  options[:version_id],
  options[:platform]
)

puts "App: #{options[:bundle_id]} (#{app_id})"
puts "Version ID: #{version_id}"
puts "Mode: #{options[:apply] ? 'apply' : 'dry-run'}"

localizations = localizations_by_locale(client, version_id)

metadata.each do |locale, fields|
  localization_id = localizations[locale]

  if localization_id.nil?
    if options[:apply]
      localization_id = create_localization(client, version_id, locale)
      localizations[locale] = localization_id
      puts "created #{locale}: #{localization_id}"
    else
      puts "would create #{locale}"
    end
  end

  summary = fields.map { |attribute, value| "#{attribute}=#{value.length}" }.join(", ")

  if options[:apply]
    patch_localization(client, localization_id, fields)
    puts "updated #{locale}: #{summary}"
  else
    puts "would update #{locale}: #{summary}"
  end
end
