lib LibC
  fun nanosleep = nanosleep(req : LibC::Timespec*, rem : LibC::Timespec*) : LibC::Int
end

def nanosleep(nanoseconds : Number)
  req = LibC::Timespec.new
  req.tv_nsec = nanoseconds.to_u32
  LibC.nanosleep(pointerof(req), nil)
end

def nanosleep(time_span : Time::Span)
  nanosleep time_span.total_nanoseconds
end

def repeat(hz : Int, &block)
  period = (1_000_000_000 / hz).to_i
  loop do
    start_time = Time.utc
    block.call
    end_time = Time.utc
    next_cycle = start_time + Time::Span.new nanoseconds: period
    if next_cycle > end_time
      # puts "Sleeping in Repeat(hz:#{hz}) for #{next_cycle - end_time}, #{100*(next_cycle - end_time).total_microseconds//(next_cycle - start_time).total_microseconds}%"
      nanosleep next_cycle - end_time
    else
      # puts "Took too long by #{end_time - next_cycle}"
    end
  end
end

def repeat(hz : Int, in_fiber : Bool, &block)
  if in_fiber
    spawn same_thread: false do
      repeat hz, &block
    end
  else
    repeat hz, &block
  end
end

def hex_str(n : UInt8 | UInt16 | UInt32 | UInt64) : String
  "0x#{n.to_s(16).rjust(sizeof(typeof(n)) * 2, '0').upcase}"
end

def array_to_uint8(array : Array(Bool | Int)) : UInt8
  raise "Array needs to have a length of 8" if array.size != 8
  value = 0_u8
  array.each_with_index do |bit, index|
    value |= (bit == false || bit == 0 ? 0 : 1) << (7 - index)
  end
  value
end

def array_to_uint16(array : Array(Bool | Int)) : UInt16
  raise "Array needs to have a length of 16" if array.size != 16
  value = 0_u16
  array.each_with_index do |bit, index|
    value |= (bit == false || bit == 0 ? 0 : 1) << (15 - index)
  end
  value
end

# Crystal's StaticArray is incredibly slow to compile with LLVM.
# This is a workaround solution proposed by Julien Reichardt (@j8r) on the
# Crystal gitter.im channel. Jonne Haß (jhass) confirmed that this will result
# in a (marginally) larger binary and slower instantiation at runtime. This is
# 100% worth the tradeoff in this case, since I'm only ever instantiation a
# StaticArray a few times, and this actually allows the APU to work properly.
# On second thought, Jonne noticed that compiling a StaticArray for release
# turns into this IR: https://p.jhass.eu/8r.txt
# Maybe this workaround will produce a smaller binary in the end anyway ;)
# GitHub issue: https://github.com/crystal-lang/crystal/issues/2485
# GitHub PR: https://github.com/crystal-lang/crystal/pull/9486
struct StaticArray(T, N)
  def self.new!(& : Int32 -> T)
    array = uninitialized self
    buf = array.to_unsafe
    {% for i in 0...N %}
    buf[{{i.id}}] = yield {{i.id}}
    {% end %}
    array
  end
end

macro trace(value, newline = true)
  {% if flag? :trace %}
    {% if newline %}
      puts {{value}}
    {% else %}
      print {{value}}
    {% end %}
  {% end %}
end

macro log(value, newline = true)
  {% if flag?(:log) %}
    {% if newline %}
      puts {{value}}
    {% else %}
      print {{value}}
    {% end %}
  {% end %}
end
