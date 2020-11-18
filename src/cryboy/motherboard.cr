require "sdl"
require "./apu"
require "./cartridge"
require "./cpu"
require "./display"
require "./interrupts"
require "./joypad"
require "./mbc/*"
require "./memory"
require "./opcodes"
require "./ppu"
require "./scanline_ppu"
require "./fifo_ppu"
require "./scheduler"
require "./timer"
require "./util"

DISPLAY_SCALE = {% unless flag? :graphics_test %} 4 {% else %} 1 {% end %}

class Motherboard
  getter bootrom : String?
  getter cgb_ptr : Pointer(Bool) { pointerof(@cgb_enabled) }
  getter cartridge : Cartridge

  getter! apu : APU
  getter! cpu : CPU
  getter! display : Display
  getter! interrupts : Interrupts
  getter! joypad : Joypad
  getter! memory : Memory
  getter! ppu : PPU
  getter! scheduler : Scheduler
  getter! timer : Timer

  def initialize(@bootrom : String?, rom_path : String, @fifo : Bool)
    @cartridge = Cartridge.new rom_path
    @cgb_enabled = !(bootrom.nil? && @cartridge.cgb == Cartridge::CGB::NONE)

    SDL.init(SDL::Init::VIDEO | SDL::Init::AUDIO | SDL::Init::JOYSTICK)
    LibSDL.joystick_open 0
    at_exit { SDL.quit }
  end

  def post_init : Nil
    @scheduler = Scheduler.new
    @interrupts = Interrupts.new
    @apu = APU.new self
    @display = Display.new self
    @joypad = Joypad.new
    @ppu = @fifo ? FifoPPU.new self : ScanlinePPU.new self
    @timer = Timer.new self
    @memory = Memory.new self
    @cpu = CPU.new self
    skip_boot if @bootrom.nil?
  end

  private def skip_boot : Nil
    cpu.skip_boot
    memory.skip_boot
    ppu.skip_boot
    timer.skip_boot
  end

  def handle_events : Nil
    while event = SDL::Event.poll
      case event
      when SDL::Event::Quit then exit 0
      when SDL::Event::Keyboard,
           SDL::Event::JoyHat,
           SDL::Event::JoyButton then joypad.handle_joypad_event event
      else nil
      end
    end
  end

  def run : Nil
    loop do
      handle_events
      cpu.tick 70224
    end
  end
end
