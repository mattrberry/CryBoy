class Channel1 < Tone # todo: sweep
  def ===(value) : Bool
    value.is_a?(Int) && 0xFF10 <= value <= 0xFF14
  end

  @sweep : UInt8 = 0x00

  def sweep_step : Nil # todo
  end

  def [](index : Int) : UInt8
    case index
    when 0xFF10 then 0x00_u8
    when 0xFF11 then self.wavepattern_soundlength
    when 0xFF12 then self.volume_envelope
    when 0xFF13 then self.frequency_lo
    when 0xFF14 then self.frequency_hi
    else             raise "Reading from invalid channel 1 register: #{hex_str index.to_u16!}"
    end
  end

  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0xFF10
    when 0xFF11 then self.wavepattern_soundlength = value
    when 0xFF12 then self.volume_envelope = value
    when 0xFF13 then self.frequency_lo = value
    when 0xFF14 then self.frequency_hi = value
    else             raise "Writing to invalid channel 1 register: #{hex_str index.to_u16!}"
    end
  end
end
