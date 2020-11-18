require "colorize"
require "option_parser"

require "./cryboy/motherboard"

module CryBoy
  VERSION = "0.1.0"

  extend self

  def run
    fifo = false
    pink = false
    rom = nil
    bootrom = nil
    OptionParser.parse do |parser|
      parser.banner = "#{"CryBoy".colorize.bold} - An accurate and readable Game Boy emulator in Crystal"
      parser.separator
      parser.separator("Usage: bin/cryboy [BOOTROM] ROM")
      parser.separator
      parser.on("-h", "--help", "Show the help message") do
        puts parser
        exit
      end
      parser.on("--fifo", "Enable FIFO rendering") { fifo = true }
      parser.on("--pink", "Set the 2-bit DMG color theme to pink") { pink = true }
      parser.unknown_args do |args|
        case args.size
        when 1 then rom = args[0]
        when 2 then bootrom, rom = args[0], args[1]
        else        abort parser
        end
      end
    end

    motherboard = Motherboard.new bootrom, rom.not_nil!, fifo
    motherboard.post_init
    motherboard.run
  end
end

unless PROGRAM_NAME.includes?("crystal-run-spec")
  CryBoy.run
end
