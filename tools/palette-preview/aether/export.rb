#!/usr/bin/env ruby
# Run Aether's unchanged CLI, record raw results plus input hashes.
require "json"
require "open3"
require "digest"
require "fileutils"

abort "Usage: export.rb AETHER_CHECKOUT AETHER_BINARY CACHE_DIRECTORY OUTPUT_JSON" unless ARGV.length == 4
checkout, binary, cache, output = ARGV.map { |path| File.expand_path(path) }
revision = File.read(File.join(__dir__, "UPSTREAM_REVISION")).strip
actual, err, status = Open3.capture3("git", "-C", checkout, "rev-parse", "HEAD")
abort err unless status.success?
abort "Aether revision mismatch: #{actual.strip}" unless actual.strip == revision
_, err, status = Open3.capture3("git", "-C", checkout, "diff", "--exit-code", "HEAD")
abort "Upstream tracked files must remain unchanged: #{err}" unless status.success?

def run_json(binary, *args)
  stdout, stderr, status = Open3.capture3(binary, *args)
  abort "Aether failed: #{args.inspect}\n#{stderr}\n#{stdout}" unless status.success?
  JSON.parse(stdout)
end

images = {}
Dir.glob(File.join(cache, "Full", "*")).sort.each do |path|
  next unless %w[.jpg .jpeg .png .webp].include?(File.extname(path).downcase)
  id = File.basename(path, ".*").sub(/\Aunsplash-/, "")
  variants = {}
  %w[dark light].each do |mode|
    flags = mode == "light" ? ["--light-mode"] : []
    extracted = run_json(binary, "--extract-palette", path, "--extract-mode", "normal", *flags, "--json")
    colors = extracted.fetch("colors")
    abort "Invalid ANSI palette" unless colors.length == 16 && colors.all? { |c| c.match?(/\A#[0-9a-fA-F]{6}\z/) }
    variables = run_json(binary, "--show-variables", JSON.generate(colors), *flags, "--json")
    colors.each_with_index do |color, i|
      abort "Aether variable mapping changed ANSI slot #{i}" unless variables.fetch("color#{i}").downcase == color.downcase
    end
    kitty = run_json(binary, "--preview-template", "kitty", path, *flags, "--json").fetch("content")
    kitty_colors = kitty.lines.map do |line|
      match = line.match(/\A(color\d+|background|foreground)\s+(#[0-9a-fA-F]{6})\s*\z/)
      [match[1], match[2]] if match
    end.compact.to_h
    (0...16).map { |i| "color#{i}" }.concat(%w[background foreground]).each do |key|
      abort "Official Kitty template differs for #{key}" unless kitty_colors.fetch(key).downcase == variables.fetch(key).downcase
    end
    variants[mode] = { "colors" => colors, "variables" => variables, "kitty" => kitty }
  end
  images[id] = { "file" => File.basename(path), "sha256" => Digest::SHA256.file(path).hexdigest, "palettes" => variants }
  puts "AETHER #{id} dark/light: original CLI colors and variables"
end
abort "No cached full-resolution images" if images.empty?
payload = {
  "schema" => 1, "engine" => "Aether", "repository" => "https://github.com/omacom/aether",
  "commit" => revision, "mode" => "normal", "adjustments" => "none",
  "launcher" => "cli.Run(os.Args[1:], EmbeddedTemplates)",
  "images" => images
}
FileUtils.mkdir_p(File.dirname(output))
File.write(output, JSON.pretty_generate(payload) + "\n")
puts "Saved #{images.size * 2} original palettes: #{output}"

