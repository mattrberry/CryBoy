require "option_parser"

SCREENSHOT_DIR = "test_results/screenshots"

# kill process after given number of seconds
def kill(process : Process, after : Number = 5) : Nil
  spawn do
    sleep after
    process.signal Signal::KILL if process.exists?
  end
end

def get_test_name(dir : String, test : String) : String
  test.rpartition('.')[0][dir.size + 1, test.size]
end

alias TestResult = NamedTuple(test: String, pass: Bool)
alias TestSuite = NamedTuple(suite: String, results: Array(TestResult))

test_results : Array(TestSuite) = [] of TestSuite

acid_dir = ""
blargg_dir = ""
mealybug_dir = ""
mooneye_dir = ""

OptionParser.parse do |parser|
  parser.on("-acid PATH", "Path to directory with acid tests") { |path| acid_dir = path }
  parser.on("-blargg PATH", "Path to directory with blargg tests") { |path| blargg = path }
  parser.on("-mealybug PATH", "Path to directory with mealybug tests") { |path| mealybug_dir = path }
  parser.on("-mooneye PATH", "Path to directory with mooneye tests") { |path| mooneye_dir = path }
  parser.invalid_option do
    STDERR.puts parser
    exit 1
  end
end

unless acid_dir == ""
  test_results << {suite: "Acid", results: [] of TestResult}
  puts "Acid Tests"
  system "shards build -Dgraphics_test"
  Dir.glob("#{acid_dir}/*acid2.gb*").sort.each do |path|
    test_name = get_test_name acid_dir, path
    Process.run "bin/cryboy", [path] do |process|
      sleep 1
      system %[import -window "$(xdotool getwindowfocus -f)" #{SCREENSHOT_DIR}/#{test_name}.png]
      system %[compare -metric AE #{SCREENSHOT_DIR}/#{test_name}.png #{SCREENSHOT_DIR}/expected/#{test_name}.png /tmp/cryboy_diff 2>/dev/null]
      passed = $?.exit_status == 0
      process.terminate if process.exists?
      test_results[test_results.size - 1][:results] << {test: test_name, pass: passed}
      print passed ? "." : "F"
    end
  end
  print "\n"
end

unless mooneye_dir == ""
  test_results << {suite: "Mooneye", results: [] of TestResult}
  puts "Mooneye Tests"
  system "shards build -Dheadless -Dprint_serial"
  fib_string = "358132134"
  Dir.glob("#{mooneye_dir}/**/*.gb").sort.each do |path|
    next if path.includes?("util") || path.includes?("manual-only")
    test_name = get_test_name mooneye_dir, path
    passed = false
    Process.run("bin/cryboy", [path]) do |process|
      kill process, after: 10 # seconds
      result = process.output.gets 9
      process.terminate if process.exists?
      passed = result == fib_string
    end
    test_results[test_results.size - 1][:results] << {test: test_name, pass: passed}
    print passed ? "." : "F"
  end
  print "\n"
end

File.open "test_results/readme.md", "w" do |file|
  file.puts "# Test Results"
  test_results.each do |test_suite|
    file.puts "## #{test_suite[:suite]} Tests"
    file.puts "| Result | Test Name |"
    file.puts "|--------|-----------|"
    test_suite[:results].each do |test_result|
      file.puts "| #{test_result[:pass] ? "👌" : "👀"} | #{test_result[:test]} |"
    end
  end
end
