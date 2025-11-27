require "./spec_helper"

describe Merger do

  it "can parse changelogs" do
    changelog = Merger::Changelog.parse(<<-MD)
      This is a changelog
      It has some header lines
      
      ## [Unreleased]
      This is a section

            
      ## [15.4.6-alpha] - 2025-11-26
      This is another section
      MD

    changelog.header.size.should eq 3
    changelog.sections.size.should eq 2
    changelog.sections[0].version.should eq "Unreleased"
    changelog.sections[0].date.should eq nil
    changelog.sections[1].version.should eq SemanticVersion.new 15, 4, 6, "alpha"
    changelog.sections[1].date.should be_truthy
  end

  it "can rebase version based on intent" do
    [
      {base: "1.0.0", current: "2.0.0", upstream: "3.4.5", expect: "4.0.0"},
      {base: "1.0.0", current: "1.1.0", upstream: "3.4.5", expect: "3.5.0"},
      {base: "1.0.0", current: "1.0.1", upstream: "3.4.5", expect: "3.4.6"},
      {base: "1.0.0", current: "Unreleased", upstream: "3.4.5", expect: "Unreleased"},
    ].each do |sample|
      base = SemanticVersion.parse?(sample[:base]) || sample[:base]
      current = SemanticVersion.parse?(sample[:current]) || sample[:current]
      upstream = SemanticVersion.parse?(sample[:upstream]) || sample[:upstream]
      expect = SemanticVersion.parse?(sample[:expect]) || sample[:expect]
      Merger.rebase_by_intent(base, current, upstream).should eq expect
    end
  end

  it "can only rebase version in simple cases" do
    [
      {base: "1.0.0", current: "0.1.0", upstream: "3.4.5"}, # Downgrading
      {base: "1.0.0", current: "1.2.0", upstream: "3.4.5"}, # Jumping versions
    ].each do |sample|
      base = SemanticVersion.parse?(sample[:base]) || sample[:base]
      current = SemanticVersion.parse?(sample[:current]) || sample[:current]
      upstream = SemanticVersion.parse?(sample[:upstream]) || sample[:upstream]
      expect_raises(Exception) { Merger.rebase_by_intent base, current, upstream }.message.should eq "Bad bump"
    end
  end

  it "can rebase changelogs" do
  
    base = Merger::Changelog.parse(<<-MD)
      This is a changelog
      It has some header lines
      
      ## [1.0.0]
      This is a section
            
      ## [0.0.1-alpha] - 2023-11-26
      This is another section
      MD

    upstream = Merger::Changelog.parse(<<-MD)
      This is a changelog
      It has some header lines
      Also I changed the header

      ## [2.0.0]
      Broke everything

      ## [1.0.1]
      Fixed thing

      ## [1.0.0]
      This is a section, I added context upstream
            
      ## [0.0.1-alpha] - 2023-11-26
      This is another section
      MD

    local = Merger::Changelog.parse(<<-MD)
      This is a changelog
      It has some header lines

      ## [Unreleased] - 1999-11-26
      WIP

      ## [1.1.0]
      Add stuff

      ## [1.0.0]
      This is a section
            
      ## [0.0.1-alpha] - 2023-11-26
      This is another section, I fixed a typo
      MD

    rebased = Merger.rebase base, upstream, local

    rebased.header.size.should eq 4
    rebased.sections.size.should eq 6
    rebased.sections[0].version.should eq "Unreleased"
    rebased.sections[0].date.should be_truthy
    rebased.sections[0].date.not_nil!.year.should be_close Time.utc.year, 1
    rebased.sections[1].version.should eq SemanticVersion.parse "2.1.0"
    rebased.sections[1].date.should be_truthy
    rebased.sections[2].version.should eq SemanticVersion.parse "2.0.0"
    rebased.sections[3].version.should eq SemanticVersion.parse "1.0.1"
    rebased.sections[4].version.should eq SemanticVersion.parse "1.0.0"
    rebased.sections[4].text[1].should eq "This is a section, I added context upstream"
    rebased.sections[5].version.should eq SemanticVersion.parse "0.0.1-alpha"    
    rebased.sections[5].text[1].should eq "This is another section, I fixed a typo"
  end
end