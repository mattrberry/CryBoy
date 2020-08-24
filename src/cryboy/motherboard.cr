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
require "./ppu_shared"
{% if flag?(:fifo) %}
  require "./ppu_fifo"
{% else %}
  require "./ppu"
{% end %}
require "./scheduler"
require "./timer"
require "./util"

DISPLAY_SCALE = {% unless flag? :graphics_test %} 4 {% else %} 1 {% end %}

class Motherboard
  getter bootrom : String?
  getter cgb_ptr : Pointer(Bool) { pointerof(@cgb_enabled) }
  getter cartridge : Cartridge

  getter apu : APU { APU.new }
  getter cpu : CPU { CPU.new self }
  getter display : Display { Display.new self }
  getter interrupts : Interrupts { Interrupts.new }
  getter joypad : Joypad { Joypad.new }
  getter memory : Memory { Memory.new self }
  getter ppu : PPU { PPU.new self }
  getter scheduler : Scheduler { Scheduler.new }
  getter timer : Timer { Timer.new self }

  def initialize(@bootrom : String?, rom_path : String)
    @cartridge = Cartridge.new rom_path
    @cgb_enabled = !(bootrom.nil? && @cartridge.cgb == Cartridge::CGB::NONE)

    SDL.init(SDL::Init::VIDEO | SDL::Init::AUDIO | SDL::Init::JOYSTICK)
    LibSDL.joystick_open 0
    at_exit { SDL.quit }
  end

  def skip_boot : Nil
    cpu.skip_boot
    memory.skip_boot
    ppu.skip_boot
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
    skip_boot if @bootrom.nil?
    loop do
      handle_events
      cpu.tick 70224
    end
  end
end
