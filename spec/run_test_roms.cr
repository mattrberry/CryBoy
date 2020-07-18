require "option_parser"

# kill process after given number of seconds
def kill(process : Process, after : Number = 5) : Nil
  spawn do
    sleep after
    process.signal Signal::KILL if process.exists?
  end
end

build = false
details = false
acid_dir = ""
mooneye_dir = ""

OptionParser.parse do |parser|
  parser.on("-b", "--build", "Tell source to build for release before tests are run") { build = true }
  parser.on("-d", "--details", "Print details on the current stage") { details = true }
  parser.on("-a PATH", "--acid=PATH", "Path to directory with acid tests") { |path| acid_dir = path }
  parser.on("-m PATH", "--mooneye=PATH", "Path to directory with mooneye tests") { |path| mooneye_dir = path }
  parser.invalid_option do
    STDERR.puts parser
    exit 1
  end
end

puts "Building for release" if details
system "shards build --release" if build

puts "\nRunning test roms" if details

unless acid_dir == ""
  puts "\nAcid Tests" if details
  Dir.glob "#{acid_dir}/*acid2.gb*" do |path|
    puts path
    Process.run "bin/cryboy", [path] do |process|
      print "Acknowledge: "
      process.terminate if process.exists?
    end
  end
end

unless mooneye_dir == ""
  puts "\nMooneye Tests" if details
  fib_string = "358132134"
  Dir.glob "#{mooneye_dir}/**/*.gb" do |path|
    next if path.includes?("util") || path.includes?("manual-only")
    passed = false
    Process.run("bin/cryboy", [path]) do |process|
      kill process, after: 10 # seconds
      result = process.output.gets 9
      process.terminate if process.exists?
      passed = result == fib_string
    end
    process_status = $?
    msg = case process_status.exit_status
          when 0 then passed ? "PASS" : "FAIL"
          when 9 then "KILL"
          else        "CRSH"
          end
    puts "#{msg} - #{path}" if msg != "PASS"
  end
end
