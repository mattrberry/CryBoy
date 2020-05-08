require "crsfml"

class Display
  @colors = [SF::Color.new(0, 0, 0), SF::Color.new(85, 85, 85), SF::Color.new(170, 170, 170), SF::Color.new(255, 255, 255)]

  def initialize(@scale = 4, @width = 160, @height = 144)
    @window = SF::RenderWindow.new(
      SF::VideoMode.new(@width * @scale, @height * @scale),
      "CryBoy",
      settings: SF::ContextSettings.new(depth: 24, antialiasing: 8)
    )
  end

  def draw(frame : Bytes) : Nil
    @window.poll_event # keep the window alive
    @window.clear
    (0...@width).each do |x|
      (0...@height).each do |y|
        shape = SF::RectangleShape.new(SF.vector2(@scale, @scale))
        shape.position = SF.vector2(x * @scale, y * @scale)
        shape.fill_color = @colors[frame[y * @width + x]]
        @window.draw shape
      end
    end
    @window.display
  end
end
