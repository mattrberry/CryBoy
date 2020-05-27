require "sdl"
require "./cartridge"
require "./cpu"
require "./display"
require "./joypad"
require "./mbc/*"
require "./memory"
require "./ppu"
require "./timer"
require "./util"

class Motherboard
  def initialize(bootrom : String?, rom : String)
    @cartridge = Cartridge.new rom
    @joypad = Joypad.new
    @timer = Timer.new
    @memory = Memory.new @cartridge, @joypad, @timer, bootrom
    @cpu = CPU.new @memory, @timer, boot: !bootrom.nil?
    @ppu = PPU.new @memory
    @display = Display.new title: @cartridge.title
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
    repeat hz: 60 do
      while event = SDL::Event.poll
        case event
        when SDL::Event::Quit then exit 0
        when SDL::Event::Keyboard
          case event.sym
          when .down?, .d?  then @joypad.down = event.keydown?
          when .up?, .e?    then @joypad.up = event.keydown?
          when .left?, .s?  then @joypad.left = event.keydown?
          when .right?, .f? then @joypad.right = event.keydown?
          when .semicolon?  then @joypad.start = event.keydown?
          when .l?          then @joypad.select = event.keydown?
          when .b?, .j?     then @joypad.b = event.keydown?
          when .a?, .k?     then @joypad.a = event.keydown?
          else                   nil
          end
        else nil
        end
      end
      if @ppu.lcd_enabled?
        (0...144).each do |y|
          check_lyc y

          stat_mode = 2
          @cpu.tick 80

          stat_mode = 3
          @cpu.tick 172
          @ppu.scanline y

          stat_mode = 0
          @cpu.tick 204
        end
        @memory.vblank = true
        @display.draw @ppu.framebuffer, @memory[0xFF47] # 0xFF47 defines the color palette

        (144...154).each do |y|
          check_lyc y
          @cpu.tick 456
        end
      else
        # todo render blank screen
        stat_mode = 0
        # set ly
        @memory[0xFF44] = 0x00_u8
        # tick 1 full screen time
        @cpu.tick 154 * 456
      end
    end
  end
end
