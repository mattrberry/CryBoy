require "compiler/crystal/formatter"
require "compiler/crystal/command/format"
require "http/client"
require "json"

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
      split = name.split(limit: 2)
      split.size <= 1 ? [] of String : split[1].split(',').map { |operand| normalize_operand operand }
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
      operand = operand.sub "hl+", "((hl &+= 1) &- 1)"
      operand = operand.sub "hl-", "((hl &-= 1) &+ 1)"
      operand = operand.sub "ff00+", "0xFF00 &+ "
      operand = operand.sub "sp+i8", "sp &+ i8"
      operand = operand.sub /(\d\d)h/, "0x\\1_u16"
      if group == Group::CONTROL_BR || group == Group::CONTROL_MISC
        # distinguish between "flag c" and "register z"
        operand = operand.sub /\bz\b/, "self.f_z"
        operand = operand.sub /\bnz\b/, "self.f_nz"
        operand = operand.sub /\bc\b/, "self.f_c"
        operand = operand.sub /\bnc\b/, "self.f_nc"
      end
      operand = operand.sub "pc", "@pc"
      operand = operand.sub "sp", "@sp"
      operand = operand.sub "af", "self.af"
      operand = operand.sub "bc", "self.bc"
      operand = operand.sub "de", "self.de"
      operand = operand.sub "hl", "self.hl"
      operand = operand.sub /\ba\b/, "self.a"
      operand = operand.sub /\bf\b/, "self.f"
      operand = operand.sub /\bb\b/, "self.b"
      operand = operand.sub /\bc\b/, "self.c"
      operand = operand.sub /\bd\b/, "self.d"
      operand = operand.sub /\be\b/, "self.e"
      operand = operand.sub /\bh\b/, "self.h"
      operand = operand.sub /\bl\b/, "self.l"
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

    # create a branch condition
    def branch(cond : String, body : Array(String)) : Array(String)
      ["if #{cond}"] + body + set_reset_flags + ["return #{cycles_branch}", "end"]
    end

    # set flag z to the given value if specified by this operation
    def set_flag_z(o : Object) : Array(String)
      flags.z == FlagOp::DEFAULT ? set_flag_z! o : [] of String
    end

    # set flag z to the given value
    def set_flag_z!(o : Object) : Array(String)
      ["self.f_z = #{o.to_s}"]
    end

    # set flag n to the given value if specified by this operation
    def set_flag_n(o : Object) : Array(String)
      flags.n == FlagOp::DEFAULT ? set_flag_n! o : [] of String
    end

    # set flag n to the given value
    def set_flag_n!(o : Object) : Array(String)
      ["self.f_n = #{o.to_s}"]
    end

    # set flag h to the given value if specified by this operation
    def set_flag_h(o : Object) : Array(String)
      flags.h == FlagOp::DEFAULT ? set_flag_h! o : [] of String
    end

    # set flag h to the given value
    def set_flag_h!(o : Object) : Array(String)
      ["self.f_h = #{o.to_s}"]
    end

    # set flag c to the given value if specified by this operation
    def set_flag_c(o : Object) : Array(String)
      flags.c == FlagOp::DEFAULT ? set_flag_c! o : [] of String
    end

    # set flag c to the given value
    def set_flag_c!(o : Object) : Array(String)
      ["self.f_c = #{o.to_s}"]
    end

    # generate code to set/reset flags if necessary
    def set_reset_flags : Array(String)
      (flags.z == FlagOp::ZERO ? set_flag_z! false : [] of String) +
        (flags.z == FlagOp::ONE ? set_flag_z! true : [] of String) +
        (flags.n == FlagOp::ZERO ? set_flag_n! false : [] of String) +
        (flags.n == FlagOp::ONE ? set_flag_n! true : [] of String) +
        (flags.h == FlagOp::ZERO ? set_flag_h! false : [] of String) +
        (flags.h == FlagOp::ONE ? set_flag_h! true : [] of String) +
        (flags.c == FlagOp::ZERO ? set_flag_c! false : [] of String) +
        (flags.c == FlagOp::ONE ? set_flag_c! true : [] of String)
    end

    # switch over operation type and generate code
    private def codegen_help : Array(String)
      case type
      when "ADC"
        to, from = operands
        if to == from
          ["carry = self.f_c ? 0x01 : 0x00"] +
            set_flag_h("(#{to} & 0x0F) + (#{from} & 0x0F) + carry > 0x0F") +
            set_flag_c("#{to} > 0x7F") +
            ["#{to} &+= #{from} &+ carry"] +
            set_flag_z("#{to} == 0")
        else
          ["carry = self.f_c ? 0x01 : 0x00"] +
            set_flag_h("(#{to} & 0x0F) + (#{from} & 0x0F) + carry > 0x0F") +
            ["#{to} &+= #{from} &+ carry"] +
            set_flag_z("#{to} == 0") +
            set_flag_c("#{to} < #{from}.to_u16 + carry")
        end
      when "ADD"
        to, from = operands
        if group == Group::X8_ALU || from == "i8" # `ADD SP, e8` works the same
          if to == from
            set_flag_h("(#{to} & 0x0F) + (#{from} & 0x0F) > 0x0F") +
              set_flag_c("#{to} > 0x7F") +
              ["#{to} &+= #{from}"] +
              set_flag_z("#{to} == 0")
          else
            set_flag_h("(#{to} & 0x0F) + (#{from} & 0x0F) > 0x0F") +
              ["#{to} &+= #{from}"] +
              set_flag_z("#{to} == 0") +
              set_flag_c("#{to} < #{from}")
          end
        elsif group == Group::X16_ALU
          if to == from
            set_flag_h("(#{to} & 0x0FFF).to_u32 + (#{from} & 0x0FFF) > 0x0FFF") +
              set_flag_c("#{to} > 0x7FFF") +
              ["#{to} &+= #{from}"]
          else
            set_flag_h("(#{to} & 0x0FFF).to_u32 + (#{from} & 0x0FFF) > 0x0FFF") +
              ["#{to} &+= #{from}"] +
              set_flag_c("#{to} < #{from}")
          end
        else
          raise "Invalid group #{group} for ADD."
        end
      when "AND"
        to, from = operands
        ["#{to} &= #{from}"] +
          set_flag_z("#{to} == 0")
      when "BIT"
        bit, reg = operands
        set_flag_z("#{reg} & (0x1 << #{bit}) == 0")
      when "CALL"
        instr = ["@sp -= 2", "@memory[@sp] = @pc", "@pc = u16"]
        if operands.size == 1
          instr
        else
          cond, _ = operands
          branch(cond, instr)
        end
      when "CCF"
        set_flag_c("!self.f_c")
      when "CP"
        to, from = operands
        set_flag_z("#{to} &- #{from} == 0") +
          set_flag_h("#{to} & 0xF < #{from} & 0xF") +
          set_flag_c("#{to} < #{from}")
      when "CPL"
        ["self.a = ~self.a"]
      when "DAA"
        [
          "if self.f_n == 0 # last op was an addition",
          "  if self.f_c || self.a > 0x99",
          "    self.a &+= 0x60",
          "    self.f_c = true",
          "  end",
          "  if self.f_h || self.a & 0x0F > 0x09",
          "    self.a &+= 0x06",
          "  end",
          "else # last op was a subtraction",
          "  self.a &-= 0x60 if self.f_c",
          "  self.a &-= 0x06 if self.f_h",
          "end",
        ]
      when "DEC"
        to = operands[0]
        ["#{to} &-= 1"] +
          set_flag_z("#{to} == 0") +
          set_flag_h("#{to} & 0x0F == 0x0F")
      when "DI"
        ["@ime = false"]
      when "EI"
        ["@ime = true"]
      when "HALT"
        ["@halted = true if @ime"]
      when "INC"
        to = operands[0]
        set_flag_h("#{to} & 0x0F == 0x0F") +
          ["#{to} &+= 1"] +
          set_flag_z("#{to} == 0")
      when "JP"
        if operands.size == 1
          ["@pc = #{operands[0]}"]
        else
          cond, loc = operands
          branch(cond, ["@pc = #{loc}"])
        end
      when "JR"
        instr = ["@pc &+= i8"]
        if operands.size == 1
          instr
        else
          cond, _ = operands
          branch(cond, instr)
        end
      when "LD"
        to, from = operands
        ["#{to} = #{from}"] +
          # the following flags _only_ apply to `LD HL, SP + i8`
          set_flag_h("(@sp & 0x0F) + (i8 & 0x0F) > 0x0F") +
          set_flag_c("#{to} < @sp")
      when "NOP"
        [] of String
      when "OR"
        to, from = operands
        ["#{to} |= #{from}"] +
          set_flag_z("#{to} == 0")
      when "POP"
        reg = operands[0]
        ["#{reg} = @memory.read_word (@sp += 2) - 2"] +
          set_flag_z("#{reg} & (0x1 << 7)") +
          set_flag_n("#{reg} & (0x1 << 6)") +
          set_flag_h("#{reg} & (0x1 << 5)") +
          set_flag_c("#{reg} & (0x1 << 4)")
      when "PREFIX"
        [
          "# todo: This should operate as a seperate instruction, but can't be interrupted.",
          "#       This will require a restructure where the CPU leads the timing, rather than the PPU.",
          "#       https://discordapp.com/channels/465585922579103744/465586075830845475/712358911151177818",
          "#       https://discordapp.com/channels/465585922579103744/465586075830845475/712359253255520328",
          "next_op = read_opcode",
          "cycles = process_opcode next_op, cb = true",
          "# izik's table lists all prefixed opcodes as a length of 2 when they should be 1",
          "@pc &-= 1",
        ]
      when "PUSH"
        ["@memory[@sp -= 2] = #{operands[0]}"]
      when "RES"
        bit, reg = operands
        ["#{reg} &= ~(0x1 << #{bit})"]
      when "RET"
        instr = ["@pc = @memory.read_word @sp", "@sp += 2"]
        if operands.size == 0
          instr
        else
          cond = operands[0]
          branch(cond, instr)
        end
      when "RETI"
        ["@ime = true", "@pc = memory.read_word @sp", "@sp += 0x02"]
      when "RL"
        reg = operands[0]
        ["carry = #{reg} & 0x80", "#{reg} = (#{reg} << 1) + (self.f_c ? 0x01 : 0x00)"] +
          set_flag_z("#{reg} == 0") +
          set_flag_c("carry")
      when "RLA"
        ["carry = self.a & 0x80", "self.a = (self.a << 1) + (self.f_c ? 0x01 : 0x00)"] +
          set_flag_c("carry")
      when "RLC"
        reg = operands[0]
        ["#{reg} = (#{reg} << 1) + (#{reg} >> 7)"] +
          set_flag_z("#{reg} == 0") +
          set_flag_c("#{reg} & 0x01")
      when "RLCA"
        ["self.a = (self.a << 1) + (self.a >> 7)"] +
          set_flag_c("self.a & 0x01")
      when "RR"
        reg = operands[0]
        ["carry = #{reg} & 0x01", "#{reg} = (#{reg} >> 1) + (self.f_c ? 0x80 : 0x00)"] +
          set_flag_z("#{reg} == 0") +
          set_flag_c("carry")
      when "RRA"
        ["carry = self.a & 0x01", "self.a = (self.a >> 1) + (self.f_c ? 0x80 : 0x00)"] +
          set_flag_c("carry")
      when "RRC"
        reg = operands[0]
        ["#{reg} = (#{reg} >> 1) + (#{reg} << 7)"] +
          set_flag_z("#{reg} == 0") +
          set_flag_c("#{reg} & 0x80")
      when "RRCA"
        ["self.a = (self.a >> 1) + (self.a << 7)"] +
          set_flag_c("self.a & 0x80")
      when "RST"
        ["@sp -= 2", "@memory[@sp] = @pc", "@pc = #{operands[0]}"]
      when "SBC"
        to, from = operands
        ["to_sub = #{from}.to_u16 + (self.f_c ? 0x01 : 0x00)"] +
          set_flag_h("(#{to} & 0x0F) < (#{from} & 0x0F) + (self.f_c ? 0x01 : 0x00)") +
          set_flag_c("#{to} < to_sub") +
          ["#{to} &-= to_sub"] +
          set_flag_z("#{to} == 0")
      when "SCF"
        # should already be covered by `set_reset_flags`
        [] of String
      when "SET"
        bit, reg = operands
        ["#{reg} |= (0x1 << #{bit})"]
      when "SLA"
        reg = operands[0]
        set_flag_c("#{reg} & 0x80") +
          ["#{reg} <<= 1"] +
          set_flag_z("#{reg} == 0")
      when "SRA"
        reg = operands[0]
        set_flag_c("#{reg} & 0x01") +
          ["#{reg} = (#{reg} >> 1) + (#{reg} & 0x80)"] +
          set_flag_z("#{reg} == 0")
      when "SRL"
        reg = operands[0]
        set_flag_c("#{reg} & 0x1") +
          ["#{reg} >>= 1"] +
          set_flag_z("#{reg} == 0")
      when "STOP"
        ["# todo: see if something more needs to happen here..."]
      when "SUB"
        to, from = operands
        set_flag_h("#{to} & 0x0F < #{from} & 0x0F") +
          set_flag_c("#{to} < #{from}") +
          ["#{to} &-= #{from}"] +
          set_flag_z("#{to} == 0")
      when "SWAP"
        reg = operands[0]
        ["#{reg} = (#{reg} << 4) + (#{reg} >> 4)"] +
          set_flag_z("#{reg} == 0")
      when "UNUSED"
        ["# unused opcode"]
      when "XOR"
        to, from = operands
        ["#{to} ^= #{from}"] +
          set_flag_z("#{to} == 0")
      else ["raise \"Not currently supporting #{name}\""]
      end
    end

    # generate the code required to process this operation
    def codegen : Array(String)
      assign_extra_integers +
        ["@pc &+= #{length}"] +
        codegen_help +
        set_reset_flags +
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
        ["else raise \"Unmatched opcode \#{opcode}\"", "end", "else", "case opcode"] +
        @cb_operations.map_with_index { |operation, index|
          ["when 0x#{index.to_s(16).rjust(2, '0').upcase} # #{operation.name}"] +
            operation.codegen
        } +
        ["else raise \"Unmatched cb-opcode \#{opcode}\"", "end", "end"]).flatten
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
