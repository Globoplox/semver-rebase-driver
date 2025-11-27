require "option_parser"
require "./merger"

command = nil
base = nil
upstream = nil
our = nil
output = nil
changelog_parser = nil
parser = OptionParser.new do |parser|
  parser.banner = "Usage: semver-rebase-driver [subcommand] [arguments]"
  parser.on("changelog", "Rebase a semantic version project changelog") do
    command = :changelog
    parser.banner = "Usage: semver-rebase-driver changelog -b <base-path> -u <upstream-path> -l <local-path> -o <output-path>"
    parser.on("-b PATH", "--base=PATH", "Specify the path of the common ancestor changlog") { |_base| base = _base }
    parser.on("-u PATH", "--upstream=PATH", "Specify the path of the upstream changlog") { |_upstream| upstream = _upstream }
    parser.on("-l PATH", "--local=PATH", "Specify the path of the local changlog") { |_our| our = _our }
    parser.on("-o PATH", "--output=PATH", "Specify the path of the output changlog") { |_output| output = _output }
    changelog_parser = parser
  end
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit 0
  end
end

parser.parse

case command
when :changelog
  unless base && upstream && our && output
    puts changelog_parser
    exit 1
  end

  File.open output.not_nil!, "w", &.puts Merger.rebase(
    Merger::Changelog.parse(Path[base.not_nil!]),
    Merger::Changelog.parse(Path[upstream.not_nil!]),
    Merger::Changelog.parse(Path[our.not_nil!])
  )

else
  puts parser
  exit 1
end
