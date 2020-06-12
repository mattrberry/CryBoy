abstract class Cartridge
  @rom : Bytes = Bytes.new 0

  getter title : String {
    io = IO::Memory.new
    io.write @rom[0x0134...0x13F]
    io.to_s
  }

  getter rom_size : UInt32 {
    0x8000_u32 << @rom[0x0148]
  }

  getter ram_size : UInt32 {
    case @rom[0x0149]
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
      rom_size = file.read_at(0x0148, 1) { |io| 0x8000 << io.read_byte.not_nil! }
      file.pos = 0
      bytes = Bytes.new rom_size.not_nil!
      file.read bytes
      bytes
    end

    cartridge_type = rom[0x0147]
    case cartridge_type
    when 0x00, 0x08, 0x09 then ROM.new rom
    when 0x01, 0x02, 0x03 then MBC1.new rom
    when 0x19, 0x1A, 0x1B,
         0x1C, 0x1D, 0x1E then MBC5.new rom
    else raise "Unimplemented cartridge type: #{hex_str cartridge_type}"
    end
  end

  # create a new Cartridge with the given bytes as rom
  def self.new(rom : Bytes) : Cartridge
    ROM.new rom
  end

  # the offset of the given bank number in rom
  def rom_bank_offset(bank_number : Int) : Int
    (bank_number.to_u32 * Memory::ROM_BANK_N.size) % rom_size
  end

  # adjust the index for local rom
  def rom_offset(index : Int) : Int
    index - Memory::ROM_BANK_N.begin
  end

  # the offset of the given bank number in ram
  def ram_bank_offset(bank_number : Int) : Int
    (bank_number.to_u32 * Memory::EXTERNAL_RAM.size) % ram_size
  end

  # adjust the index for local ram
  def ram_offset(index : Int) : Int
    index - Memory::EXTERNAL_RAM.begin
  end

  # read from cartridge memory
  abstract def [](index : Int) : UInt8
  abstract def []=(index : Int, value : UInt8) : Nil
end
