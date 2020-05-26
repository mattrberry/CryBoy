class Joypad
  property button_keys = false
  property direction_keys = false

  # describes if a button is CURRENTLY PRESSED
  property down = false
  property up = false
  property left = false
  property right = false
  property start = false
  property :select # select is a keyword
  @select = false
  property b = false
  property a = false

  def read : UInt8
    array_to_uint8 [
      0,
      0,
      !@button_keys,
      !@direction_keys,
      !((@down && @direction_keys) || (@start && @button_keys)),
      !((@up && @direction_keys) || (@select && @button_keys)),
      !((@left && @direction_keys) || (@b && @button_keys)),
      !((@right && @direction_keys) || (@a && @button_keys)),
    ]
  end

  def write(value : UInt8) : Nil
    @button_keys = (value >> 5) & 0x1 == 0
    @direction_keys = (value >> 4) & 0x1 == 0
  end
end
