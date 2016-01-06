#!/usr/bin/env bundle exec ruby
require 'optparse'
require 'sqlite3'

DEFAULT_OPTIONS={
  :help  => false,
  :days_back => nil,
  :db    => 'moose_results.db',
}
SEPERATOR="**************************************************************************"
TABLE_SEPERATOR="        "
JUST=40
TABLE_LINE="   --------------------------------------------------------------------------------------------------\n"
@options=DEFAULT_OPTIONS
@db=nil

# Returns options parser object
def options_parser
  optparse = OptionParser.new do|opts|
    # Set a banner
    opts.banner = "Usage: #{File.basename($0)} [options...]"

    opts.on '-d NUM', '--days-back NUM',
            'how many days into the past to use for report generation' do |days_back|
      @options[:days_back] = days_back
    end

    opts.on '--db DATABASE_NAME',
            'sqlite3 database to push data to' do |dbname|
      @options[:db] = dbname
    end

    opts.on '-h', '--help' do
      @options[:help] = true
    end
  end
  optparse
end

def open_db(name)
  @db = SQLite3::Database.open name
end

def number_of_test_runs(time_clause)
  query_str = "select count(distinct(run_date)) as num
  from test_results
  where test_results.test_id >= 0
  %s;"
  res = @db.execute(query_str % time_clause)
  num_tests = res.first.first
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nTest runs in range : #{num_tests}\n"
  formatted_res
end

def most_frequent_exception_traces(time_clause)
  query_str = "select count(*) as num, exception_trace
  from test_results
  where test_results.exception_trace != \"\"
  %s
  group by exception_trace
  order by num DESC
  limit 5;"
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nMost frequent exception traces\n"
  formatted_res += "  |  #{"Occurences".ljust(JUST)}#{TABLE_SEPERATOR}|  #{"Trace".ljust(JUST)}  |\n"
  formatted_res += TABLE_LINE
  res.each do |row|
    trace = row[1]
    formatted_res += "  |  #{row[0].to_s.ljust(JUST)}#{TABLE_SEPERATOR}|  #{"Exception trace:".ljust(JUST)}  |\n"
    trace.split("\\n").each do |tline|
      formatted_res += "  |#{" ".ljust(JUST)}#{TABLE_SEPERATOR}|   #{tline.to_s.ljust(JUST*2)}  |\n"
    end
  formatted_res += TABLE_LINE
  end
  formatted_res
end

def tests_with_most_failures(time_clause)
  query_str = "select count(*) as num, name
  from test_results, tests
  where test_results.test_id = tests.test_id
  %s
  group by tests.test_id
  order by num DESC
  limit 5;"
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nTests with most failures\n"
  formatted_res += "  |  #{"Number of failures".ljust(JUST)}#{TABLE_SEPERATOR}|  #{"Test Name".ljust(JUST)}  |\n"
  formatted_res += TABLE_LINE
  res.each do |row|
    formatted_res += "  |  #{row[0].to_s.ljust(JUST)}#{TABLE_SEPERATOR}|  #{row[1].to_s.ljust(JUST)}  |\n"
    formatted_res += TABLE_LINE
  end
  formatted_res
end

def test_groups_ordered_by_failures(time_clause)
  query_str = "select count(*) as num, test_groups.name
  from test_groups, tests, test_results
  where test_groups.test_id = tests.test_id
  and test_results.test_id = tests.test_id
  %s
  group by test_groups.name
  order by num DESC;"
  res = @db.execute(query_str % time_clause)
  formatted_res = ""
  formatted_res +=  SEPERATOR
  formatted_res += "\nTests Groups with most failures\n"
  formatted_res += "  |  #{"Number of Failures".ljust(JUST)}#{TABLE_SEPERATOR}|  #{"Test Group Name".ljust(JUST)}  |\n"
  formatted_res += TABLE_LINE
  res.each do |row|
    formatted_res += "  |  #{row[0].to_s.ljust(JUST)}#{TABLE_SEPERATOR}|  #{row[1].to_s.ljust(JUST)}  |\n"
    formatted_res += TABLE_LINE
  end
  formatted_res
end

def collect_from_db(days_back)
  time_clause = ""
  if days_back
    time_clause = "and test_results.run_date between datetime('now', '-%d days') AND datetime('now')" % days_back
  end
  res = ""
  res += number_of_test_runs(time_clause)
  res += most_frequent_exception_traces(time_clause)
  res += tests_with_most_failures(time_clause)
  res += test_groups_ordered_by_failures(time_clause)
  res
end

optparse = options_parser
optparse.parse(ARGV)
if @options[:help]
  puts optparse.help
  exit
end
puts SEPERATOR
puts "Automoose Report for #{Time.now().strftime("%Y-%m-%d %H:%M:%S")}"
time_clause = "All recorded test results"
if @options[:days_back]
  time_clause = "Last %d days" % @options[:days_back]
end
puts time_clause
puts SEPERATOR
open_db(@options[:db])
results = collect_from_db(@options[:days_back])
puts results
@db.close
