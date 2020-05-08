require "./cartridge"
require "./cpu"
require "./display"
require "./memory"
require "./ppu"

class Motherboard
  def initialize(rom_path : String)
    @cartridge = Cartridge.new rom_path
    # puts "Title: #{@cartridge.title}"
    # puts "Size:  #{@cartridge.rom_size}"
    @memory = Memory.new @cartridge
    @cpu = CPU.new @memory
    @ppu = PPU.new @memory
    @display = Display.new
    loop do
      @cpu.tick
      @display.draw @ppu.frame
    end
  end

  def run : Nil
    @cpu.tick
  end
end
