require "sdl"
require "./cartridge"
require "./cpu"
require "./display"
require "./memory"
require "./ppu"
require "./util"

class Motherboard
  def initialize(bootrom : String?, rom : String)
    @cartridge = Cartridge.new bootrom, rom
    # puts "Title: #{@cartridge.title}"
    # puts "Size:  #{@cartridge.rom_size}"
    @memory = Memory.new @cartridge
    @cpu = CPU.new @memory, boot: !bootrom.nil?
    @ppu = PPU.new @memory
    @display = Display.new
  end

  def timer_divider : Nil
    @memory[0xFF04] &+= 1
  end

  def timer_counter : Nil
    @memory[0xFF05] &+= 1
    if @memory[0xFF05] == 0_u8
      @memory[0xFF05] = @memory[0xFF06]
      @memory.timer = true
    end
  end

  def check_lyc(y : Int) : Nil
    # set ly
    @memory[0xFF44] = y.to_u8
    # check lyc & set coincidence flag
    if y.to_u8 == @memory[0xFF45]
      @memory[0xFF41] |= 0b100
      if @memory[0xFF41] & 0b01000000 > 0
        @memory.lcd_stat = true
      end
    else
      @memory[0xFF41] &= ~0b100
    end
  end

  def stat_mode=(mode : UInt8) : Nil
    @memory[0xFF41] = (@memory[0xFF41] & 0b11111100) | mode
  end

  def run : Nil
    # repeat hz: 60, in_fiber: true { @display.draw @ppu.frame }
    # repeat hz: 16384, in_fiber: true { timer_divider }
    # repeat hz: @memory[0xFF07] == 0b00 ? 4096 : @memory[0xFF07] == 0b01 ? 262144 : @memory[0xFF07] == 0b10 ? 65536 : 16384, in_fiber: true { timer_counter }
    repeat hz: 60 do
      while event = SDL::Event.poll
        case event
        when SDL::Event::Quit
          puts "quit"
          exit 0
        when SDL::Event::Keyboard
          if event.mod.lctrl? && event.sym.q?
            puts "ctrl+q"
            exit 0
          end
        else nil # Crystal will soon require exhaustive cases
        end
      end
      if @ppu.lcd_enabled?
        (0...144).each do |y|
          check_lyc y

          stat_mode = 2
          @cpu.tick 80

          stat_mode = 3
          @cpu.tick 170
          @ppu.scanline y

          stat_mode = 0
          @cpu.tick 206
        end
        @memory.vblank = true
        @display.draw @ppu.framebuffer, @memory[0xFF47] # 0xFF47 defines the color palette
        # @display.draw_all_tiles @memory, @ppu.scanlines

        (144...154).each do |y|
          check_lyc y
          @cpu.tick 456
        end
      else
        # todo render blank screen
        stat_mode = 0
        # set ly
        @memory[0xFF44] = 0_u8
        # tick 1 full screen time
        @cpu.tick 154 * 456
      end
    end
  end
end
