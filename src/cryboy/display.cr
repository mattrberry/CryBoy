class Display
  @colors = [SDL::Color[0xE0, 0xF8, 0xCF], SDL::Color[0x86, 0xC0, 0x6C], SDL::Color[0x30, 0x68, 0x50], SDL::Color[0x07, 0x17, 0x20]]

  def initialize(@scale = 2, @width = 160, @height = 144, title : String? = nil)
    @window = SDL::Window.new("CryBoy" + (title.nil? ? "" : " - #{title}"), @width * @scale, @height * @scale)
    @renderer = SDL::Renderer.new @window
    @renderer.logical_size = {160, 144}
  end

  def draw(framebuffer : Array(Array(UInt8)), palette : UInt8) : Nil
    framebuffer.each_with_index do |scanline, y|
      scanline.each_with_index do |color, x|
        @renderer.draw_color = @colors[color]
        @renderer.draw_point x, y
      end
    end
    @renderer.present
  end
end

###############################################################################
# Potential start to using textures rather than drawing colors.
# Could improve render speeds.

# PIXELFORMAT_RGB24       = (1 << 28) | (7 << 24) | (1 << 20) | (0 << 16) | (24 << 8) | (3 << 0)
# TEXTUREACCESS_STREAMING = 1

# @texture = LibSDL.create_texture @renderer, PIXELFORMAT_RGB24, TEXTUREACCESS_STREAMING, @width, @height

# @framebuffer2 = Bytes.new 160 * 144 * 3
# framebuffer.each_with_index do |scanline, y|
#   scanline.each_with_index do |color, x|
#     @framebuffer2.not_nil![(160 * y + x) * 3 + 0] = @colors[color].r.to_u8
#     @framebuffer2.not_nil![(160 * y + x) * 3 + 1] = @colors[color].g.to_u8
#     @framebuffer2.not_nil![(160 * y + x) * 3 + 2] = @colors[color].b.to_u8
#   end
# end
# LibSDL.update_texture @texture, nil, pointerof(@framebuffer2), 160 * 3
# @renderer.clear
# @renderer.copy @texture
# @renderer.present
