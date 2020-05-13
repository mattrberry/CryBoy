require "./gb/motherboard"

module Gb
  VERSION = "0.1.0"

  extend self

  def run
    if ARGV.size != 1
      raise "Only arg should be the path to the rom"
    end

    motherboard = Motherboard.new ARGV[0]
    motherboard.run
  end
end

unless PROGRAM_NAME.includes?("crystal-run-spec")
  Gb.run
end
