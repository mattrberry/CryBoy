require "compiler/crystal/formatter"
require "compiler/crystal/command/format"
require "http/client"
require "json"

# abstract flag setting so I don't forget to use "self."
# `should_set` allows the code to be generated conditionally
def set_flag_z(o : Object, should_set = true) : Array(String)
  should_set ? ["self.f_z = #{o.to_s}"] : [] of String
end

# abstract flag setting so I don't forget to use "self."
# `should_set` allows the code to be generated conditionally
def set_flag_n(o : Object, should_set = true) : Array(String)
  should_set ? ["self.f_n = #{o.to_s}"] : [] of String
end

# abstract flag setting so I don't forget to use "self."
# `should_set` allows the code to be generated conditionally
def set_flag_h(o : Object, should_set = true) : Array(String)
  should_set ? ["self.f_h = #{o.to_s}"] : [] of String
end

# abstract flag setting so I don't forget to use "self."
# `should_set` allows the code to be generated conditionally
def set_flag_c(o : Object, should_set = true) : Array(String)
  should_set ? ["self.f_c = #{o.to_s}"] : [] of String
end

module DmgOps
  enum FlagOp
    ZERO
    ONE
    UNCHANGED
    DEFAULT
  end

  class Flags
    include JSON::Serializable

    @[JSON::Field(key: "Z")]
    @z : String
    @[JSON::Field(key: "N")]
    @n : String
    @[JSON::Field(key: "H")]
    @h : String
    @[JSON::Field(key: "C")]
    @c : String

    def str_to_flagop(s : String) : FlagOp
      case s
      when "0" then FlagOp::ZERO
      when "1" then FlagOp::ONE
      when "-" then FlagOp::UNCHANGED
      else          FlagOp::DEFAULT
      end
    end

    def z : FlagOp
      str_to_flagop @z
    end

    def n : FlagOp
      str_to_flagop @n
    end

    def h : FlagOp
      str_to_flagop @h
    end

    def c : FlagOp
      str_to_flagop @c
    end

    # generates code to set/reset flags if necessary
    def set_reset : Array(String)
      (self.z == FlagOp::ZERO ? set_flag_z false : [] of String) +
        (self.z == FlagOp::ONE ? set_flag_z true : [] of String) +
        (self.n == FlagOp::ZERO ? set_flag_n false : [] of String) +
        (self.n == FlagOp::ONE ? set_flag_n true : [] of String) +
        (self.h == FlagOp::ZERO ? set_flag_h false : [] of String) +
        (self.h == FlagOp::ONE ? set_flag_h true : [] of String) +
        (self.c == FlagOp::ZERO ? set_flag_c false : [] of String) +
        (self.c == FlagOp::ONE ? set_flag_c true : [] of String)
    end
  end

  enum Group
    X8_LSM
    X16_LSM
    X8_ALU
    X16_ALU
    X8_RSB
    CONTROL_BR
    CONTROL_MISC
  end

  class Operation
    include JSON::Serializable

    @[JSON::Field(key: "Name")]
    property name : String
    @[JSON::Field(key: "Group")]
    @group : String
    @[JSON::Field(key: "TCyclesNoBranch")]
    property cycles : UInt8
    @[JSON::Field(key: "TCyclesBranch")]
    property cycles_branch : UInt8
    @[JSON::Field(key: "Length")]
    property length : UInt8
    @[JSON::Field(key: "Flags")]
    property flags : Flags

    # read the operation type from the name
    def type : String
      @name.split.first
    end

    # read the operation operands from the name
    def operands : Array(String)
      name.split(limit: 2)[1].split(',').map { |operand| normalize_operand operand }
    end

    # read the group as a Group enum
    def group : Group
      case @group
      when "x8/lsm"       then Group::X8_LSM
      when "x16/lsm"      then Group::X16_LSM
      when "x8/alu"       then Group::X8_ALU
      when "x16/alu"      then Group::X16_ALU
      when "x8/rsb"       then Group::X8_RSB
      when "control/br"   then Group::CONTROL_BR
      when "control/misc" then Group::CONTROL_MISC
      else                     raise "Failed to match group #{@group}"
      end
    end

    # normalize an operand to work with the existing cpu methods/fields
    def normalize_operand(operand : String) : String
      operand = operand.downcase
      operand = operand.sub "(", "@memory["
      operand = operand.sub ")", "]"
      operand = operand.sub "hl+", "((hl &+= 1) - 1)"
      operand = operand.sub "hl-", "((hl &-= 1) + 1)"
      operand = operand.sub "ff00+", "0xFF00 &+ "
      operand = operand.sub "pc", "@pc"
      operand = operand.sub "sp", "@sp"
      operand = operand.sub "af", "self.af"
      operand = operand.sub "bc", "self.bc"
      operand = operand.sub "de", "self.de"
      operand = operand.sub "hl", "self.hl"
      if operand.size == 1
        operand = "self.#{operand}"
      end
      operand
    end

    # set u8, u16, and i8 if necessary
    def assign_extra_integers : Array(String)
      if name.includes? "u8"
        return ["u8 = @memory[@pc + 1]"]
      elsif name.includes? "u16"
        return ["u16 = @memory.read_word @pc + 1"]
      elsif name.includes? "i8"
        return ["i8 = @memory[@pc + 1].to_i8!"]
      end
      [] of String
    end

    # switch over operation type and generate code
    private def codegen_help : Array(String)
      case type
      when "INC"
        to = operands[0]
        ["#{to} &+= 1"] +
          set_flag_z("#{to} == 0", flags.z == FlagOp::DEFAULT) +
          set_flag_h("#{to} & 0x10", flags.h == FlagOp::DEFAULT)
      when "LD"
        to, from = operands
        ["#{to} = #{from}"]
      when "NOP"
        [] of String
      else ["raise \"Not currently supporting #{name}\""]
      end
    end

    # generate the code required to process this operation
    def codegen : Array(String)
      assign_extra_integers +
        ["@pc += #{length}"] +
        codegen_help +
        flags.set_reset +
        ["return #{cycles}"]
    end
  end

  class Response
    include JSON::Serializable

    @[JSON::Field(key: "Unprefixed")]
    @operations : Array(Operation)
    @[JSON::Field(key: "CBPrefixed")]
    @cb_operations : Array(Operation)

    def codegen : Array(String)
      (["if !cb", "case opcode"] +
        @operations.map_with_index { |operation, index|
          ["when 0x#{index.to_s(16).rjust(2, '0').upcase} # #{operation.name}"] +
            operation.codegen
        } +
        ["end", "else", "case opcode"] +
        @cb_operations.map_with_index { |operation, index|
          ["when 0x#{index.to_s(16).rjust(2, '0').upcase} # #{operation.name}"] +
            operation.codegen
        } +
        ["end", "end"]).flatten
    end
  end
end

# get izik's opcode table
HTTP::Client.get("https://raw.githubusercontent.com/izik1/gbops/master/dmgops.json") do |response|
  # parse json response
  response = DmgOps::Response.from_json(response.body_io)
  # generate opcode execution code
  codegen = response.codegen.join("\n")
  # format and print to stdout/stderr
  Crystal::Command::FormatCommand.new(["-"], stdin: IO::Memory.new codegen).run
end
