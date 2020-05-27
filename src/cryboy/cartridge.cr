abstract class Cartridge
  @program : Bytes = Bytes.new 0

  getter title : String {
    io = IO::Memory.new
    io.write @program[0x0134...0x13F]
    io.to_s
  }

  getter ram_size : UInt32 {
    case @program[0x0149]
    when 0x01 then 0x0800_u32
    when 0x02 then 0x2000_u32
    when 0x03 then 0x2000_u32 * 4
    when 0x04 then 0x2000_u32 * 16
    when 0x05 then 0x2000_u32 * 8
    else           0x0000_u32
    end
  }

  # open rom, determine MBC type, and initialize the correct cartridge
  def self.new(rom_path : String) : Cartridge
    rom = File.open rom_path do |file|
      bytes = Bytes.new file.size
      file.read bytes
      bytes
    end

    cartridge_type = rom[0x0147]
    case cartridge_type
    when 0x00, 0x08, 0x09 then ROM.new rom
    when 0x01, 0x02, 0x03 then MBC1.new rom
    else                       raise "Unimplemented cartridge type: #{cartridge_type}"
    end
  end

  # create a new Cartridge with the given bytes as rom
  def self.new(rom : Bytes) : Cartridge
    ROM.new rom
  end

  # read from cartridge memory
  abstract def [](index : Int) : UInt8
  abstract def []=(index : Int, value : UInt8) : Nil
end
