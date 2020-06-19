class Channel2 < Tone
  @@RANGE = 0xFF16..0xFF19
  # def ===(value) : Bool
  #   value.is_a?(Int) && 0xFF16 <= value <= 0xFF19
  # end

  def [](index : Int) : UInt8
    case index
    when 0xFF16 then self.wavepattern_soundlength
    when 0xFF17 then self.volume_envelope
    when 0xFF18 then self.frequency_lo
    when 0xFF19 then self.frequency_hi
    else             raise "Reading from invalid channel 2 register: #{hex_str index.to_u16!}"
    end
  end

  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0xFF16 then self.wavepattern_soundlength = value
    when 0xFF17 then self.volume_envelope = value
    when 0xFF18 then self.frequency_lo = value
    when 0xFF19 then self.frequency_hi = value
    else             raise "Writing to invalid channel 2 register: #{hex_str index.to_u16!}"
    end
  end
end
