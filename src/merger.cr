require "semantic_version"

module Merger
  extend self
  
  VERSION = {{ `shards version __DIR__`.chomp.stringify }}
  ENTRY_PATTERN = /^##\s+\[([^\]]+)\]\s*(-\s*(\d{4}-\d{2}-\d{2}))?$/

  class Changelog
    class Section
      alias Version = SemanticVersion | String

      property version : Version
      property text : Array(String)
      property date : Time?

      def initialize(@text, version, date)
        @version = SemanticVersion.parse?(version) || version
        @date = Time::Format::ISO_8601_DATE.parse date if date
      end


      def initialize(other : self)
        @version = other.version
        @date = other.date
        @text = other.text
      end


      def to_s(io)
        if date
          io.puts "## [#{version}] - #{date}"
        else
          io.puts "## [#{version}]"
        end
        text[1...].each do |line|
          io.puts line
        end
      end

      def clone
        Section.new self
      end
    end
  
    property header : Array(String)
    property sections : Array(Section)
  
    def initialize(@header, @sections) end

    def self.parse(path : Path) : self
      parse File.read path
    end

    # Rough parsing of Keep a changelog fomatted files.
    # Mostly based around the pattern "## [version] - <date>" to detect section.
    # It is kinda brittle. 
    # Any footer will be included in the last section. 
    def self.parse(text : String) : self
      state = :header
      header = [] of String
      footer = [] of String
      section = [] of String
      version = ""
      date = ""
      sections = [] of Section
      text.each_line do |line|
        case {state, line =~ ENTRY_PATTERN}
        when {:header, nil} then header << line
        when {:header, _} 
          version = $1
          date = $3?
          section = [line]
          state = :section
        when {:section, nil} then section << line
        when {:section, _} 
          sections << Section.new section, version, date
          version = $1
          date = $3?
          section = [line]
        end
      end
      sections << Section.new section, version, date if section.size > 0
      Changelog.new header, sections
    end

    def to_s(io)
      header.each { |line| io.puts line }
      sections.each { |section| io.puts section }
    end

    def write(path : Path)
      File.open path, "w" { |io| io.puts self }
    end
  end

  alias Version = Changelog::Section::Version

  # Given three semantic versions *from*, *to*, *onto*, attempt to extract the intent (major minor patch)
  # between from and to, and apply it to rebase.
  # Example: from: 1.0.0, to: 1.1.0, onto: 3.4.5 => 3.5.0.
  # If any given version is not a semantic version, return *to*.
  # If it detect any downgrade in version or missing version, it will raise.
  def rebase_by_intent(from : Version, to : Version, onto : Version) : Version
    case {from, to, onto}
    when {SemanticVersion, SemanticVersion, SemanticVersion}
      case {to.major - from.major, to.minor - from.minor, to.patch - from.patch}
      when {1, 0, 0} then onto.bump_major
      when {0, 1, 0} then onto.bump_minor
      when {0, 0, 1} then onto.bump_patch
      else raise "Bad bump"
      end
    else to
    end 
  end

  # Given three changelog *base*, *upstream*, *our*, attempt to rebase *our* onto *upstream*, 
  # with *base* being the most recent common ancestor between *our* and *upstream*.
  # It will attempt to merge the header. It will raise of both *our* and *upstream* differ from *base* in different ways.
  # It does the same for each existing sections.
  # It raise if any of *upstream* or *base* don't have any versions.
  # It will keep existing non-semver versions and won't keep rebasing semantic versions if the chain is interupted by
  # a non-semver version.
  # It will upsert date on local version versions
  def rebase(base : Changelog, upstream : Changelog, our : Changelog) : Changelog
    # Check and merge header and common sections

    patched_header = case {base.header != our.header, base.header != upstream.header, our.header != upstream.header}
    when {true, true, true} then raise "Conflict on headers"
    when {true, false, true}, {_,_, false} then our.header
    when {false, true, true} then upstream.header
    else our.header
    end
    
    our_sections = our.sections.clone

    (1..(base.sections.size)).each do |i|
      our_text = our_sections[-i].text
      base_text = base.sections[-i].text
      upstream_text = upstream.sections[-i].text
      our_sections[-i].text = case {base_text != our_text, base_text != upstream_text, our_text != upstream_text}
      when {true, true, true} then raise "Conflict on section"
      when {true, false, true}, {_,_, false} then our_text
      when {false, true, true} then upstream_text
      else our_text 
      end
    end

    exclusive_sections = our_sections[0...(our_sections.size - base.sections.size)]
    raise "Cannot merge changelogs" unless upstream.sections.size > 0 && base.sections.size > 0
    current_base = base.sections.first.version
    last_upstream = upstream.sections.first.version
    exclusive_sections.reverse.each do |section|
      if (section.version.is_a? SemanticVersion)
        version = section.version
        last_upstream = section.version = rebase_by_intent current_base, version, last_upstream
        current_base = version
      end
    end
    exclusive_sections.each &.date = Time.utc
    upstream_only = upstream.sections[0...(upstream.sections.size - base.sections.size)]
    patched_base = our_sections[(our_sections.size - base.sections.size)..]
    Changelog.new patched_header, exclusive_sections + upstream_only + patched_base
  end
end
