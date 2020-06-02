require "sdl"
require "./cartridge"
require "./cpu"
require "./display"
require "./interrupts"
require "./joypad"
require "./mbc/*"
require "./memory"
require "./ppu"
require "./timer"
require "./util"

class Motherboard
  def initialize(bootrom : String?, rom : String)
    SDL.init(SDL::Init::VIDEO | SDL::Init::AUDIO | SDL::Init::JOYSTICK)
    at_exit { SDL.quit }

    LibSDL.joystick_open 0

    @cartridge = Cartridge.new rom
    @interrupts = Interrupts.new
    @ppu = PPU.new @interrupts
    @joypad = Joypad.new
    @timer = Timer.new @interrupts
    @memory = Memory.new @cartridge, @interrupts, @ppu, @joypad, @timer, bootrom
    @cpu = CPU.new @memory, @interrupts, @ppu, @timer, boot: !bootrom.nil?
    @display = Display.new title: @cartridge.title
  end

  def handle_events : Nil
    while event = SDL::Event.poll
      case event
      when SDL::Event::Quit                                                then exit 0
      when SDL::Event::Keyboard, SDL::Event::JoyHat, SDL::Event::JoyButton then @joypad.handle_joypad_event event
      else                                                                      nil
      end
    end
  end

  def run : Nil
    repeat hz: 60 do
      handle_events
      @cpu.tick 70224
      @display.draw @ppu.framebuffer, @memory[0xFF47] # 0xFF47 defines the color palette
    end
  end
end
