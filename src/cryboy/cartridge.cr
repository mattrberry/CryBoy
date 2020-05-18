require "bindata"
require "./memory"

enum BootMode
  Joybus
  Normal
  Multiplay
end

class Cartridge < BinData
  enum CartridgeType
    ROM_ONLY                = 0x00
    MBC1                    = 0x01
    MBC1_RAM                = 0x02
    MBC1_RAM_BATTERY        = 0x03
    MBC2                    = 0x05
    MBC2_BATTERY            = 0x06
    ROM_RAM                 = 0x08
    ROM_RAM_BATTERY         = 0x09
    MMM01                   = 0x0B
    MMM01_RAM               = 0x0C
    MMM01_RAM_BATTERY       = 0x0D
    MBC3_TIMER_BATTERY      = 0x0F
    MBC3_TIMER_RAM_BATTERY  = 0x10
    MBC3                    = 0x11
    MBC3_RAM                = 0x12
    MBC3_RAM_BATTERY        = 0x13
    MBC4                    = 0x15
    MBC4_RAM                = 0x16
    MBC4_RAM_BATTERY        = 0x17
    MBC5                    = 0x19
    MBC5_RAM                = 0x1A
    MBC5_RAM_BATTERY        = 0x1B
    MBC5_RUMBLE             = 0x1C
    MBC5_RUMBLE_RAM         = 0x1D
    MBC5_RUMBLE_RAM_BATTERY = 0x1E
    POCKET_CAMERA           = 0xFC
    BANDAI_TAMA5            = 0xFD
    HuC3                    = 0xFE
    HuC1_RAM_BATTERY        = 0xFF
  end

  enum DestinationCode
    Japanese
    Non_Japanese
  end

  # endian big

  # bytes :unknown, length: ->{ 0x100 }
  # uint32 :entry_point
  # bytes :nintendo_logo, length: ->{ 0x134 - 0x104 }
  # string :title, length: ->{ 0x013F - 0x134 }
  # string :manufacturer_code, length: ->{ 0x143 - 0x13F }
  # uint8 :cgb_flag
  # string :new_licensee_code, length: ->{ 0x146 - 0x144 }
  # uint8 :sgb_flag
  # enum_field UInt8, cartridge_type : CartridgeType = CartridgeType::ROM_ONLY
  # uint8 :rom_size
  # uint8 :ram_size
  # enum_field UInt8, destination_code : DestinationCode = DestinationCode::Japanese
  # uint8 :old_licensee_code
  # uint8 :mask_rom_version_number
  # uint8 :header_checksum, verify: ->{
  #   chk = 0_u8
  #   title.bytes.each { |byte| chk &-= byte; chk &-= 1 }
  #   manufacturer_code.bytes.each { |byte| chk &-= byte; chk &-= 1 }
  #   chk &-= cgb_flag; chk &-= 1
  #   new_licensee_code.bytes.each { |byte| chk &-= byte; chk &-= 1 }
  #   chk &-= sgb_flag; chk &-= 1
  #   chk &-= cartridge_type.value; chk &-= 1
  #   chk &-= rom_size; chk &-= 1
  #   chk &-= ram_size; chk &-= 1
  #   chk &-= destination_code.value; chk &-= 1
  #   chk &-= old_licensee_code; chk &-= 1
  #   chk &-= mask_rom_version_number; chk &-= 1
  #   header_checksum == chk
  # }
  # uint16 :global_checksum
  # remaining_bytes :rom

  # property all_bytes : Bytes = Bytes.new 0

  # def self.new(rom_path : String) : Cartridge
  #   cartridge = File.open rom_path, &.read_bytes Cartridge
  #   cartridge.all_bytes = File.open(rom_path) do |file|
  #     b = Bytes.new file.size
  #     file.read b
  #     b
  #   end
  #   puts cartridge.cartridge_type
  #   cartridge
  # end

  @program : Bytes = Bytes.new 0

  def initialize(rom_path : String)
    File.open rom_path do |file|
      @program = Bytes.new file.size
      file.read @program
    end
    @ram = Bytes.new Memory::EXTERNAL_RAM.size
  end

  def initialize(@program : Bytes)
    @ram = Bytes.new Memory::EXTERNAL_RAM.size
  end

  def [](index : Int) : UInt8
    case index
    when Memory::EXTERNAL_RAM then return @ram[index - Memory::EXTERNAL_RAM.begin]
    else                           return @program[index]
    end
  end

  def []=(index : Int, value : UInt8) : Nil
    @ram[index - Memory::EXTERNAL_RAM.begin] = value if Memory::EXTERNAL_RAM.includes? index
  end
end
