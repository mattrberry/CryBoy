require "sdl"

class Display
  @colors = [SDL::Color[0x00], SDL::Color[0xAA], SDL::Color[0x55], SDL::Color[0xFF]]

  def initialize(@scale = 4, @width = 160, @height = 144)
    SDL.init(SDL::Init::VIDEO)
    at_exit { SDL.quit }
    @window = SDL::Window.new("CryBoy", @width * @scale, @height * @scale)
    @renderer = SDL::Renderer.new @window
  end

  def draw_scanlines : Nil
    @renderer.draw_color = SDL::Color[0xFF, 0x00, 0x00]
    (1...@width).each do |col|
      @renderer.draw_line col * @scale, 0, col * @scale, @height * @scale
    end
    (1...@height).each do |row|
      @renderer.draw_line 0, row * @scale, @width * @scale, row * @scale
    end
  end

  def draw(framebuffer : Array(Array(UInt8))) : Nil
    framebuffer.each_with_index do |scanline, y|
      scanline.each_with_index do |color, x|
        @renderer.draw_color = @colors[color]
        @renderer.fill_rect(x * @scale, y * @scale, @scale, @scale)
      end
    end

    # draw_scanlines
    @renderer.present
  end
end
