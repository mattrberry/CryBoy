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
{% if flag?(:fifo) %}
require "./ppu_fifo"
{% else %}
require "./ppu"
{% end %}
require "./timer"
require "./util"

class Motherboard
  def initialize(bootrom : String?, rom_path : String)
    SDL.init(SDL::Init::VIDEO | SDL::Init::AUDIO | SDL::Init::JOYSTICK)
    at_exit { SDL.quit }

    LibSDL.joystick_open 0

    @cartridge = Cartridge.new rom_path
    @cgb_enabled = !(bootrom.nil? && @cartridge.cgb == Cartridge::CGB::NONE)
    @interrupts = Interrupts.new
    @display = Display.new title: @cartridge.title
    @ppu = PPU.new @display, @interrupts, pointerof(@cgb_enabled)
    @apu = APU.new
    @timer = Timer.new @interrupts
    @joypad = Joypad.new
    @memory = Memory.new @cartridge, @interrupts, @ppu, @apu, @timer, @joypad, pointerof(@cgb_enabled), bootrom
    @cpu = CPU.new @memory, @interrupts, @ppu, @apu, @timer, boot: !bootrom.nil?
  end

  def handle_events : Nil
    while event = SDL::Event.poll
      case event
      when SDL::Event::Quit then exit 0
      when SDL::Event::Keyboard,
           SDL::Event::JoyHat,
           SDL::Event::JoyButton then @joypad.handle_joypad_event event
      else nil
      end
    end
  end

  def run : Nil
    loop do
      handle_events
      @cpu.tick 70224
    end
  end
end
