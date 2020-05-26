require "sdl"

class Display
  @colors = [SDL::Color[0xFF], SDL::Color[0xAA], SDL::Color[0x55], SDL::Color[0x00]]

  def initialize(@scale = 2, @width = 160, @height = 144)
    SDL.init(SDL::Init::VIDEO)
    at_exit { SDL.quit }
    @window = SDL::Window.new("CryBoy", @width * @scale, @height * @scale)
    @renderer = SDL::Renderer.new @window
  end

  def draw(framebuffer : Array(Array(UInt8)), palette : UInt8) : Nil
    colors = [@colors[palette & 0x3], @colors[(palette >> 2) & 0x3], @colors[(palette >> 4) & 0x3], @colors[(palette >> 6) & 0x3]]
    framebuffer.each_with_index do |scanline, y|
      scanline.each_with_index do |color, x|
        @renderer.draw_color = colors[color]
        @renderer.fill_rect(x * @scale, y * @scale, @scale, @scale)
      end
    end
    @renderer.present
  end
end
