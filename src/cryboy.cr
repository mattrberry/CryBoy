require "./cryboy/motherboard"

module CryBoy
  VERSION = "0.1.0"

  extend self

  def run
    raise "Provide the (optional) bootrom and game rom as arguments." if ARGV.size < 1 || ARGV.size > 2
    rom = ARGV[0] if ARGV.size == 1
    bootrom = ARGV[0] if ARGV.size == 2
    rom = ARGV[1] if ARGV.size == 2

    motherboard = Motherboard.new bootrom, rom.not_nil!
    motherboard.run
  end
end

unless PROGRAM_NAME.includes?("crystal-run-spec")
  CryBoy.run
end
