require "option_parser"

# kill process after given number of seconds
def kill(process : Process, after : Number = 5) : Nil
  spawn do
    sleep after
    process.signal Signal::KILL if process.exists?
  end
end

acid_dir = ""
mooneye_dir = ""

OptionParser.parse do |parser|
  parser.on("-a PATH", "--acid=PATH", "Path to directory with acid tests") { |path| acid_dir = path }
  parser.on("-m PATH", "--mooneye=PATH", "Path to directory with mooneye tests") { |path| mooneye_dir = path }
  parser.invalid_option do
    STDERR.puts parser
    exit 1
  end
end

puts "\nRunning test roms"

unless acid_dir == ""
  puts "\nAcid Tests"
  puts "Building for acid tests"
  system "shards build"
  puts "Running tests"
  Dir.glob "#{acid_dir}/*acid2.gb*" do |path|
    puts path
    Process.run "bin/cryboy", [path] do |process|
      print "Acknowledge: "
      gets
      process.terminate if process.exists?
    end
  end
end

mooneye_output = "spec/mooneye_test_failures.txt"
unless mooneye_dir == ""
  puts "\nMooneye Tests"
  puts "Building for mooneye tests"
  system "shards build -Dheadless -Dprint_serial"
  puts "Running tests"
  fib_string = "358132134"
  File.write mooneye_output, ""
  File.open mooneye_output, "w" do |file|
    Dir.glob("#{mooneye_dir}/**/*.gb").sort.each do |path|
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
      str_result = "#{msg} - #{path[mooneye_dir.size, path.size - mooneye_dir.size]}"
      puts str_result
      file.puts str_result if msg != "PASS"
    end
  end
end
