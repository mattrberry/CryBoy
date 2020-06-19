class Channel1 < ToneChannel # todo: sweep
  @@RANGE = 0xFF10..0xFF14

  @sweep : UInt8 = 0x80

  def sweep_step : Nil # todo
  end

  def [](index : Int) : UInt8
    case index
    when 0xFF10 then @sweep # todo
    when 0xFF11 then self.wavepattern_soundlength
    when 0xFF12 then self.volume_envelope
    when 0xFF13 then self.frequency_lo
    when 0xFF14 then self.frequency_hi
    else             raise "Reading from invalid channel 1 register: #{hex_str index.to_u16!}"
    end
  end

  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0xFF10 then @sweep = 0x80_u8 | value # todo
    when 0xFF11 then self.wavepattern_soundlength = value
    when 0xFF12 then self.volume_envelope = value
    when 0xFF13 then self.frequency_lo = value
    when 0xFF14 then self.frequency_hi = value
    else             raise "Writing to invalid channel 1 register: #{hex_str index.to_u16!}"
    end
  end
end
